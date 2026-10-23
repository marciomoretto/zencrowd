#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Mosaico aéreo para contagem — versão local
Versão v3.2.2 — leitura robusta do XMP DJI para GPS/altitude/orientação.

Uso:
    python mosaico_dji.py fotos.zip -o mosaico_saida
    python mosaico_dji.py /caminho/para/fotos -o mosaico_saida

O algoritmo mantém:
- priors de FOV/altura;
- SIFT + RANSAC;
- componentes apenas com arestas "ok";
- calibração global de escala;
- correção de paridade;
- arestas visuais usadas somente para regularização de escala;
- mosaico sem blending e source_map.
"""

import argparse
import atexit
import json
import math
import os
import shutil
import subprocess
import tempfile
import threading
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
import geopandas as gpd

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from PIL import Image
from shapely.geometry import Polygon
from pyproj import CRS, Transformer
from scipy.optimize import least_squares


def console_display(obj):
    """Substituto simples para display() do Jupyter."""
    if isinstance(obj, pd.DataFrame):
        if obj.empty:
            print("[DataFrame vazio]")
        else:
            with pd.option_context(
                "display.max_rows", 200,
                "display.max_columns", 100,
                "display.width", 220,
                "display.max_colwidth", 60,
            ):
                print(obj.to_string(index=False))
        return

    if isinstance(obj, pd.Series):
        print(obj.to_string())
        return

    if isinstance(obj, Image.Image):
        print(f"[Imagem PIL: {obj.size[0]}x{obj.size[1]}]")
        return

    print(obj)


display = console_display


def ensure_exiftool():
    if shutil.which("exiftool") is None:
        raise RuntimeError(
            "ExifTool não encontrado. No Ubuntu/Debian instale com:\n"
            "  sudo apt update && sudo apt install -y libimage-exiftool-perl"
        )


def safe_extract_zip(zip_path, destination):
    destination = Path(destination).resolve()

    with zipfile.ZipFile(zip_path, "r") as z:
        for member in z.infolist():
            target = (destination / member.filename).resolve()

            if (
                destination not in target.parents
                and target != destination
            ):
                raise RuntimeError(
                    f"Caminho inseguro no ZIP: {member.filename}"
                )

        z.extractall(destination)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Monta um mosaico aéreo georreferenciado sem blending "
            "a partir de fotos aproximadamente zenitais de drone."
        )
    )

    parser.add_argument(
        "input",
        type=Path,
        help="Diretório com imagens ou arquivo .zip contendo as fotos."
    )

    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("mosaico_saida"),
        help="Diretório de saída. Padrão: ./mosaico_saida"
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Apaga o diretório de saída se ele já existir e não estiver vazio."
    )

    parser.add_argument(
        "--mosaic-scale",
        type=float,
        default=None,
        help="Multiplicador da resolução do mosaico. Padrão: valor interno (1.0)."
    )

    parser.add_argument(
        "--max-output-pixels",
        type=int,
        default=None,
        help="Limite máximo de pixels do raster final. Padrão: sem limite."
    )

    parser.add_argument(
        "--no-auto-rotate",
        action="store_true",
        help="Desativa a rotação automática do mosaico para a horizontal."
    )

    parser.add_argument(
        "--exclude-suspects",
        action="store_true",
        help="Ativa a exclusão automática das fotos marcadas como suspeitas."
    )

    parser.add_argument(
        "--no-zip",
        action="store_true",
        help="Não cria o ZIP final com os resultados."
    )

    parser.add_argument(
        "--keep-extracted",
        action="store_true",
        help="Se a entrada for ZIP, mantém a pasta temporária extraída após o término."
    )

    return parser.parse_args()


def worker_count():
    """Threads para as etapas paralelas (SIFT e registro de pares); MOSAIC_WORKERS sobrescreve."""
    try:
        configured = int(os.environ.get("MOSAIC_WORKERS", ""))
    except ValueError:
        configured = 0

    if configured > 0:
        return configured

    try:
        available = len(os.sched_getaffinity(0))
    except AttributeError:
        available = os.cpu_count() or 1

    return max(1, min(8, available))


def main():
    # ============================================================
    # CONFIGURAÇÃO
    # ============================================================

    # ----------------------------
    # Pastas
    # ----------------------------

    IMAGE_DIR = None
    OUTPUT_DIR = None


    # ============================================================
    # PRIORS UNIVERSAIS
    # ============================================================
    #
    # Estes valores servem apenas para inicializar a geometria.
    # Eles NÃO são tratados como verdade pelo restante do pipeline.

    DEFAULT_FOV_DIAG_DEG = 84.0
    DEFAULT_HEIGHT_M = 70.0


    # ----------------------------
    # Plausibilidade da altura EXIF
    # ----------------------------

    USE_EXIF_HEIGHT_AS_PRIOR = True

    MIN_PLAUSIBLE_HEIGHT_M = 10.0
    MAX_PLAUSIBLE_HEIGHT_M = 500.0

    AGL_OFFSET_M = 0.0


    # ----------------------------
    # Informação óptica do EXIF
    # ----------------------------

    USE_EXIF_CAMERA_INFO = True

    # FOVs diagonais aproximados da câmera wide/principal.
    # São priors, não calibrações rígidas.
    #
    # A ordem importa: padrões mais específicos vêm primeiro.

    # Atenção: modelos multicâmera como o Mavic 3 Pro podem usar
    # lentes tele. Se FocalLengthIn35mmFormat existir, ele tem
    # prioridade sobre este lookup e permite distinguir a câmera usada.
    #
    MODEL_FOV_PRIORS = [
        ("MAVIC 3 PRO", 84.0),
        ("MAVIC 3", 84.0),

        ("AIR 3S", 84.0),
        ("AIR 3", 82.0),
        ("AIR 2S", 88.0),
        ("MAVIC AIR 2", 84.0),

        ("MINI 4 PRO", 82.1),
        ("MINI 3 PRO", 82.1),
        ("MINI 3", 82.1),
        ("MINI 2", 83.0),

        ("DJI NEO", 117.6),
        ("NEO", 117.6),
    ]


    # ----------------------------
    # Zenitalidade
    # ----------------------------
    #
    # Se houver pitch no EXIF, exigimos que esteja próximo de ±90°.
    # Se não houver pitch, a foto não é descartada automaticamente.

    PITCH_TOL_DEG = 3.0


    # ----------------------------
    # Yaw
    # ----------------------------
    #
    # Ordem de preferência:
    # FlightYawDegree -> GimbalYawDegree -> rumo aproximado pelo GPS.

    ROTATION_OFFSET_DEG = 0.0


    # ============================================================
    # DESCOBERTA DE PARES
    # ============================================================
    #
    # Um par entra na lista de candidatos se satisfizer AO MENOS
    # UMA destas condições:
    #
    # - proximidade temporal;
    # - proximidade entre centros GPS;
    # - overlap dos footprints aproximados.

    TEMPORAL_NEIGHBOR_WINDOW = 3

    PRIOR_MIN_OVERLAP_TO_TRY = 0.02

    GPS_NEIGHBOR_MULTIPLIER = 5.0
    GPS_NEIGHBOR_MIN_M = 80.0
    GPS_NEIGHBOR_MAX_M = 300.0


    # ============================================================
    # SIFT + RANSAC
    # ============================================================

    SIFT_MAX_DIM = 1800
    SIFT_NFEATURES = 6000
    LOWE_RATIO = 0.75

    RANSAC_THRESHOLD_PX = 4.0
    RANSAC_MAX_ITERS = 10000
    RANSAC_CONFIDENCE = 0.999

    MIN_MATCHES_TO_TRY = 25


    # ============================================================
    # CLASSIFICAÇÃO DAS ARESTAS VISUAIS
    # ============================================================
    #
    # A escala não precisa mais ficar colada em 1.
    # Mantemos apenas limites amplos como proteção contra soluções
    # degeneradas.

    OK_MIN_INLIERS = 40
    OK_MIN_INLIER_RATIO = 0.40
    OK_MAX_MEDIAN_ERROR_SIFT_PX = 3.0
    OK_SCALE_MIN = 0.25
    OK_SCALE_MAX = 4.00

    WEAK_MIN_INLIERS = 25
    WEAK_MIN_INLIER_RATIO = 0.25
    WEAK_MAX_MEDIAN_ERROR_SIFT_PX = 4.5
    WEAK_SCALE_MIN = 0.10
    WEAK_SCALE_MAX = 10.00


    # ============================================================
    # OTIMIZAÇÃO
    # ============================================================

    COMPONENT_LOSS_F_SCALE_PX = 10.0
    GEO_FIT_LOSS_F_SCALE_M = 2.0


    # ============================================================
    # CORREÇÃO APRENDIDA DA ALTURA AGL
    # ============================================================
    #
    # RelativeAltitude da DJI é altura relativa ao ponto de decolagem,
    # não necessariamente altura sobre o terreno sob cada fotografia.
    #
    # Componentes visualmente fortes + GPS permitem inferir uma
    # altura efetiva. A diferença:
    #
    #     H_efetiva - RelativeAltitude
    #
    # é tratada como um OFFSET ADITIVO de AGL do voo.
    #
    # Isso é diferente de multiplicar todas as alturas pelo mesmo fator.
    # Em especial, evita exagerar a diferença entre uma foto inicial
    # a 45 m relativos e as fotos posteriores a ~102 m relativos.

    USE_LEARNED_AGL_OFFSET = True

    # Componentes fortes que já possuem arestas "ok" são usados.
    AGL_OFFSET_MIN_COMPONENT_SIZE = 2
    AGL_OFFSET_MIN_SUPPORT_COMPONENTS = 2

    # Proteção contra estimativas absurdas.
    AGL_OFFSET_MIN_M = -100.0
    AGL_OFFSET_MAX_M = 300.0

    # Rejeição robusta quando houver várias estimativas.
    AGL_OFFSET_MAD_Z = 3.5


    # ============================================================
    # CALIBRAÇÃO GLOBAL DE ESCALA DO VOO
    # ============================================================
    #
    # Componentes com >= 2 fotos e arestas "ok" podem ensinar
    # quanto a escala métrica observada por SIFT + GPS difere
    # da escala prevista por FOV x altura.
    #
    # Depois da correção AGL aditiva, esta etapa aprende apenas
    # um RESÍDUO multiplicativo global (por exemplo, pequeno erro de FOV).
    # Ele é aplicado a todos os componentes.

    USE_GLOBAL_FLIGHT_SCALE = True

    GLOBAL_SCALE_MIN_COMPONENT_SIZE = 2

    # Por padrão exigimos pelo menos 2 componentes independentes.
    # Exceção: um único componente com >= 3 fotos também pode
    # fornecer suporte, pois contém mais de uma baseline GPS.
    GLOBAL_SCALE_MIN_SUPPORT_COMPONENTS = 2
    GLOBAL_SCALE_SINGLE_COMPONENT_MIN_IMAGES = 3

    # Proteção contra soluções métricas claramente degeneradas.
    GLOBAL_SCALE_RATIO_MIN = 0.50
    GLOBAL_SCALE_RATIO_MAX = 3.00

    # Rejeição robusta de outliers entre componentes.
    GLOBAL_SCALE_MAD_Z = 3.5

    # Se True, a escala global regulariza também os componentes
    # conectados. Isso é o que evita tamanhos diferentes entre
    # componentes do mesmo voo.
    GLOBAL_SCALE_APPLY_TO_ALL_COMPONENTS = True


    # ============================================================
    # ARESTAS VISUAIS USADAS SOMENTE PARA ESCALA
    # ============================================================
    #
    # Estas arestas NÃO entram no grafo geométrico.
    # Elas servem apenas para regularizar a escala métrica entre
    # componentes que já foram posicionados separadamente.

    USE_SCALE_EDGE_REGULARIZATION = True

    # Restrição à sequência local do voo.
    SCALE_EDGE_MAX_TEMPORAL_GAP = 1

    # Evidência visual mínima.
    #
    # REGRA IMPORTANTE (v3.1.3):
    # uma aresta classificada como "rejeitado" pela etapa geométrica
    # NÃO pode mais recalibrar escala. Isso impede que poucos inliers
    # substituam um prior EXIF coerente.
    #
    # A rede de escala pode usar apenas "ok" e "fraco", além dos
    # critérios quantitativos abaixo.
    SCALE_EDGE_ALLOWED_STATUSES = ("ok", "fraco")

    SCALE_EDGE_MIN_INLIERS = 10
    SCALE_EDGE_MAX_MEDIAN_ERROR_PX = 2.5
    SCALE_EDGE_MAX_ABS_ROTATION_DEG = 3.0

    # Escala relativa B -> A estimada pelo RANSAC.
    SCALE_EDGE_MIN_RELATIVE_SCALE = 0.65
    SCALE_EDGE_MAX_RELATIVE_SCALE = 1.60

    # Peso da equação de escala:
    # sqrt(inliers / max(error, floor))
    SCALE_EDGE_ERROR_FLOOR_PX = 0.50

    # Proteção contra uma correção absurda de um componente.
    SCALE_EDGE_COMPONENT_FACTOR_MIN = 0.50
    SCALE_EDGE_COMPONENT_FACTOR_MAX = 2.00

    # ============================================================
    # DIAGNÓSTICO / EXCLUSÃO
    # ============================================================

    AUTO_EXCLUDE_SUSPECTS = False

    SUSPECT_GPS_DISTANCE_M = 25.0
    SMALL_COMPONENT_MAX_SIZE = 2
    LOW_DEGREE_MAX = 1

    # Apenas alerta sobre conflito entre prior e escala aprendida.
    PRIOR_SCALE_ALERT_MIN = 0.65
    PRIOR_SCALE_ALERT_MAX = 1.55


    # ============================================================
    # ORIENTAÇÃO DO OUTPUT
    # ============================================================

    AUTO_ROTATE_OUTPUT_HORIZONTAL = True
    HORIZONTAL_ANGLE_TOL_DEG = 0.25
    PCA_MAX_POINTS = 200_000


    # ============================================================
    # MOSAICO FINAL
    # ============================================================

    MOSAIC_SCALE = 1.0

    # None = sem teto de pixels: o mosaico usa a resolução máxima das fotos.
    MAX_OUTPUT_PIXELS = None

    # Limite do formato JPEG (libjpeg) por lado da imagem.
    JPEG_MAX_DIMENSION = 65_500
    JPEG_QUALITY = 95


    print("Configuração algorítmica v3.2.2 carregada.")



    args = parse_args()

    INPUT_PATH = args.input.expanduser().resolve()
    OUTPUT_DIR = args.output_dir.expanduser().resolve()

    if not INPUT_PATH.exists():
        raise FileNotFoundError(
            f"Entrada não encontrada: {INPUT_PATH}"
        )

    if args.mosaic_scale is not None:
        if args.mosaic_scale <= 0:
            raise ValueError("--mosaic-scale precisa ser > 0.")
        MOSAIC_SCALE = float(args.mosaic_scale)

    if args.max_output_pixels is not None:
        if args.max_output_pixels <= 0:
            raise ValueError("--max-output-pixels precisa ser > 0.")
        MAX_OUTPUT_PIXELS = int(args.max_output_pixels)

    if args.no_auto_rotate:
        AUTO_ROTATE_OUTPUT_HORIZONTAL = False

    if args.exclude_suspects:
        AUTO_EXCLUDE_SUSPECTS = True


    # ============================================================
    # DIRETÓRIO DE SAÍDA
    # ============================================================

    if OUTPUT_DIR.exists() and any(OUTPUT_DIR.iterdir()):
        if not args.overwrite:
            raise RuntimeError(
                f"O diretório de saída já existe e não está vazio:\n"
                f"  {OUTPUT_DIR}\n\n"
                "Use --overwrite para apagá-lo antes de executar."
            )

        shutil.rmtree(OUTPUT_DIR)

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )


    # ============================================================
    # PREPARAR IMAGENS
    # ============================================================

    _temp_extract_dir = None

    if INPUT_PATH.is_dir():

        IMAGE_DIR = INPUT_PATH

    elif (
        INPUT_PATH.is_file()
        and
        INPUT_PATH.suffix.lower() == ".zip"
    ):

        _temp_extract_dir = Path(
            tempfile.mkdtemp(
                prefix="mosaico_dji_"
            )
        )

        IMAGE_DIR = _temp_extract_dir

        print(
            "Extraindo ZIP para pasta temporária:",
            IMAGE_DIR
        )

        safe_extract_zip(
            INPUT_PATH,
            IMAGE_DIR
        )

    else:

        raise ValueError(
            "A entrada precisa ser um diretório ou um arquivo .zip."
        )


    def _cleanup_temp():
        if (
            _temp_extract_dir is not None
            and
            _temp_extract_dir.exists()
            and
            not args.keep_extracted
        ):
            shutil.rmtree(
                _temp_extract_dir,
                ignore_errors=True
            )


    atexit.register(
        _cleanup_temp
    )


    IMAGE_EXTS = {
        ".jpg",
        ".jpeg",
        ".png",
        ".tif",
        ".tiff",
    }


    image_files = sorted([
        p
        for p in IMAGE_DIR.rglob("*")
        if (
            p.is_file()
            and
            p.suffix.lower() in IMAGE_EXTS
            and
            "__MACOSX" not in p.parts
        )
    ])


    print()
    print("=" * 75)
    print("ENTRADA")
    print("=" * 75)
    print("Entrada:", INPUT_PATH)
    print("Imagens:", len(image_files))
    print("Saída:", OUTPUT_DIR)
    print()


    if not image_files:
        raise RuntimeError(
            "Nenhuma imagem compatível encontrada."
        )


    ensure_exiftool()



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 9
    # ===========================================================================
    def extract_exiftool_metadata(image_dir):
        """
        Extrai os metadados gerais e, em uma segunda chamada,
        lê explicitamente o namespace XMP-drone-dji.

        Motivo:
        alguns JPEGs DJI possuem um GPS EXIF tradicional vazio/NaN,
        mas preservam coordenadas válidas no XMP:

            XMP-drone-dji:GPSLatitude
            XMP-drone-dji:GPSLongitude

        Sem separar os grupos, o ExifTool pode expor o campo EXIF
        vazio sob o mesmo nome lógico e o pipeline conclui
        incorretamente que a foto não tem GPS.
        """

        # --------------------------------------------------------
        # 1) Metadados gerais
        # --------------------------------------------------------

        cmd = [
            "exiftool",
            "-json", "-n", "-r",
            "-ext", "jpg", "-ext", "jpeg",
            "-ext", "JPG", "-ext", "JPEG",
            "-ext", "tif", "-ext", "tiff",
            "-ext", "TIF", "-ext", "TIFF",
            "-ext", "png", "-ext", "PNG",
            str(image_dir),
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        general_rows = json.loads(
            result.stdout
        )

        # --------------------------------------------------------
        # 2) Namespace DJI XMP explicitamente, com grupos
        # --------------------------------------------------------

        xmp_cmd = [
            "exiftool",
            "-json",
            "-n",
            "-r",
            "-G1",

            "-XMP-drone-dji:GPSLatitude",
            "-XMP-drone-dji:GPSLongitude",
            "-XMP-drone-dji:AbsoluteAltitude",
            "-XMP-drone-dji:RelativeAltitude",
            "-XMP-drone-dji:GimbalPitchDegree",
            "-XMP-drone-dji:GimbalYawDegree",
            "-XMP-drone-dji:GimbalRollDegree",
            "-XMP-drone-dji:FlightYawDegree",
            "-XMP-drone-dji:FlightPitchDegree",
            "-XMP-drone-dji:FlightRollDegree",

            "-ext", "jpg", "-ext", "jpeg",
            "-ext", "JPG", "-ext", "JPEG",
            "-ext", "tif", "-ext", "tiff",
            "-ext", "TIF", "-ext", "TIFF",
            "-ext", "png", "-ext", "PNG",

            str(image_dir),
        ]

        xmp_result = subprocess.run(
            xmp_cmd,
            capture_output=True,
            text=True,
            check=True
        )

        xmp_rows = json.loads(
            xmp_result.stdout
        )


        def grouped_tag_value(
            record,
            tag_name
        ):
            """
            Procura um tag dentro do grupo XMP-drone-dji,
            tolerando diferenças de capitalização do ExifTool.
            """

            wanted_tag = str(
                tag_name
            ).lower()

            for key, value in record.items():

                key_lower = str(
                    key
                ).lower()

                if (
                    "xmp-drone-dji" in key_lower
                    and
                    key_lower.split(":")[-1]
                    ==
                    wanted_tag
                ):
                    return value

            return np.nan


        # --------------------------------------------------------
        # 3) Índice pelo SourceFile
        # --------------------------------------------------------

        xmp_by_source = {}

        for row in xmp_rows:

            source = row.get(
                "SourceFile"
            )

            if source is None:
                # Segurança para uma eventual representação agrupada.
                for key, value in row.items():
                    if str(key).lower().endswith(
                        "sourcefile"
                    ):
                        source = value
                        break

            if source is None:
                continue

            xmp_by_source[
                str(source)
            ] = row


        # --------------------------------------------------------
        # 4) Enriquecer os registros gerais com nomes únicos
        # --------------------------------------------------------

        mapping = {
            "DJI_XMP_GPSLatitude":
                "gpslatitude",

            "DJI_XMP_GPSLongitude":
                "gpslongitude",

            "DJI_XMP_AbsoluteAltitude":
                "absolutealtitude",

            "DJI_XMP_RelativeAltitude":
                "relativealtitude",

            "DJI_XMP_GimbalPitchDegree":
                "gimbalpitchdegree",

            "DJI_XMP_GimbalYawDegree":
                "gimbalyawdegree",

            "DJI_XMP_GimbalRollDegree":
                "gimbalrolldegree",

            "DJI_XMP_FlightYawDegree":
                "flightyawdegree",

            "DJI_XMP_FlightPitchDegree":
                "flightpitchdegree",

            "DJI_XMP_FlightRollDegree":
                "flightrolldegree",
        }


        for row in general_rows:

            source = str(
                row.get(
                    "SourceFile",
                    ""
                )
            )

            xmp_row = xmp_by_source.get(
                source
            )

            if xmp_row is None:
                continue

            for output_name, tag_name in mapping.items():

                row[
                    output_name
                ] = grouped_tag_value(
                    xmp_row,
                    tag_name
                )


        return pd.DataFrame(
            general_rows
        )


    def normalize_name(value):
        return "".join(
            ch.lower()
            for ch in str(value)
            if ch.isalnum()
        )


    def pick_column(df, candidates, required=False):
        normalized = {
            normalize_name(c): c
            for c in df.columns
        }

        for candidate in candidates:
            key = normalize_name(candidate)

            if key in normalized:
                return normalized[key]

        if required:
            raise KeyError(
                f"Nenhuma coluna encontrada entre {candidates}. "
                f"Disponíveis: {list(df.columns)}"
            )

        return None


    def numeric_col(df, candidates, required=False):
        col = pick_column(
            df,
            candidates,
            required=required
        )

        if col is None:
            return (
                pd.Series(
                    np.nan,
                    index=df.index,
                    dtype=float
                ),
                None
            )

        return (
            pd.to_numeric(
                df[col],
                errors="coerce"
            ),
            col
        )


    def text_col(df, candidates):
        col = pick_column(
            df,
            candidates,
            required=False
        )

        if col is None:
            return (
                pd.Series(
                    "",
                    index=df.index,
                    dtype="object"
                ),
                None
            )

        return (
            df[col]
            .fillna("")
            .astype(str),
            col
        )


    def parse_exif_datetime(series):
        text = (
            series
            .astype(str)
            .str.replace(
                r"^(\d{4}):(\d{2}):(\d{2})",
                r"\1-\2-\3",
                regex=True
            )
        )

        return pd.to_datetime(
            text,
            errors="coerce"
        )


    def fov_diag_from_35mm_equivalent(focal_35mm):
        """
        Converte distância focal equivalente em 35 mm para
        FOV diagonal usando o quadro 36 x 24 mm.

        É um prior óptico, não uma calibração fotogramétrica.
        """
        if not np.isfinite(focal_35mm):
            return np.nan

        if focal_35mm < 8 or focal_35mm > 500:
            return np.nan

        diag_35 = math.hypot(
            36.0,
            24.0
        )

        return math.degrees(
            2.0
            *
            math.atan(
                diag_35
                /
                (2.0 * focal_35mm)
            )
        )


    def infer_model_fov_prior(model_text):
        text = str(
            model_text
        ).upper()

        for pattern, fov in MODEL_FOV_PRIORS:
            if pattern in text:
                return float(fov), pattern

        return np.nan, None


    def choose_height_prior(relative_altitude):
        """
        Hierarquia:
            1) RelativeAltitude plausível;
            2) fallback universal de 70 m.
        """
        if (
            USE_EXIF_HEIGHT_AS_PRIOR
            and
            np.isfinite(relative_altitude)
            and
            MIN_PLAUSIBLE_HEIGHT_M
            <= relative_altitude
            <= MAX_PLAUSIBLE_HEIGHT_M
        ):
            return (
                float(relative_altitude)
                + AGL_OFFSET_M,
                "exif_relative_altitude",
                "medium"
            )

        return (
            float(DEFAULT_HEIGHT_M),
            "default_70m",
            "low"
        )


    def choose_fov_prior(
        focal_35mm,
        camera_text
    ):
        """
        Hierarquia:
            1) focal equivalente 35 mm;
            2) lookup pelo modelo;
            3) prior universal de 84°.
        """

        if USE_EXIF_CAMERA_INFO:
            fov_35 = fov_diag_from_35mm_equivalent(
                focal_35mm
            )

            if np.isfinite(fov_35):
                return (
                    float(fov_35),
                    "exif_focal_35mm",
                    "high"
                )

            model_fov, pattern = infer_model_fov_prior(
                camera_text
            )

            if np.isfinite(model_fov):
                return (
                    float(model_fov),
                    f"model_lookup:{pattern}",
                    "medium"
                )

        return (
            float(DEFAULT_FOV_DIAG_DEG),
            "default_84deg",
            "low"
        )


    # ============================================================
    # EXTRAIR EXIF
    # ============================================================

    raw_meta = extract_exiftool_metadata(
        IMAGE_DIR
    )

    if raw_meta.empty:
        raise RuntimeError(
            "ExifTool não retornou metadados."
        )


    raw_meta.to_csv(
        OUTPUT_DIR
        /
        "metadata_exiftool_bruto.csv",
        index=False
    )


    df = raw_meta.copy()


    # ============================================================
    # COLUNAS PRINCIPAIS
    # ============================================================

    source_col = pick_column(
        df,
        ["SourceFile"],
        required=True
    )


    lat, _ = numeric_col(
        df,
        [
            "DJI_XMP_GPSLatitude",
            "GPSLatitude",
            "DJIGPSLatitude"
        ],
        required=True
    )


    lon, _ = numeric_col(
        df,
        [
            "DJI_XMP_GPSLongitude",
            "GPSLongitude",
            "DJIGPSLongitude"
        ],
        required=True
    )


    rel_alt, rel_alt_col = numeric_col(
        df,
        [
            "DJI_XMP_RelativeAltitude",
            "RelativeAltitude",
            "DJIRelativeAltitude"
        ],
        required=False
    )


    abs_alt, abs_alt_col = numeric_col(
        df,
        [
            "DJI_XMP_AbsoluteAltitude",
            "AbsoluteAltitude",
            "DJIAbsoluteAltitude"
        ],
        required=False
    )


    gimbal_pitch, _ = numeric_col(
        df,
        [
            "DJI_XMP_GimbalPitchDegree",
            "GimbalPitchDegree",
            "DJIGimbalPitchDegree"
        ],
        required=False
    )


    flight_yaw, _ = numeric_col(
        df,
        [
            "DJI_XMP_FlightYawDegree",
            "FlightYawDegree",
            "DJIFlightYawDegree"
        ],
        required=False
    )


    gimbal_yaw, _ = numeric_col(
        df,
        [
            "DJI_XMP_GimbalYawDegree",
            "GimbalYawDegree",
            "DJIGimbalYawDegree"
        ],
        required=False
    )


    focal_35, _ = numeric_col(
        df,
        [
            "FocalLengthIn35mmFormat",
            "FocalLengthIn35mmFilm",
            "FocalLength35efl"
        ],
        required=False
    )


    make_text, _ = text_col(
        df,
        [
            "Make",
            "CameraMake"
        ]
    )


    model_text, _ = text_col(
        df,
        [
            "Model",
            "CameraModelName"
        ]
    )


    lens_text, _ = text_col(
        df,
        [
            "LensModel",
            "Lens"
        ]
    )


    datetime_col = pick_column(
        df,
        [
            "SubSecDateTimeOriginal",
            "DateTimeOriginal",
            "CreateDate"
        ],
        required=False
    )


    # ============================================================
    # NORMALIZAÇÃO
    # ============================================================

    df["filename"] = df[
        source_col
    ].map(
        lambda x: Path(
            str(x)
        ).name
    )


    df["source_path"] = (
        df[source_col]
        .astype(str)
    )


    df["gps_latitude"] = lat
    df["gps_longitude"] = lon

    df["relative_altitude_m"] = rel_alt
    df["absolute_altitude_m"] = abs_alt
    df["gimbal_pitch_deg"] = gimbal_pitch
    df["flight_yaw_deg"] = flight_yaw
    df["gimbal_yaw_deg"] = gimbal_yaw

    df["focal_35mm"] = focal_35

    df["camera_make"] = make_text
    df["camera_model"] = model_text
    df["lens_model"] = lens_text

    df["camera_text"] = (
        df[
            [
                "camera_make",
                "camera_model",
                "lens_model"
            ]
        ]
        .fillna("")
        .astype(str)
        .agg(
            " | ".join,
            axis=1
        )
    )


    if datetime_col is not None:
        df["capture_time"] = parse_exif_datetime(
            df[datetime_col]
        )
    else:
        df["capture_time"] = pd.NaT


    # ============================================================
    # PRIORS POR FOTO
    # ============================================================

    height_prior_values = []
    height_prior_sources = []
    height_prior_confidences = []

    fov_prior_values = []
    fov_prior_sources = []
    fov_prior_confidences = []


    for _, row in df.iterrows():

        (
            h_prior,
            h_source,
            h_conf
        ) = choose_height_prior(
            float(
                row["relative_altitude_m"]
            )
            if pd.notna(
                row["relative_altitude_m"]
            )
            else np.nan
        )

        (
            fov_prior,
            fov_source,
            fov_conf
        ) = choose_fov_prior(
            float(
                row["focal_35mm"]
            )
            if pd.notna(
                row["focal_35mm"]
            )
            else np.nan,
            row["camera_text"]
        )

        height_prior_values.append(
            h_prior
        )

        height_prior_sources.append(
            h_source
        )

        height_prior_confidences.append(
            h_conf
        )

        fov_prior_values.append(
            fov_prior
        )

        fov_prior_sources.append(
            fov_source
        )

        fov_prior_confidences.append(
            fov_conf
        )


    df["height_prior_m"] = (
        height_prior_values
    )

    df["height_prior_source"] = (
        height_prior_sources
    )

    df["height_prior_confidence"] = (
        height_prior_confidences
    )


    df["fov_diag_prior_deg"] = (
        fov_prior_values
    )

    df["fov_prior_source"] = (
        fov_prior_sources
    )

    df["fov_prior_confidence"] = (
        fov_prior_confidences
    )


    # ============================================================
    # DIAGNÓSTICO DA ORIGEM DOS METADADOS
    # ============================================================

    xmp_gps_count = int(
        (
            pd.to_numeric(
                df.get(
                    "DJI_XMP_GPSLatitude",
                    pd.Series(
                        np.nan,
                        index=df.index
                    )
                ),
                errors="coerce"
            ).notna()
            &
            pd.to_numeric(
                df.get(
                    "DJI_XMP_GPSLongitude",
                    pd.Series(
                        np.nan,
                        index=df.index
                    )
                ),
                errors="coerce"
            ).notna()
        ).sum()
    )

    usable_normalized_gps_count = int(
        (
            df[
                "gps_latitude"
            ].between(
                -90,
                90
            )
            &
            df[
                "gps_longitude"
            ].between(
                -180,
                180
            )
        ).sum()
    )

    print()
    print(
        "GPS válido no XMP DJI:",
        xmp_gps_count,
        "/",
        len(
            df
        )
    )

    print(
        "GPS válido após normalização:",
        usable_normalized_gps_count,
        "/",
        len(
            df
        )
    )


    # ============================================================
    # FILTRO
    # ============================================================
    #
    # GPS continua obrigatório para georreferenciamento.
    #
    # Pitch:
    # - se conhecido, deve estar próximo do zenital;
    # - se desconhecido, não eliminamos a foto.
    #
    # NÃO filtramos mais por altura.
    # NÃO exigimos yaw no EXIF.

    gps_ok = (
        df["gps_latitude"].between(
            -90,
            90
        )
        &
        df["gps_longitude"].between(
            -180,
            180
        )
    )


    pitch_known = (
        df["gimbal_pitch_deg"]
        .notna()
    )


    pitch_zenith = (
        (
            df["gimbal_pitch_deg"]
            .abs()
            -
            90.0
        )
        .abs()
        <=
        PITCH_TOL_DEG
    )


    pitch_ok = (
        ~pitch_known
        |
        pitch_zenith
    )


    df["selected"] = (
        gps_ok
        &
        pitch_ok
    )


    print(
        "Total:",
        len(df)
    )

    print(
        "Selecionadas:",
        int(
            df["selected"].sum()
        )
    )

    print()
    print(
        "Fonte do prior de altura:"
    )

    print(
        df.loc[
            df["selected"],
            "height_prior_source"
        ]
        .value_counts(
            dropna=False
        )
    )

    print()
    print(
        "Fonte do prior de FOV:"
    )

    print(
        df.loc[
            df["selected"],
            "fov_prior_source"
        ]
        .value_counts(
            dropna=False
        )
    )


    work = (
        df.loc[
            df["selected"]
        ]
        .copy()
    )


    if work.empty:
        raise RuntimeError(
            "Nenhuma foto passou pelos filtros."
        )


    if (
        work["capture_time"]
        .notna()
        .any()
    ):
        work = work.sort_values(
            [
                "capture_time",
                "filename"
            ]
        )
    else:
        work = work.sort_values(
            "filename"
        )


    work = work.reset_index(
        drop=True
    )


    df.to_csv(
        OUTPUT_DIR
        /
        "metadata_normalizado.csv",
        index=False
    )


    display(
        work[
            [
                c
                for c in [
                    "filename",
                    "camera_model",
                    "focal_35mm",
                    "relative_altitude_m",
                    "absolute_altitude_m",
                    "height_prior_m",
                    "height_prior_source",
                    "fov_diag_prior_deg",
                    "fov_prior_source",
                    "flight_yaw_deg",
                    "gimbal_yaw_deg",
                ]
                if c in work.columns
            ]
        ]
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 11
    # ===========================================================================
    def diag_fov_to_hv(
        fov_diag_deg,
        width,
        height
    ):
        """
        Converte FOV diagonal em horizontal e vertical usando
        o aspect ratio REAL da fotografia.
        """

        if width <= 0 or height <= 0:
            raise ValueError(
                "Dimensões inválidas."
            )

        diag_ar = math.hypot(
            width,
            height
        )

        alpha = math.radians(
            fov_diag_deg / 2.0
        )

        fov_w = (
            2.0
            *
            math.atan(
                (width / diag_ar)
                *
                math.tan(alpha)
            )
        )

        fov_h = (
            2.0
            *
            math.atan(
                (height / diag_ar)
                *
                math.tan(alpha)
            )
        )

        return (
            fov_w,
            fov_h
        )


    def utm_crs_from_lon_lat(
        lon,
        lat
    ):
        zone = (
            int(
                (lon + 180)
                //
                6
            )
            +
            1
        )

        epsg = (
            32600 + zone
            if lat >= 0
            else 32700 + zone
        )

        return CRS.from_epsg(
            epsg
        )


    def transform_points(
        T,
        points
    ):
        pts = np.asarray(
            points,
            dtype=np.float64
        )

        pts_h = np.column_stack([
            pts,
            np.ones(
                len(pts)
            )
        ])

        out = (
            T
            @
            pts_h.T
        ).T

        return out[:, :2]


    def image_corners(
        width,
        height
    ):
        return np.array([
            [0, 0],
            [width - 1, 0],
            [width - 1, height - 1],
            [0, height - 1],
        ], dtype=np.float64)


    def coarse_pixel_to_utm_transform(
        x0,
        y0,
        half_w,
        half_h,
        width,
        height,
        rotation_deg
    ):
        sx = (
            2.0
            *
            half_w
            /
            max(
                width - 1,
                1
            )
        )

        sy = (
            2.0
            *
            half_h
            /
            max(
                height - 1,
                1
            )
        )

        pixel_to_local = np.array([
            [
                sx,
                0.0,
                -half_w
            ],
            [
                0.0,
                -sy,
                half_h
            ],
            [
                0.0,
                0.0,
                1.0
            ],
        ], dtype=np.float64)

        theta = math.radians(
            rotation_deg
        )

        c = math.cos(
            theta
        )

        s = math.sin(
            theta
        )

        rotate = np.array([
            [
                c,
                -s,
                0.0
            ],
            [
                s,
                c,
                0.0
            ],
            [
                0.0,
                0.0,
                1.0
            ],
        ], dtype=np.float64)

        translate = np.array([
            [
                1.0,
                0.0,
                x0
            ],
            [
                0.0,
                1.0,
                y0
            ],
            [
                0.0,
                0.0,
                1.0
            ],
        ], dtype=np.float64)

        return (
            translate
            @
            rotate
            @
            pixel_to_local
        )


    def course_yaw_from_centers(
        xs,
        ys
    ):
        """
        Estima rumo em graus:
            0 = norte
            90 = leste

        Usa diferença central quando possível.
        """

        xs = np.asarray(
            xs,
            dtype=np.float64
        )

        ys = np.asarray(
            ys,
            dtype=np.float64
        )

        n = len(xs)

        result = np.full(
            n,
            np.nan,
            dtype=np.float64
        )

        if n < 2:
            return result

        for i in range(n):

            if i == 0:
                dx = (
                    xs[1]
                    -
                    xs[0]
                )

                dy = (
                    ys[1]
                    -
                    ys[0]
                )

            elif i == n - 1:
                dx = (
                    xs[-1]
                    -
                    xs[-2]
                )

                dy = (
                    ys[-1]
                    -
                    ys[-2]
                )

            else:
                dx = (
                    xs[i + 1]
                    -
                    xs[i - 1]
                )

                dy = (
                    ys[i + 1]
                    -
                    ys[i - 1]
                )

            if (
                dx * dx
                +
                dy * dy
            ) < 1.0:
                continue

            result[i] = (
                math.degrees(
                    math.atan2(
                        dx,
                        dy
                    )
                )
                %
                360.0
            )

        return result


    def choose_yaw_prior(
        flight_yaw,
        gimbal_yaw,
        course_yaw
    ):
        if np.isfinite(
            flight_yaw
        ):
            return (
                float(flight_yaw),
                "exif_flight_yaw",
                "high"
            )

        if np.isfinite(
            gimbal_yaw
        ):
            return (
                float(gimbal_yaw),
                "exif_gimbal_yaw",
                "medium"
            )

        if np.isfinite(
            course_yaw
        ):
            return (
                float(course_yaw),
                "gps_course",
                "low"
            )

        return (
            0.0,
            "fallback_zero",
            "very_low"
        )


    # ============================================================
    # CRS UTM
    # ============================================================

    median_lon = float(
        work[
            "gps_longitude"
        ].median()
    )

    median_lat = float(
        work[
            "gps_latitude"
        ].median()
    )


    TARGET_CRS = utm_crs_from_lon_lat(
        median_lon,
        median_lat
    )


    gps_transformer = Transformer.from_crs(
        "EPSG:4326",
        TARGET_CRS,
        always_xy=True
    )


    # ============================================================
    # CENTROS GPS EM UTM
    # ============================================================

    centers_x = []
    centers_y = []


    for _, row in work.iterrows():

        x0, y0 = gps_transformer.transform(
            float(
                row["gps_longitude"]
            ),
            float(
                row["gps_latitude"]
            )
        )

        centers_x.append(
            float(x0)
        )

        centers_y.append(
            float(y0)
        )


    course_yaws = course_yaw_from_centers(
        centers_x,
        centers_y
    )


    # ============================================================
    # FOOTPRINTS PRIORS
    # ============================================================

    records = []


    for pos, (_, row) in enumerate(
        work.iterrows()
    ):

        path = Path(
            row["source_path"]
        )

        try:

            with Image.open(
                path
            ) as im:
                width, height = im.size


            x0 = centers_x[
                pos
            ]

            y0 = centers_y[
                pos
            ]


            H_prior = float(
                row[
                    "height_prior_m"
                ]
            )


            fov_diag_prior = float(
                row[
                    "fov_diag_prior_deg"
                ]
            )


            (
                fov_w_rad,
                fov_h_rad

            ) = diag_fov_to_hv(

                fov_diag_prior,
                width,
                height

            )


            half_w = (
                H_prior
                *
                math.tan(
                    fov_w_rad / 2.0
                )
            )


            half_h = (
                H_prior
                *
                math.tan(
                    fov_h_rad / 2.0
                )
            )


            flight_yaw = (
                float(
                    row["flight_yaw_deg"]
                )
                if pd.notna(
                    row["flight_yaw_deg"]
                )
                else np.nan
            )


            gimbal_yaw = (
                float(
                    row["gimbal_yaw_deg"]
                )
                if pd.notna(
                    row["gimbal_yaw_deg"]
                )
                else np.nan
            )


            (
                yaw_prior,
                yaw_source,
                yaw_confidence

            ) = choose_yaw_prior(

                flight_yaw,
                gimbal_yaw,
                course_yaws[pos]

            )


            rotation_deg = (
                -yaw_prior
                +
                ROTATION_OFFSET_DEG
            )


            T = coarse_pixel_to_utm_transform(
                x0=x0,
                y0=y0,
                half_w=half_w,
                half_h=half_h,
                width=width,
                height=height,
                rotation_deg=rotation_deg
            )


            corners_utm = transform_points(
                T,
                image_corners(
                    width,
                    height
                )
            )


            prior_m_per_px_x = (
                2.0
                *
                half_w
                /
                max(
                    width - 1,
                    1
                )
            )


            prior_m_per_px_y = (
                2.0
                *
                half_h
                /
                max(
                    height - 1,
                    1
                )
            )


            prior_m_per_px = math.sqrt(
                prior_m_per_px_x
                *
                prior_m_per_px_y
            )


            rec = row.to_dict()


            rec.update({
                "geometry":
                    Polygon(
                        corners_utm
                    ),

                "x0":
                    x0,

                "y0":
                    y0,

                "height_prior_m":
                    H_prior,

                "fov_diag_prior_deg":
                    fov_diag_prior,

                "fov_w_prior_deg":
                    math.degrees(
                        fov_w_rad
                    ),

                "fov_h_prior_deg":
                    math.degrees(
                        fov_h_rad
                    ),

                "yaw_prior_deg":
                    yaw_prior,

                "yaw_prior_source":
                    yaw_source,

                "yaw_prior_confidence":
                    yaw_confidence,

                "rotation_deg":
                    rotation_deg,

                "half_w":
                    half_w,

                "half_h":
                    half_h,

                "prior_m_per_px":
                    prior_m_per_px,

                "image_width":
                    width,

                "image_height":
                    height,
            })


            records.append(
                rec
            )


        except Exception as e:

            print(
                f"[WARN] "
                f"{row['filename']}: "
                f"{e}"
            )


    if not records:
        raise RuntimeError(
            "Nenhum footprint prior calculado."
        )


    gdf = gpd.GeoDataFrame(
        records,
        geometry="geometry",
        crs=TARGET_CRS
    ).reset_index(
        drop=True
    )


    coarse_T_utm = {}


    for i, row in gdf.iterrows():

        coarse_T_utm[
            i
        ] = coarse_pixel_to_utm_transform(

            x0=float(
                row["x0"]
            ),

            y0=float(
                row["y0"]
            ),

            half_w=float(
                row["half_w"]
            ),

            half_h=float(
                row["half_h"]
            ),

            width=int(
                row["image_width"]
            ),

            height=int(
                row["image_height"]
            ),

            rotation_deg=float(
                row["rotation_deg"]
            )

        )


    gdf.to_file(
        OUTPUT_DIR
        /
        "footprints_prior.geojson",
        driver="GeoJSON"
    )


    gdf[
        [
            "filename",
            "height_prior_m",
            "height_prior_source",
            "fov_diag_prior_deg",
            "fov_prior_source",
            "yaw_prior_deg",
            "yaw_prior_source",
            "prior_m_per_px",
        ]
    ].to_csv(
        OUTPUT_DIR
        /
        "priors_geometricos.csv",
        index=False
    )


    print(
        "Fotos válidas:",
        len(gdf)
    )

    print(
        "CRS:",
        TARGET_CRS.to_string()
    )


    display(
        gdf[
            [
                "filename",
                "height_prior_m",
                "height_prior_source",
                "fov_diag_prior_deg",
                "fov_prior_source",
                "yaw_prior_deg",
                "yaw_prior_source",
            ]
        ]
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 12
    # ===========================================================================
    fig, ax = plt.subplots(figsize=(12, 10))

    gdf.boundary.plot(
        ax=ax,
        linewidth=0.8
    )

    ax.scatter(
        gdf["x0"],
        gdf["y0"],
        s=20
    )

    for i, row in gdf.iterrows():
        ax.text(
            row["x0"],
            row["y0"],
            str(i),
            fontsize=8,
            ha="center",
            va="center"
        )

    ax.set_aspect("equal")
    ax.set_title("Footprints-prior aproximados")
    plt.tight_layout()
    footprints_plot_path = OUTPUT_DIR / "diagnostico_footprints.png"
    fig.savefig(
        footprints_plot_path,
        dpi=160,
        bbox_inches="tight"
    )
    plt.close(fig)
    print("Diagnóstico:", footprints_plot_path)


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 14
    # ===========================================================================
    # Os objetos do OpenCV não são compartilhados entre threads:
    # cada thread cria o seu próprio matcher e cada foto o seu SIFT.
    thread_state = threading.local()

    def get_matcher():
        if not hasattr(thread_state, "matcher"):
            thread_state.matcher = cv2.BFMatcher(
                cv2.NORM_L2
            )

        return thread_state.matcher


    def extract_sift_features(row):
        path = Path(row["source_path"])

        img = cv2.imread(
            str(path),
            cv2.IMREAD_GRAYSCALE
        )

        if img is None:
            raise RuntimeError(f"Não consegui abrir {path}")

        h_original, w_original = img.shape[:2]

        scale = min(
            1.0,
            SIFT_MAX_DIM / max(h_original, w_original)
        )

        if scale < 1.0:
            w_small = max(1, int(round(w_original * scale)))
            h_small = max(1, int(round(h_original * scale)))

            img = cv2.resize(
                img,
                (w_small, h_small),
                interpolation=cv2.INTER_AREA
            )

        sift = cv2.SIFT_create(
            nfeatures=SIFT_NFEATURES
        )

        kp, des = sift.detectAndCompute(
            img,
            None
        )

        return {
            "path": path,
            "kp": kp,
            "des": des,
            "scale": scale,
            "shape_original": (h_original, w_original),
            "shape_sift": img.shape[:2],
        }


    def overlap_ratio(geom_a, geom_b):
        intersection = geom_a.intersection(geom_b)

        if intersection.is_empty:
            return 0.0

        denom = min(geom_a.area, geom_b.area)

        if denom <= 0:
            return 0.0

        return float(intersection.area / denom)


    # A escala é preservada. Os limites abaixo são apenas proteção
    # contra soluções degeneradas, e não uma exigência de escala ~1.
    def classify_registration(
        n_inliers,
        inlier_ratio_value,
        median_error_sift_px,
        scale_est
    ):
        if (
            n_inliers >= OK_MIN_INLIERS
            and inlier_ratio_value >= OK_MIN_INLIER_RATIO
            and median_error_sift_px <= OK_MAX_MEDIAN_ERROR_SIFT_PX
            and OK_SCALE_MIN <= scale_est <= OK_SCALE_MAX
        ):
            return "ok"

        if (
            n_inliers >= WEAK_MIN_INLIERS
            and inlier_ratio_value >= WEAK_MIN_INLIER_RATIO
            and median_error_sift_px <= WEAK_MAX_MEDIAN_ERROR_SIFT_PX
            and WEAK_SCALE_MIN <= scale_est <= WEAK_SCALE_MAX
        ):
            return "fraco"

        return "rejeitado"


    def register_pair(
        index_a,
        index_b,
        row_a,
        row_b,
        feat_a,
        feat_b,
        overlap_geometry
    ):
        result = {
            "index_a": index_a,
            "index_b": index_b,
            "filename_a": row_a["filename"],
            "filename_b": row_b["filename"],
            "temporal_gap": index_b - index_a,
            "overlap_ratio_geometry": overlap_geometry,
            "status": "rejeitado",
        }

        kp_a = feat_a["kp"]
        kp_b = feat_b["kp"]

        des_a = feat_a["des"]
        des_b = feat_b["des"]

        if des_a is None or des_b is None:
            result["motivo"] = "sem_descritores"
            return result

        knn = get_matcher().knnMatch(
            des_a,
            des_b,
            k=2
        )

        good = []

        for pair in knn:
            if len(pair) < 2:
                continue

            m, n = pair

            if m.distance < LOWE_RATIO * n.distance:
                good.append(m)

        result["matches"] = len(good)

        if len(good) < MIN_MATCHES_TO_TRY:
            result["motivo"] = "poucos_matches"
            return result

        pts_a = np.float32([
            kp_a[m.queryIdx].pt
            for m in good
        ])

        pts_b = np.float32([
            kp_b[m.trainIdx].pt
            for m in good
        ])

        M_small, inlier_mask = cv2.estimateAffinePartial2D(
            pts_b,
            pts_a,
            method=cv2.RANSAC,
            ransacReprojThreshold=RANSAC_THRESHOLD_PX,
            maxIters=RANSAC_MAX_ITERS,
            confidence=RANSAC_CONFIDENCE,
            refineIters=50
        )

        if M_small is None or inlier_mask is None:
            result["motivo"] = "ransac_falhou"
            return result

        keep = inlier_mask.ravel().astype(bool)

        n_inliers = int(keep.sum())
        inlier_ratio_value = n_inliers / len(good)

        pts_b_h = np.column_stack([
            pts_b,
            np.ones(len(pts_b))
        ])

        predicted_a = (M_small @ pts_b_h.T).T

        errors = np.linalg.norm(
            predicted_a - pts_a,
            axis=1
        )

        median_error = float(
            np.median(errors[keep])
        )

        scale_a = float(feat_a["scale"])
        scale_b = float(feat_b["scale"])

        M_original = np.zeros(
            (2, 3),
            dtype=np.float64
        )

        M_original[:, :2] = (
            M_small[:, :2]
            * (scale_b / scale_a)
        )

        M_original[:, 2] = (
            M_small[:, 2] / scale_a
        )

        a = M_original[0, 0]
        b = M_original[0, 1]

        scale_est = math.sqrt(a*a + b*b)

        rotation_deg = math.degrees(
            math.atan2(
                M_original[1, 0],
                M_original[0, 0]
            )
        )

        status = classify_registration(
            n_inliers,
            inlier_ratio_value,
            median_error,
            scale_est
        )

        result.update({
            "inliers": n_inliers,
            "inlier_ratio": float(inlier_ratio_value),
            "error_median_sift_px": median_error,
            "error_median_original_px": median_error / scale_a,
            "rotation_deg": rotation_deg,
            "scale": scale_est,
            "tx_original_px": float(M_original[0, 2]),
            "ty_original_px": float(M_original[1, 2]),
            "status": status,
            "motivo": (
                "registro_consistente"
                if status == "ok"
                else "nao_usado_na_otimizacao_fina"
            ),
            "m00": float(M_original[0, 0]),
            "m01": float(M_original[0, 1]),
            "m02": float(M_original[0, 2]),
            "m10": float(M_original[1, 0]),
            "m11": float(M_original[1, 1]),
            "m12": float(M_original[1, 2]),
        })

        return result


    def matrix_from_registration_row(row):
        return np.array([
            [
                float(row["m00"]),
                float(row["m01"]),
                float(row["m02"])
            ],
            [
                float(row["m10"]),
                float(row["m11"]),
                float(row["m12"])
            ]
        ], dtype=np.float64)


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 16
    # ===========================================================================
    # ============================================================
    # FEATURES SIFT
    # ============================================================

    features_cache = {}


    def extract_sift_for_row(item):
        i, row = item

        print(
            f"SIFT "
            f"[{i + 1}/{len(gdf)}] "
            f"{row['filename']}"
        )

        return i, extract_sift_features(
            row
        )


    with ThreadPoolExecutor(max_workers=worker_count()) as pool:
        for i, features in pool.map(
            extract_sift_for_row,
            list(gdf.iterrows())
        ):
            features_cache[
                i
            ] = features


    # ============================================================
    # DISTÂNCIA TÍPICA ENTRE FOTOS CONSECUTIVAS
    # ============================================================

    consecutive_distances = []


    for i in range(
        len(gdf) - 1
    ):

        dx = (
            float(
                gdf.iloc[i + 1]["x0"]
            )
            -
            float(
                gdf.iloc[i]["x0"]
            )
        )

        dy = (
            float(
                gdf.iloc[i + 1]["y0"]
            )
            -
            float(
                gdf.iloc[i]["y0"]
            )
        )

        d = math.hypot(
            dx,
            dy
        )

        if np.isfinite(
            d
        ) and d > 0.5:

            consecutive_distances.append(
                d
            )


    if consecutive_distances:

        median_step_m = float(
            np.median(
                consecutive_distances
            )
        )

    else:

        median_step_m = (
            GPS_NEIGHBOR_MIN_M
            /
            GPS_NEIGHBOR_MULTIPLIER
        )


    gps_neighbor_radius_m = float(
        np.clip(
            GPS_NEIGHBOR_MULTIPLIER
            *
            median_step_m,

            GPS_NEIGHBOR_MIN_M,

            GPS_NEIGHBOR_MAX_M
        )
    )


    print()
    print(
        f"Passo GPS mediano: "
        f"{median_step_m:.1f} m"
    )

    print(
        f"Raio GPS para candidatos: "
        f"{gps_neighbor_radius_m:.1f} m"
    )


    # ============================================================
    # CONSTRUIR CANDIDATOS
    # ============================================================

    candidate_map = {}


    for i in range(
        len(gdf)
    ):

        for j in range(
            i + 1,
            len(gdf)
        ):

            reasons = []


            # ----------------------------------------------------
            # 1) proximidade temporal
            # ----------------------------------------------------

            temporal_gap = (
                j - i
            )

            if (
                temporal_gap
                <=
                TEMPORAL_NEIGHBOR_WINDOW
            ):

                reasons.append(
                    "temporal"
                )


            # ----------------------------------------------------
            # 2) distância GPS
            # ----------------------------------------------------

            dx = (
                float(
                    gdf.iloc[j]["x0"]
                )
                -
                float(
                    gdf.iloc[i]["x0"]
                )
            )

            dy = (
                float(
                    gdf.iloc[j]["y0"]
                )
                -
                float(
                    gdf.iloc[i]["y0"]
                )
            )

            gps_distance_m = math.hypot(
                dx,
                dy
            )


            if (
                gps_distance_m
                <=
                gps_neighbor_radius_m
            ):

                reasons.append(
                    "gps"
                )


            # ----------------------------------------------------
            # 3) overlap do footprint-prior
            # ----------------------------------------------------

            prior_overlap = overlap_ratio(

                gdf.iloc[
                    i
                ].geometry,

                gdf.iloc[
                    j
                ].geometry

            )


            if (
                prior_overlap
                >=
                PRIOR_MIN_OVERLAP_TO_TRY
            ):

                reasons.append(
                    "footprint_prior"
                )


            if reasons:

                candidate_map[
                    (i, j)
                ] = {

                    "index_a":
                        i,

                    "index_b":
                        j,

                    "temporal_gap":
                        temporal_gap,

                    "gps_distance_m":
                        gps_distance_m,

                    "prior_overlap":
                        prior_overlap,

                    "candidate_reasons":
                        ",".join(
                            reasons
                        ),
                }


    candidate_pairs = list(
        candidate_map.values()
    )


    print()
    print(
        "Pares candidatos:",
        len(candidate_pairs)
    )


    if not candidate_pairs:
        raise RuntimeError(
            "Nenhum par candidato encontrado."
        )


    # ============================================================
    # REGISTRAR PARES
    # ============================================================

    def register_candidate(numbered_candidate):

        k, candidate = numbered_candidate

        i = int(
            candidate["index_a"]
        )

        j = int(
            candidate["index_b"]
        )

        row_a = gdf.iloc[
            i
        ]

        row_b = gdf.iloc[
            j
        ]


        print(
            f"[{k}/{len(candidate_pairs)}] "
            f"{row_a['filename']} "
            f"<-> "
            f"{row_b['filename']} "
            f"({candidate['candidate_reasons']})"
        )


        try:

            result = register_pair(

                index_a=i,

                index_b=j,

                row_a=row_a,

                row_b=row_b,

                feat_a=features_cache[
                    i
                ],

                feat_b=features_cache[
                    j
                ],

                overlap_geometry=float(
                    candidate[
                        "prior_overlap"
                    ]
                )

            )


        except Exception as e:

            result = {

                "index_a":
                    i,

                "index_b":
                    j,

                "filename_a":
                    row_a[
                        "filename"
                    ],

                "filename_b":
                    row_b[
                        "filename"
                    ],

                "status":
                    "rejeitado",

                "motivo":
                    f"erro: {e}",
            }


        result[
            "gps_distance_m"
        ] = float(
            candidate[
                "gps_distance_m"
            ]
        )


        result[
            "candidate_reasons"
        ] = candidate[
            "candidate_reasons"
        ]


        result[
            "prior_overlap"
        ] = float(
            candidate[
                "prior_overlap"
            ]
        )


        return result


    # pool.map preserva a ordem dos pares, como no loop sequencial original.
    with ThreadPoolExecutor(max_workers=worker_count()) as pool:
        registration_results = list(
            pool.map(
                register_candidate,
                enumerate(
                    candidate_pairs,
                    start=1
                )
            )
        )


    registration_df = pd.DataFrame(
        registration_results
    )


    registration_df.to_csv(
        OUTPUT_DIR
        /
        "registro_visual_rede.csv",
        index=False
    )


    print()
    print(
        registration_df[
            "status"
        ]
        .value_counts(
            dropna=False
        )
    )


    display(
        registration_df[
            [
                c
                for c in [
                    "index_a",
                    "index_b",
                    "filename_a",
                    "filename_b",
                    "candidate_reasons",
                    "gps_distance_m",
                    "prior_overlap",
                    "matches",
                    "inliers",
                    "inlier_ratio",
                    "error_median_sift_px",
                    "rotation_deg",
                    "scale",
                    "status",
                ]
                if c in registration_df.columns
            ]
        ]
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 18
    # ===========================================================================
    def connected_components(n_nodes, edges_df):
        adjacency = {
            i: set()
            for i in range(n_nodes)
        }

        for _, edge in edges_df.iterrows():
            a = int(edge["index_a"])
            b = int(edge["index_b"])

            adjacency[a].add(b)
            adjacency[b].add(a)

        visited = set()
        components = []

        for start in range(n_nodes):
            if start in visited:
                continue

            stack = [start]
            component = []

            while stack:
                node = stack.pop()

                if node in visited:
                    continue

                visited.add(node)
                component.append(node)

                for neighbor in adjacency[node]:
                    if neighbor not in visited:
                        stack.append(neighbor)

            components.append(sorted(component))

        return components


    ok_edges_df = (
        registration_df[
            registration_df["status"] == "ok"
        ]
        .copy()
        .reset_index(drop=True)
    )

    weak_edges_df = (
        registration_df[
            registration_df["status"] == "fraco"
        ]
        .copy()
        .reset_index(drop=True)
    )

    components = connected_components(
        len(gdf),
        ok_edges_df
    )

    component_of = {}

    for component_id, nodes in enumerate(components):
        for node in nodes:
            component_of[node] = component_id


    print("Componentes visuais:", len(components))

    for component_id, nodes in enumerate(components):
        print(
            f"C{component_id}: {nodes}"
        )

    # Apenas diagnóstico: arestas fracas que cruzam componentes.
    cross_weak = []

    for _, edge in weak_edges_df.iterrows():
        a = int(edge["index_a"])
        b = int(edge["index_b"])

        if component_of[a] != component_of[b]:
            cross_weak.append(edge)

    if cross_weak:
        print()
        print(
            "Arestas fracas entre componentes "
            "(não serão usadas automaticamente):"
        )

        display(
            pd.DataFrame(cross_weak)[
                [
                    c for c in [
                        "filename_a",
                        "filename_b",
                        "inliers",
                        "inlier_ratio",
                        "error_median_sift_px",
                        "rotation_deg",
                        "scale"
                    ]
                    if c in pd.DataFrame(cross_weak).columns
                ]
            ]
        )


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 19
    # ===========================================================================
    fig, ax = plt.subplots(figsize=(12, 10))

    gdf.boundary.plot(
        ax=ax,
        linewidth=0.6
    )

    ax.scatter(
        gdf["x0"],
        gdf["y0"],
        s=25
    )

    for _, edge in ok_edges_df.iterrows():
        a = int(edge["index_a"])
        b = int(edge["index_b"])

        ax.plot(
            [
                gdf.iloc[a]["x0"],
                gdf.iloc[b]["x0"]
            ],
            [
                gdf.iloc[a]["y0"],
                gdf.iloc[b]["y0"]
            ],
            linewidth=1
        )

    for i, row in gdf.iterrows():
        ax.text(
            row["x0"],
            row["y0"],
            f"{i}\nC{component_of[i]}",
            fontsize=7,
            ha="center",
            va="center"
        )

    ax.set_aspect("equal")
    ax.set_title("Rede visual confiável e componentes")
    plt.tight_layout()
    network_plot_path = OUTPUT_DIR / "diagnostico_rede_visual.png"
    fig.savefig(
        network_plot_path,
        dpi=160,
        bbox_inches="tight"
    )
    plt.close(fig)
    print("Diagnóstico:", network_plot_path)


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 21
    # ===========================================================================
    def similarity_matrix(
        theta,
        log_scale,
        tx,
        ty
    ):
        scale = math.exp(
            log_scale
        )

        c = math.cos(
            theta
        )

        s = math.sin(
            theta
        )

        return np.array([
            [
                scale * c,
                -scale * s,
                tx
            ],
            [
                scale * s,
                scale * c,
                ty
            ],
            [
                0.0,
                0.0,
                1.0
            ],
        ], dtype=np.float64)


    def matrix_to_similarity_pose(
        T
    ):
        a = float(
            T[0, 0]
        )

        c = float(
            T[1, 0]
        )

        scale = math.hypot(
            a,
            c
        )

        theta = math.atan2(
            c,
            a
        )

        return (
            theta,
            math.log(
                max(
                    scale,
                    1e-12
                )
            ),
            float(
                T[0, 2]
            ),
            float(
                T[1, 2]
            )
        )


    def registration_similarity_matrix(
        row
    ):
        """
        Matriz homogênea B -> A preservando a similaridade
        estimada por estimateAffinePartial2D.
        """

        M = matrix_from_registration_row(
            row
        )

        T = np.eye(
            3,
            dtype=np.float64
        )

        T[:2, :] = M

        return T


    def sample_points_for_image(
        index
    ):
        h, w = features_cache[
            index
        ][
            "shape_original"
        ]

        cx = (
            w - 1
        ) / 2.0

        cy = (
            h - 1
        ) / 2.0

        return np.array([
            [
                cx,
                cy
            ],
            [
                cx - 0.25*w,
                cy
            ],
            [
                cx + 0.25*w,
                cy
            ],
            [
                cx,
                cy - 0.25*h
            ],
            [
                cx,
                cy + 0.25*h
            ],
        ], dtype=np.float64)


    sample_points_cache = {
        i: sample_points_for_image(
            i
        )
        for i in range(
            len(gdf)
        )
    }


    def prepare_component_edges(
        nodes
    ):
        node_set = set(
            nodes
        )

        subset = ok_edges_df[
            ok_edges_df[
                "index_a"
            ].isin(
                node_set
            )
            &
            ok_edges_df[
                "index_b"
            ].isin(
                node_set
            )
        ]

        edges = []


        for _, row in subset.iterrows():

            a = int(
                row[
                    "index_a"
                ]
            )

            b = int(
                row[
                    "index_b"
                ]
            )


            T_b_to_a = registration_similarity_matrix(
                row
            )


            ratio = float(
                row[
                    "inlier_ratio"
                ]
            )


            n_inliers = float(
                row[
                    "inliers"
                ]
            )


            error = float(
                row[
                    "error_median_sift_px"
                ]
            )


            weight = (

                ratio

                *

                min(
                    n_inliers / 100.0,
                    2.0
                )

                /

                max(
                    error,
                    0.75
                )

            )


            edges.append({

                "a":
                    a,

                "b":
                    b,

                "T_b_to_a":
                    T_b_to_a,

                "weight_raw":
                    weight,

                "pair_scale":
                    float(
                        row["scale"]
                    ),

            })


        if edges:

            median_weight = float(
                np.median([
                    e[
                        "weight_raw"
                    ]
                    for e in edges
                ])
            )


            if (
                median_weight
                <=
                0
            ):

                median_weight = 1.0


            for edge in edges:

                edge[
                    "weight"
                ] = (
                    edge[
                        "weight_raw"
                    ]
                    /
                    median_weight
                )


        return edges


    def optimize_component(
        component_id,
        nodes
    ):

        nodes = sorted(
            nodes
        )


        # ========================================================
        # COMPONENTE UNITÁRIO
        # ========================================================

        if len(nodes) == 1:

            node = nodes[
                0
            ]

            return {

                "poses": {
                    node:
                        np.eye(
                            3,
                            dtype=np.float64
                        )
                },

                "anchor":
                    node,

                "initial_median_px":
                    0.0,

                "final_median_px":
                    0.0,

                "final_rms_px":
                    0.0,

                "edges":
                    [],
            }


        edges = prepare_component_edges(
            nodes
        )


        if not edges:

            raise RuntimeError(
                f"Componente {component_id} "
                f"sem arestas."
            )


        # ========================================================
        # GRAU E ADJACÊNCIA
        # ========================================================

        degree = {
            node: 0
            for node in nodes
        }


        adjacency = {
            node: []
            for node in nodes
        }


        for edge in edges:

            a = edge[
                "a"
            ]

            b = edge[
                "b"
            ]

            T = edge[
                "T_b_to_a"
            ]


            degree[
                a
            ] += 1

            degree[
                b
            ] += 1


            adjacency[
                a
            ].append(
                (
                    b,
                    T
                )
            )


            adjacency[
                b
            ].append(
                (
                    a,
                    np.linalg.inv(
                        T
                    )
                )
            )


        # ========================================================
        # ÂNCORA
        # ========================================================

        anchor = max(
            nodes,
            key=lambda node: degree[
                node
            ]
        )


        # ========================================================
        # POSES INICIAIS POR PROPAGAÇÃO DA REDE
        # ========================================================

        initial_poses = {
            anchor:
                np.eye(
                    3,
                    dtype=np.float64
                )
        }


        queue = [
            anchor
        ]


        while queue:

            current = queue.pop(
                0
            )


            P_current = initial_poses[
                current
            ]


            for (
                neighbor,
                T_neighbor_to_current

            ) in adjacency[
                current
            ]:

                if (
                    neighbor
                    in
                    initial_poses
                ):
                    continue


                initial_poses[
                    neighbor
                ] = (

                    P_current

                    @

                    T_neighbor_to_current

                )


                queue.append(
                    neighbor
                )


        missing = [
            node
            for node in nodes
            if node
            not in
            initial_poses
        ]


        if missing:

            raise RuntimeError(
                f"Componente "
                f"{component_id} "
                f"internamente desconectado: "
                f"{missing}"
            )


        # ========================================================
        # VETOR DE PARÂMETROS
        # ========================================================

        free_nodes = [
            node
            for node in nodes
            if node
            !=
            anchor
        ]


        node_to_param = {
            node: k
            for k, node
            in enumerate(
                free_nodes
            )
        }


        # theta, log_scale, tx, ty

        x0 = np.zeros(
            4
            *
            len(
                free_nodes
            ),
            dtype=np.float64
        )


        for node in free_nodes:

            k = node_to_param[
                node
            ]


            (
                theta,
                log_scale,
                tx,
                ty

            ) = matrix_to_similarity_pose(

                initial_poses[
                    node
                ]

            )


            x0[
                4*k
            ] = theta


            x0[
                4*k + 1
            ] = log_scale


            x0[
                4*k + 2
            ] = tx


            x0[
                4*k + 3
            ] = ty


        def poses_from_vector(
            x
        ):

            poses = {
                anchor:
                    np.eye(
                        3,
                        dtype=np.float64
                    )
            }


            for node in free_nodes:

                k = node_to_param[
                    node
                ]


                poses[
                    node
                ] = similarity_matrix(

                    theta=x[
                        4*k
                    ],

                    log_scale=x[
                        4*k + 1
                    ],

                    tx=x[
                        4*k + 2
                    ],

                    ty=x[
                        4*k + 3
                    ],

                )


            return poses


        # ========================================================
        # RESÍDUOS
        # ========================================================

        def residuals(
            x
        ):

            poses = poses_from_vector(
                x
            )


            values = []


            for edge in edges:

                a = edge[
                    "a"
                ]

                b = edge[
                    "b"
                ]

                T = edge[
                    "T_b_to_a"
                ]


                pts_b = sample_points_cache[
                    b
                ]


                pts_a = transform_points(
                    T,
                    pts_b
                )


                component_b = transform_points(
                    poses[
                        b
                    ],
                    pts_b
                )


                component_a = transform_points(
                    poses[
                        a
                    ],
                    pts_a
                )


                diff = (
                    component_b
                    -
                    component_a
                )


                values.extend(
                    (
                        diff
                        *
                        math.sqrt(
                            edge[
                                "weight"
                            ]
                        )
                    )
                    .ravel()
                )


            return np.asarray(
                values,
                dtype=np.float64
            )


        initial_residual = residuals(
            x0
        )


        opt = least_squares(

            residuals,

            x0,

            method="trf",

            loss="soft_l1",

            f_scale=
                COMPONENT_LOSS_F_SCALE_PX,

            max_nfev=3000,

            verbose=0

        )


        final_residual = residuals(
            opt.x
        )


        return {

            "poses":
                poses_from_vector(
                    opt.x
                ),

            "anchor":
                anchor,

            "initial_median_px":
                float(
                    np.median(
                        np.abs(
                            initial_residual
                        )
                    )
                ),

            "final_median_px":
                float(
                    np.median(
                        np.abs(
                            final_residual
                        )
                    )
                ),

            "final_rms_px":
                float(
                    np.sqrt(
                        np.mean(
                            final_residual**2
                        )
                    )
                ),

            "edges":
                edges,
        }



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 22
    # ===========================================================================
    component_results = {}
    local_visual_poses = {}
    summary_rows = []


    for component_id, nodes in enumerate(
        components
    ):

        result = optimize_component(
            component_id,
            nodes
        )


        component_results[
            component_id
        ] = result


        component_scales = []


        for (
            node,
            pose

        ) in result[
            "poses"
        ].items():

            local_visual_poses[
                node
            ] = pose


            (
                _theta,
                log_scale,
                _tx,
                _ty

            ) = matrix_to_similarity_pose(
                pose
            )


            component_scales.append(
                math.exp(
                    log_scale
                )
            )


        summary_rows.append({

            "component_id":
                component_id,

            "n_images":
                len(nodes),

            "n_edges_ok":
                len(
                    result[
                        "edges"
                    ]
                ),

            "anchor_index":
                result[
                    "anchor"
                ],

            "anchor_filename":
                gdf.iloc[
                    result[
                        "anchor"
                    ]
                ][
                    "filename"
                ],

            "initial_median_px":
                result[
                    "initial_median_px"
                ],

            "final_median_px":
                result[
                    "final_median_px"
                ],

            "final_rms_px":
                result[
                    "final_rms_px"
                ],

            "local_scale_min":
                float(
                    np.min(
                        component_scales
                    )
                ),

            "local_scale_median":
                float(
                    np.median(
                        component_scales
                    )
                ),

            "local_scale_max":
                float(
                    np.max(
                        component_scales
                    )
                ),

        })


    component_summary_df = pd.DataFrame(
        summary_rows
    )


    display(
        component_summary_df
    )


    component_summary_df.to_csv(
        OUTPUT_DIR
        /
        "componentes_visuais.csv",
        index=False
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 24
    # ===========================================================================
    VISUAL_Y_FLIP = np.array([
        [1.0,  0.0, 0.0],
        [0.0, -1.0, 0.0],
        [0.0,  0.0, 1.0],
    ], dtype=np.float64)


    def fit_similarity_closed_form(
        src,
        dst
    ):
        """
        Similaridade livre:
            dst ~= scale * R * src + t
        """

        src = np.asarray(
            src,
            dtype=np.float64
        )

        dst = np.asarray(
            dst,
            dtype=np.float64
        )


        mean_src = src.mean(
            axis=0
        )

        mean_dst = dst.mean(
            axis=0
        )


        X = (
            src
            -
            mean_src
        )

        Y = (
            dst
            -
            mean_dst
        )


        H = (
            X.T
            @
            Y
        )


        U, singular_values, Vt = (
            np.linalg.svd(
                H
            )
        )


        R = (
            Vt.T
            @
            U.T
        )


        if (
            np.linalg.det(
                R
            )
            <
            0
        ):

            Vt[
                -1,
                :
            ] *= -1

            R = (
                Vt.T
                @
                U.T
            )


        denom = np.sum(
            X**2
        )


        scale = (
            singular_values.sum()
            /
            denom
            if denom > 0
            else 1.0
        )


        t = (
            mean_dst
            -
            scale
            *
            (
                R
                @
                mean_src
            )
        )


        T = np.eye(
            3,
            dtype=np.float64
        )


        T[
            :2,
            :2
        ] = (
            scale
            *
            R
        )


        T[
            :2,
            2
        ] = t


        return T


    def metric_scale_from_matrix(
        T
    ):
        """
        Escala isotrópica da parte linear.
        """

        A = np.asarray(
            T,
            dtype=np.float64
        )[
            :2,
            :2
        ]


        return math.sqrt(
            abs(
                float(
                    np.linalg.det(
                        A
                    )
                )
            )
        )


    def image_center_for_node(
        node
    ):

        h, w = features_cache[
            node
        ][
            "shape_original"
        ]


        return np.array([
            [
                (w - 1) / 2.0,
                (h - 1) / 2.0
            ]
        ], dtype=np.float64)


    def flip_y_points(
        pts
    ):
        """
        Converte pontos 2D de um sistema y-down para um sistema y-up,
        preservando origem e unidade:
            (x, y) -> (x, -y)
        """

        pts = np.asarray(
            pts,
            dtype=np.float64
        ).copy()

        pts[
            :,
            1
        ] *= -1.0

        return pts


    def component_center_correspondences(
        nodes,
        flip_visual_y=False
    ):
        """
        Centros das fotos:
            src = coordenadas no sistema visual local do componente
            dst = centros GPS em UTM

        Se flip_visual_y=True:
            src passa a ser expresso em um sistema local y-up.
        """

        src_centers = []
        dst_centers = []


        for node in sorted(
            nodes
        ):

            center_visual = transform_points(

                local_visual_poses[
                    node
                ],

                image_center_for_node(
                    node
                )

            )[0]


            if flip_visual_y:
                center_visual = np.array([
                    center_visual[0],
                    -center_visual[1]
                ], dtype=np.float64)


            center_gps = np.array([
                float(
                    gdf.iloc[
                        node
                    ][
                        "x0"
                    ]
                ),
                float(
                    gdf.iloc[
                        node
                    ][
                        "y0"
                    ]
                ),
            ])


            src_centers.append(
                center_visual
            )

            dst_centers.append(
                center_gps
            )


        return (
            np.asarray(
                src_centers,
                dtype=np.float64
            ),
            np.asarray(
                dst_centers,
                dtype=np.float64
            )
        )


    def component_prior_metric_scale(
        nodes
    ):
        """
        Estima quantos metros deveriam corresponder a uma unidade
        do sistema visual local do componente segundo os priors.

        Como usamos |det|, a inversão de Y não altera esta escala.
        """

        values = []


        for node in sorted(
            nodes
        ):

            local_scale = (
                metric_scale_from_matrix(
                    local_visual_poses[
                        node
                    ]
                )
            )


            prior_m_per_px = float(
                gdf.iloc[
                    node
                ][
                    "prior_m_per_px"
                ]
            )


            if (
                np.isfinite(
                    local_scale
                )
                and
                local_scale > 0
                and
                np.isfinite(
                    prior_m_per_px
                )
                and
                prior_m_per_px > 0
            ):

                values.append(
                    prior_m_per_px
                    /
                    local_scale
                )


        if not values:

            return np.nan


        return float(
            np.median(
                values
            )
        )


    def component_metric_scale_from_mpp_column(
        nodes,
        column_name
    ):
        """
        Converte uma coluna de metros/pixel por foto em
        metros/unidade visual do componente.
        """

        values = []

        for node in sorted(
            nodes
        ):

            local_scale = metric_scale_from_matrix(
                local_visual_poses[
                    node
                ]
            )

            m_per_px = float(
                gdf.iloc[
                    node
                ][
                    column_name
                ]
            )

            if (
                np.isfinite(
                    local_scale
                )
                and
                local_scale > 0
                and
                np.isfinite(
                    m_per_px
                )
                and
                m_per_px > 0
            ):

                values.append(
                    m_per_px
                    /
                    local_scale
                )

        if not values:
            return np.nan

        return float(
            np.median(
                values
            )
        )


    def fit_component_free_to_utm(
        nodes
    ):
        """
        Calibração livre usada para APRENDER a razão de escala.

        IMPORTANTE:
        o ajuste é feito num sistema visual local y-up.
        No fim, a transformação é reconvertida para atuar sobre
        o sistema visual bruto (y-down), multiplicando por VISUAL_Y_FLIP
        à direita.

        - singleton:
            usa o prior completo;
        - 2 fotos:
            similaridade fechada;
        - 3+:
            similaridade robusta.
        """

        nodes = sorted(
            nodes
        )


        if len(
            nodes
        ) == 1:

            node = nodes[
                0
            ]


            return (
                coarse_T_utm[
                    node
                ].copy(),
                0.0,
                0.0
            )


        src_raw, dst = (
            component_center_correspondences(
                nodes,
                flip_visual_y=False
            )
        )

        src_y_up = flip_y_points(
            src_raw
        )


        T0_y_up = fit_similarity_closed_form(
            src_y_up,
            dst
        )


        if len(
            nodes
        ) == 2:

            errors = np.linalg.norm(

                transform_points(
                    T0_y_up,
                    src_y_up
                )
                -
                dst,

                axis=1

            )

            T0_raw = (
                T0_y_up
                @
                VISUAL_Y_FLIP
            )


            return (
                T0_raw,
                float(
                    np.median(
                        errors
                    )
                ),
                float(
                    np.sqrt(
                        np.mean(
                            errors**2
                        )
                    )
                )
            )


        dst_origin = dst.mean(
            axis=0
        )


        A0 = T0_y_up[
            :2,
            :2
        ]


        scale0 = metric_scale_from_matrix(
            T0_y_up
        )


        theta0 = math.atan2(
            A0[
                1,
                0
            ],
            A0[
                0,
                0
            ]
        )


        t0_centered = (
            T0_y_up[
                :2,
                2
            ]
            -
            dst_origin
        )


        x0 = np.array([
            theta0,
            math.log(
                max(
                    scale0,
                    1e-12
                )
            ),
            t0_centered[
                0
            ],
            t0_centered[
                1
            ],
        ], dtype=np.float64)


        def params_to_T_y_up(
            x
        ):

            theta = x[
                0
            ]

            scale = math.exp(
                x[
                    1
                ]
            )


            c = math.cos(
                theta
            )

            s = math.sin(
                theta
            )


            R = np.array([
                [
                    c,
                    -s
                ],
                [
                    s,
                    c
                ],
            ], dtype=np.float64)


            T = np.eye(
                3,
                dtype=np.float64
            )


            T[
                :2,
                :2
            ] = (
                scale
                *
                R
            )


            T[
                :2,
                2
            ] = (
                dst_origin
                +
                x[
                    2:4
                ]
            )


            return T


        def residuals(
            x
        ):

            predicted = transform_points(

                params_to_T_y_up(
                    x
                ),

                src_y_up

            )


            return (
                predicted
                -
                dst
            ).ravel()


        opt = least_squares(

            residuals,

            x0,

            method="trf",

            loss="soft_l1",

            f_scale=
                GEO_FIT_LOSS_F_SCALE_M,

            max_nfev=1000,

            verbose=0

        )


        T_y_up = params_to_T_y_up(
            opt.x
        )


        errors = np.linalg.norm(

            transform_points(
                T_y_up,
                src_y_up
            )
            -
            dst,

            axis=1

        )

        T_raw = (
            T_y_up
            @
            VISUAL_Y_FLIP
        )


        return (
            T_raw,
            float(
                np.median(
                    errors
                )
            ),
            float(
                np.sqrt(
                    np.mean(
                        errors**2
                    )
                )
            )
        )


    def weighted_rotation_fixed_scale_closed_form(
        src,
        dst,
        fixed_scale
    ):
        """
        Ajusta apenas rotação + translação, mantendo a escala fixa.

            dst ~= fixed_scale * R * src + t
        """

        src = np.asarray(
            src,
            dtype=np.float64
        )

        dst = np.asarray(
            dst,
            dtype=np.float64
        )


        mean_src = src.mean(
            axis=0
        )

        mean_dst = dst.mean(
            axis=0
        )


        X = (
            src
            -
            mean_src
        )

        Y = (
            dst
            -
            mean_dst
        )


        H = (
            X.T
            @
            Y
        )


        U, _, Vt = np.linalg.svd(
            H
        )


        R = (
            Vt.T
            @
            U.T
        )


        if (
            np.linalg.det(
                R
            )
            <
            0
        ):

            Vt[
                -1,
                :
            ] *= -1

            R = (
                Vt.T
                @
                U.T
            )


        t = (
            mean_dst
            -
            fixed_scale
            *
            (
                R
                @
                mean_src
            )
        )


        T = np.eye(
            3,
            dtype=np.float64
        )


        T[
            :2,
            :2
        ] = (
            fixed_scale
            *
            R
        )


        T[
            :2,
            2
        ] = t


        return T


    def fit_component_fixed_scale_to_utm(
        nodes,
        fixed_scale
    ):
        """
        Recoloca o componente em UTM com ESCALA FIXA.

        IMPORTANTE:
        o ajuste é feito em coordenadas locais y-up e depois
        reconvertido para atuar sobre o sistema visual bruto y-down.

        - singleton:
            preserva exatamente o prior completo;
            não há motivo para reestimar orientação;
        - 2 fotos:
            ajusta rotação + translação fechadas;
        - 3+ fotos:
            refina robustamente rotação + translação.
        """

        nodes = sorted(
            nodes
        )


        # ========================================================
        # SINGLETON
        # ========================================================

        if len(
            nodes
        ) == 1:

            node = nodes[
                0
            ]

            T_prior = coarse_T_utm[
                node
            ]
            prior_scale = metric_scale_from_matrix(
                T_prior
            )

            if (
                not np.isfinite(
                    prior_scale
                )
                or
                prior_scale <= 0
            ):

                raise RuntimeError(
                    f"Escala-prior inválida na foto {node}."
                )

            # Para singletons, a paridade já está correta em coarse_T_utm.
            # Apenas regularizamos a escala preservando a orientação-prior.
            A_prior = T_prior[
                :2,
                :2
            ]

            R_improper = (
                A_prior
                /
                prior_scale
            )

            center_px = (
                image_center_for_node(
                    node
                )[0]
            )

            center_gps = np.array([
                float(
                    gdf.iloc[
                        node
                    ][
                        "x0"
                    ]
                ),
                float(
                    gdf.iloc[
                        node
                    ][
                        "y0"
                    ]
                ),
            ])

            A_new = (
                fixed_scale
                *
                R_improper
            )

            t_new = (
                center_gps
                -
                A_new
                @
                center_px
            )

            T = np.eye(
                3,
                dtype=np.float64
            )

            T[
                :2,
                :2
            ] = A_new

            T[
                :2,
                2
            ] = t_new

            return (
                T,
                0.0,
                0.0
            )


        # ========================================================
        # 2+ FOTOS
        # ========================================================

        src_raw, dst = (
            component_center_correspondences(
                nodes,
                flip_visual_y=False
            )
        )

        src_y_up = flip_y_points(
            src_raw
        )

        T0_y_up = (
            weighted_rotation_fixed_scale_closed_form(
                src_y_up,
                dst,
                fixed_scale
            )
        )


        if len(
            nodes
        ) == 2:

            errors = np.linalg.norm(

                transform_points(
                    T0_y_up,
                    src_y_up
                )
                -
                dst,

                axis=1

            )

            T0_raw = (
                T0_y_up
                @
                VISUAL_Y_FLIP
            )

            return (
                T0_raw,
                float(
                    np.median(
                        errors
                    )
                ),
                float(
                    np.sqrt(
                        np.mean(
                            errors**2
                        )
                    )
                )
            )


        # ========================================================
        # ROBUSTO PARA 3+
        # ========================================================

        A0 = T0_y_up[
            :2,
            :2
        ]

        theta0 = math.atan2(
            A0[
                1,
                0
            ],
            A0[
                0,
                0
            ]
        )

        dst_origin = dst.mean(
            axis=0
        )

        t0_centered = (
            T0_y_up[
                :2,
                2
            ]
            -
            dst_origin
        )

        x0 = np.array([
            theta0,
            t0_centered[
                0
            ],
            t0_centered[
                1
            ],
        ], dtype=np.float64)


        def params_to_T_y_up(
            x
        ):

            theta = x[
                0
            ]


            c = math.cos(
                theta
            )

            s = math.sin(
                theta
            )


            R = np.array([
                [
                    c,
                    -s
                ],
                [
                    s,
                    c
                ],
            ], dtype=np.float64)

            T = np.eye(
                3,
                dtype=np.float64
            )

            T[
                :2,
                :2
            ] = (
                fixed_scale
                *
                R
            )

            T[
                :2,
                2
            ] = (
                dst_origin
                +
                x[
                    1:3
                ]
            )

            return T


        def residuals(
            x
        ):

            predicted = transform_points(

                params_to_T_y_up(
                    x
                ),

                src_y_up

            )

            return (
                predicted
                -
                dst
            ).ravel()


        opt = least_squares(

            residuals,

            x0,

            method="trf",

            loss="soft_l1",

            f_scale=
                GEO_FIT_LOSS_F_SCALE_M,

            max_nfev=1000,

            verbose=0

        )

        T_y_up = params_to_T_y_up(
            opt.x
        )

        errors = np.linalg.norm(

            transform_points(
                T_y_up,
                src_y_up
            )
            -
            dst,

            axis=1

        )

        T_raw = (
            T_y_up
            @
            VISUAL_Y_FLIP
        )

        return (
            T_raw,
            float(
                np.median(
                    errors
                )
            ),
            float(
                np.sqrt(
                    np.mean(
                        errors**2
                    )
                )
            )
        )


    def robust_component_ratio_filter(
        values
    ):
        """
        Remove razões extremas e, quando possível, outliers por MAD.
        """

        arr = np.asarray(
            values,
            dtype=np.float64
        )

        finite = np.isfinite(
            arr
        )

        plausible = (
            finite
            &
            (
                arr
                >=
                GLOBAL_SCALE_RATIO_MIN
            )
            &
            (
                arr
                <=
                GLOBAL_SCALE_RATIO_MAX
            )
        )

        keep = plausible.copy()

        candidate_values = arr[
            plausible
        ]

        if len(
            candidate_values
        ) >= 3:

            median = float(
                np.median(
                    candidate_values
                )
            )

            mad = float(
                np.median(
                    np.abs(
                        candidate_values
                        -
                        median
                    )
                )
            )

            if mad > 1e-12:

                robust_z = (
                    0.67448975
                    *
                    np.abs(
                        arr
                        -
                        median
                    )
                    /
                    mad
                )

                keep &= (
                    robust_z
                    <=
                    GLOBAL_SCALE_MAD_Z
                )

        return keep


    # ============================================================
    # PASSAGEM 1 — CALIBRAÇÃO LIVRE DOS COMPONENTES
    # ============================================================

    component_free_to_utm = {}
    scale_learning_rows = []


    for component_id, nodes in enumerate(
        components
    ):

        (
            T_free,
            free_median_m,
            free_rms_m

        ) = fit_component_free_to_utm(
            nodes
        )

        component_free_to_utm[
            component_id
        ] = T_free

        prior_component_scale = (
            component_prior_metric_scale(
                nodes
            )
        )

        free_component_scale = (
            metric_scale_from_matrix(
                T_free
            )
        )

        scale_ratio = (
            free_component_scale
            /
            prior_component_scale
            if (
                np.isfinite(
                    prior_component_scale
                )
                and
                prior_component_scale > 0
            )
            else np.nan
        )

        n_edges_ok = int(
            len(
                component_results[
                    component_id
                ][
                    "edges"
                ]
            )
        )

        informative = (
            len(
                nodes
            )
            >=
            GLOBAL_SCALE_MIN_COMPONENT_SIZE
            and
            n_edges_ok >= 1
        )

        scale_learning_rows.append({

            "component_id":
                component_id,

            "n_images":
                len(
                    nodes
                ),

            "n_edges_ok":
                n_edges_ok,

            "informative_for_scale":
                informative,

            "prior_component_m_per_visual":
                prior_component_scale,

            "free_component_m_per_visual":
                free_component_scale,

            "free_to_prior_ratio":
                scale_ratio,

            "free_geo_fit_median_m":
                free_median_m,

            "free_geo_fit_rms_m":
                free_rms_m,

            "free_det":
                float(
                    np.linalg.det(
                        T_free[
                            :2,
                            :2
                        ]
                    )
                ),

        })


    component_scale_learning_df = pd.DataFrame(
        scale_learning_rows
    )

    required_scale_learning_columns = {
        "component_id",
        "n_images",
        "n_edges_ok",
        "informative_for_scale",
        "prior_component_m_per_visual",
        "free_component_m_per_visual",
        "free_to_prior_ratio",
    }

    missing_scale_learning_columns = (
        required_scale_learning_columns
        -
        set(
            component_scale_learning_df.columns
        )
    )

    if missing_scale_learning_columns:
        raise RuntimeError(
            "Erro interno na tabela de calibração livre. "
            f"Colunas ausentes: {sorted(missing_scale_learning_columns)}"
        )


    # ============================================================
    # APRENDER OFFSET AGL ADITIVO
    # ============================================================
    #
    # Para uma foto i dentro de um componente forte:
    #
    #   free_mpp_i =
    #       free_component_m_per_visual
    #       *
    #       local_visual_scale_i
    #
    # Como o prior óptico é linear em altura:
    #
    #   mpp_i = optical_factor_i * H_i
    #
    # obtemos:
    #
    #   H_efetiva_i =
    #       free_mpp_i
    #       /
    #       (prior_mpp_i / H_prior_i)
    #
    # e então:
    #
    #   offset_i = H_efetiva_i - H_prior_i
    #
    # O offset final é a mediana robusta dessas estimativas.

    agl_offset_samples = []


    for component_id, nodes in enumerate(
        components
    ):

        n_edges_ok = int(
            len(
                component_results[
                    component_id
                ][
                    "edges"
                ]
            )
        )

        if (
            len(
                nodes
            )
            <
            AGL_OFFSET_MIN_COMPONENT_SIZE
            or
            n_edges_ok < 1
        ):
            continue


        free_component_scale = float(

            component_scale_learning_df.loc[
                component_scale_learning_df[
                    "component_id"
                ]
                ==
                component_id,
                "free_component_m_per_visual"
            ].iloc[
                0
            ]

        )


        for node in nodes:

            local_scale = metric_scale_from_matrix(
                local_visual_poses[
                    node
                ]
            )

            free_m_per_px = (
                free_component_scale
                *
                local_scale
            )

            height_prior = float(
                gdf.iloc[
                    node
                ][
                    "height_prior_m"
                ]
            )

            prior_m_per_px = float(
                gdf.iloc[
                    node
                ][
                    "prior_m_per_px"
                ]
            )


            if (
                not np.isfinite(
                    free_m_per_px
                )
                or
                not np.isfinite(
                    height_prior
                )
                or
                not np.isfinite(
                    prior_m_per_px
                )
                or
                height_prior <= 0
                or
                prior_m_per_px <= 0
            ):
                continue


            optical_mpp_per_m = (
                prior_m_per_px
                /
                height_prior
            )

            effective_height_m = (
                free_m_per_px
                /
                optical_mpp_per_m
            )

            offset_m = (
                effective_height_m
                -
                height_prior
            )


            agl_offset_samples.append({

                "component_id":
                    component_id,

                "image_index":
                    node,

                "filename":
                    gdf.iloc[
                        node
                    ][
                        "filename"
                    ],

                "height_prior_m":
                    height_prior,

                "free_m_per_px":
                    free_m_per_px,

                "effective_height_m":
                    effective_height_m,

                "agl_offset_sample_m":
                    offset_m,

            })


    agl_offset_samples_df = pd.DataFrame(
        agl_offset_samples
    )


    if len(
        agl_offset_samples_df
    ) > 0:

        offsets = (
            agl_offset_samples_df[
                "agl_offset_sample_m"
            ]
            .to_numpy(
                dtype=np.float64
            )
        )

        plausible = (
            np.isfinite(
                offsets
            )
            &
            (
                offsets
                >=
                AGL_OFFSET_MIN_M
            )
            &
            (
                offsets
                <=
                AGL_OFFSET_MAX_M
            )
        )

        keep = plausible.copy()

        candidate_offsets = offsets[
            plausible
        ]

        if len(
            candidate_offsets
        ) >= 3:

            offset_median = float(
                np.median(
                    candidate_offsets
                )
            )

            offset_mad = float(
                np.median(
                    np.abs(
                        candidate_offsets
                        -
                        offset_median
                    )
                )
            )

            if offset_mad > 1e-12:

                robust_z = (
                    0.67448975
                    *
                    np.abs(
                        offsets
                        -
                        offset_median
                    )
                    /
                    offset_mad
                )

                keep &= (
                    robust_z
                    <=
                    AGL_OFFSET_MAD_Z
                )


        agl_offset_samples_df[
            "accepted"
        ] = keep


        accepted_agl_samples = (
            agl_offset_samples_df[
                agl_offset_samples_df[
                    "accepted"
                ]
            ]
            .copy()
        )


    else:

        agl_offset_samples_df[
            "accepted"
        ] = pd.Series(
            dtype=bool
        )

        accepted_agl_samples = (
            agl_offset_samples_df.copy()
        )


    agl_support_components = (
        accepted_agl_samples[
            "component_id"
        ]
        .nunique()
        if len(
            accepted_agl_samples
        ) > 0
        else 0
    )


    if (
        USE_LEARNED_AGL_OFFSET
        and
        agl_support_components
        >=
        AGL_OFFSET_MIN_SUPPORT_COMPONENTS
        and
        len(
            accepted_agl_samples
        ) > 0
    ):

        learned_agl_offset_m = float(
            np.median(
                accepted_agl_samples[
                    "agl_offset_sample_m"
                ]
            )
        )

        learned_agl_offset_used = True

    else:

        learned_agl_offset_m = 0.0
        learned_agl_offset_used = False


    # ------------------------------------------------------------
    # Criar altura e m/pixel corrigidos por foto
    # ------------------------------------------------------------

    corrected_heights = []
    corrected_mpp = []


    for i, row in gdf.iterrows():

        H = float(
            row[
                "height_prior_m"
            ]
        )

        base_mpp = float(
            row[
                "prior_m_per_px"
            ]
        )

        H_corrected = (
            H
            +
            learned_agl_offset_m
            if learned_agl_offset_used
            else H
        )

        # Evita altura não física.
        H_corrected = max(
            H_corrected,
            1.0
        )

        mpp_corrected = (
            base_mpp
            *
            H_corrected
            /
            H
        )

        corrected_heights.append(
            H_corrected
        )

        corrected_mpp.append(
            mpp_corrected
        )


    gdf[
        "height_agl_corrected_m"
    ] = corrected_heights


    gdf[
        "prior_m_per_px_agl_corrected"
    ] = corrected_mpp


    agl_offset_samples_df.to_csv(
        OUTPUT_DIR
        /
        "agl_offset_samples.csv",
        index=False
    )


    print()
    print("=" * 75)
    print("CORREÇÃO APRENDIDA DE ALTURA AGL")
    print("=" * 75)

    print(
        "Offset AGL aplicado:",
        learned_agl_offset_used
    )

    print(
        "Componentes de suporte:",
        agl_support_components
    )

    print(
        f"Offset AGL aprendido: "
        f"{learned_agl_offset_m:.3f} m"
    )

    if learned_agl_offset_used:
        print(
            "Alturas corrigidas: "
            f"{float(gdf['height_agl_corrected_m'].min()):.2f} m "
            "a "
            f"{float(gdf['height_agl_corrected_m'].max()):.2f} m"
        )

    if len(
        agl_offset_samples_df
    ) > 0:

        display(
            agl_offset_samples_df
        )



    # ============================================================
    # APRENDER k_global
    # ============================================================

    # Recalcular o prior dos componentes após o offset AGL.
    corrected_component_prior_scale = {}

    for component_id, nodes in enumerate(
        components
    ):

        corrected_component_prior_scale[
            component_id
        ] = (
            component_metric_scale_from_mpp_column(
                nodes,
                "prior_m_per_px_agl_corrected"
            )
        )


    informative_df = (
        component_scale_learning_df[
            component_scale_learning_df[
                "informative_for_scale"
            ]
        ]
        .copy()
    )


    informative_df[
        "agl_corrected_component_m_per_visual"
    ] = informative_df[
        "component_id"
    ].map(
        corrected_component_prior_scale
    )


    informative_df[
        "free_to_agl_corrected_ratio"
    ] = (

        informative_df[
            "free_component_m_per_visual"
        ]

        /

        informative_df[
            "agl_corrected_component_m_per_visual"
        ]

    )


    if len(
        informative_df
    ) > 0:

        ratio_values = (
            informative_df[
                "free_to_agl_corrected_ratio"
            ]
            .to_numpy(
                dtype=np.float64
            )
        )

        keep_mask = (
            robust_component_ratio_filter(
                ratio_values
            )
        )

        informative_df[
            "accepted_for_global_scale"
        ] = keep_mask

    else:

        informative_df[
            "accepted_for_global_scale"
        ] = pd.Series(
            dtype=bool
        )

    accepted_df = (
        informative_df[
            informative_df[
                "accepted_for_global_scale"
            ]
        ]
        .copy()
    )

    n_support_components = len(
        accepted_df
    )

    single_large_component_support = (
        n_support_components == 1
        and
        int(
            accepted_df.iloc[
                0
            ][
                "n_images"
            ]
        )
        >=
        GLOBAL_SCALE_SINGLE_COMPONENT_MIN_IMAGES
    )

    enough_support = (

        n_support_components
        >=
        GLOBAL_SCALE_MIN_SUPPORT_COMPONENTS

        or

        single_large_component_support

    )

    if (
        USE_GLOBAL_FLIGHT_SCALE
        and
        enough_support
    ):

        global_scale_correction = float(
            np.median(
                accepted_df[
                    "free_to_agl_corrected_ratio"
                ]
            )
        )

        global_scale_used = True

    else:

        global_scale_correction = 1.0
        global_scale_used = False


    print()
    print("=" * 75)
    print("CALIBRAÇÃO GLOBAL DE ESCALA")
    print("=" * 75)

    print()
    print(
        "Componentes informativos:",
        len(
            informative_df
        )
    )

    print(
        "Componentes aceitos:",
        n_support_components
    )

    print(
        "Suporte suficiente:",
        enough_support
    )

    print(
        "Calibração global aplicada:",
        global_scale_used
    )

    print(
        f"Fator global k: "
        f"{global_scale_correction:.4f}"
    )

    if len(
        informative_df
    ) > 0:

        display(
            informative_df[
                [
                    "component_id",
                    "n_images",
                    "n_edges_ok",
                    "free_to_prior_ratio",
                    "free_to_agl_corrected_ratio",
                    "free_geo_fit_rms_m",
                    "accepted_for_global_scale",
                ]
            ]
        )


    # ============================================================
    # PASSAGEM 2 — ESCALA FINAL REGULARIZADA
    # ============================================================

    component_to_utm = {}
    final_geo_rows = []


    for component_id, nodes in enumerate(
        components
    ):

        # A escala-base agora usa o prior corrigido pelo
        # offset AGL aprendido.
        prior_component_scale = float(
            corrected_component_prior_scale[
                component_id
            ]
        )

        free_T = (
            component_free_to_utm[
                component_id
            ]
        )

        free_component_scale = (
            metric_scale_from_matrix(
                free_T
            )
        )

        if (
            global_scale_used
            and
            GLOBAL_SCALE_APPLY_TO_ALL_COMPONENTS
            and
            np.isfinite(
                prior_component_scale
            )
            and
            prior_component_scale > 0
        ):

            final_component_scale = (
                prior_component_scale
                *
                global_scale_correction
            )

            (
                T_final,
                final_median_m,
                final_rms_m

            ) = fit_component_fixed_scale_to_utm(

                nodes,
                final_component_scale

            )

            scale_source = (
                "global_flight_scale"
            )

        elif (
            global_scale_used
            and
            len(
                nodes
            ) == 1
            and
            np.isfinite(
                prior_component_scale
            )
            and
            prior_component_scale > 0
        ):

            final_component_scale = (
                prior_component_scale
                *
                global_scale_correction
            )

            (
                T_final,
                final_median_m,
                final_rms_m

            ) = fit_component_fixed_scale_to_utm(

                nodes,
                final_component_scale

            )

            scale_source = (
                "global_scale_singleton"
            )

        else:

            T_final = (
                free_T
            )

            final_component_scale = (
                free_component_scale
            )

            free_row = (
                component_scale_learning_df[
                    component_scale_learning_df[
                        "component_id"
                    ]
                    ==
                    component_id
                ]
                .iloc[
                    0
                ]
            )

            final_median_m = float(
                free_row[
                    "free_geo_fit_median_m"
                ]
            )

            final_rms_m = float(
                free_row[
                    "free_geo_fit_rms_m"
                ]
            )

            scale_source = (
                "free_component_scale"
                if len(
                    nodes
                ) >= 2
                else
                "raw_prior_singleton"
            )

        component_to_utm[
            component_id
        ] = T_final

        final_geo_rows.append({

            "component_id":
                component_id,

            "n_images":
                len(
                    nodes
                ),

            "n_edges_ok":
                int(
                    len(
                        component_results[
                            component_id
                        ][
                            "edges"
                        ]
                    )
                ),

            # Prior original, antes da correção aditiva de AGL.
            "prior_component_m_per_visual":
                float(
                    component_scale_learning_df.loc[
                        component_scale_learning_df[
                            "component_id"
                        ]
                        ==
                        component_id,
                        "prior_component_m_per_visual"
                    ].iloc[
                        0
                    ]
                ),

            # Prior depois de aplicar o offset AGL aprendido.
            "agl_corrected_component_m_per_visual":
                prior_component_scale,

            "free_component_m_per_visual":
                free_component_scale,

            "free_to_prior_ratio":
                (
                    free_component_scale
                    /
                    float(
                        component_scale_learning_df.loc[
                            component_scale_learning_df[
                                "component_id"
                            ]
                            ==
                            component_id,
                            "prior_component_m_per_visual"
                        ].iloc[
                            0
                        ]
                    )
                    if (
                        float(
                            component_scale_learning_df.loc[
                                component_scale_learning_df[
                                    "component_id"
                                ]
                                ==
                                component_id,
                                "prior_component_m_per_visual"
                            ].iloc[
                                0
                            ]
                        ) > 0
                    )
                    else np.nan
                ),

            "free_to_agl_corrected_ratio":
                (
                    free_component_scale
                    /
                    prior_component_scale
                    if (
                        np.isfinite(
                            prior_component_scale
                        )
                        and
                        prior_component_scale > 0
                    )
                    else np.nan
                ),

            "global_scale_correction":
                global_scale_correction,

            "final_component_m_per_visual":
                final_component_scale,

            "final_to_agl_corrected_ratio":
                (
                    final_component_scale
                    /
                    prior_component_scale
                    if (
                        np.isfinite(
                            prior_component_scale
                        )
                        and
                        prior_component_scale > 0
                    )
                    else np.nan
                ),

            "scale_source":
                scale_source,

            "final_geo_fit_median_m":
                final_median_m,

            "final_geo_fit_rms_m":
                final_rms_m,

            "final_det":
                float(
                    np.linalg.det(
                        T_final[
                            :2,
                            :2
                        ]
                    )
                ),

            "parity_ok":
                bool(
                    np.linalg.det(
                        T_final[
                            :2,
                            :2
                        ]
                    ) < 0
                ),

        })


    component_geo_df = pd.DataFrame(
        final_geo_rows
    )

    required_component_geo_columns = {
        "component_id",
        "n_images",
        "prior_component_m_per_visual",
        "agl_corrected_component_m_per_visual",
        "free_component_m_per_visual",
        "final_component_m_per_visual",
        "final_to_agl_corrected_ratio",
    }

    missing_component_geo_columns = (
        required_component_geo_columns
        -
        set(
            component_geo_df.columns
        )
    )

    if missing_component_geo_columns:
        raise RuntimeError(
            "Erro interno na tabela geométrica final. "
            f"Colunas ausentes: {sorted(missing_component_geo_columns)}"
        )

    component_geo_df.to_csv(
        OUTPUT_DIR
        /
        "componentes_geometricos.csv",
        index=False
    )

    print()
    print(
        "Geometria final dos componentes:"
    )

    display(
        component_geo_df
    )

    bad_parity_components = component_geo_df[
        ~component_geo_df[
            "parity_ok"
        ]
    ].copy()

    if len(
        bad_parity_components
    ) > 0:

        print()
        print(
            "[WARN] Componentes com paridade incorreta:"
        )

        display(
            bad_parity_components[
                [
                    "component_id",
                    "n_images",
                    "scale_source",
                    "final_det"
                ]
            ]
        )

    else:

        print()
        print(
            "Todos os componentes ficaram com paridade correta (det < 0)."
        )



    # ============================================================
    # PASSAGEM 3 — REDE DE ARESTAS USADAS SOMENTE PARA ESCALA
    # ============================================================

    def current_image_m_per_px(
        image_index
    ):
        """
        Escala métrica da foto antes da regularização por arestas
        de escala.
        """

        component_id = component_of[
            image_index
        ]

        T = (
            component_to_utm[
                component_id
            ]
            @
            local_visual_poses[
                image_index
            ]
        )

        return metric_scale_from_matrix(
            T
        )


    def component_visual_centroid(
        component_id
    ):
        """
        Centro médio das fotografias no sistema visual bruto
        do componente.

        Ao alterar a escala do componente, mantemos este ponto
        fixo em UTM para evitar deslocamentos artificiais.
        """

        nodes = components[
            component_id
        ]

        centers = []

        for node in nodes:

            center_visual = transform_points(

                local_visual_poses[
                    node
                ],

                image_center_for_node(
                    node
                )

            )[0]

            centers.append(
                center_visual
            )

        return np.mean(
            np.asarray(
                centers,
                dtype=np.float64
            ),
            axis=0
        )


    def rescale_component_about_centroid(
        T,
        component_id,
        factor
    ):
        """
        Multiplica apenas a escala métrica do componente.

        - preserva orientação;
        - preserva paridade;
        - mantém o centro visual médio no mesmo ponto UTM.
        """

        factor = float(
            factor
        )

        pivot_visual = (
            component_visual_centroid(
                component_id
            )
        )

        pivot_utm = transform_points(
            T,
            np.array([
                pivot_visual
            ])
        )[0]

        A_old = T[
            :2,
            :2
        ]

        A_new = (
            factor
            *
            A_old
        )

        t_new = (
            pivot_utm
            -
            A_new
            @
            pivot_visual
        )

        T_new = T.copy()

        T_new[
            :2,
            :2
        ] = A_new

        T_new[
            :2,
            2
        ] = t_new

        return T_new


    # ------------------------------------------------------------
    # Escala atual de cada foto
    # ------------------------------------------------------------

    pre_scale_edge_mpp = {
        i:
            current_image_m_per_px(
                i
            )
        for i in range(
            len(
                gdf
            )
        )
    }


    # ------------------------------------------------------------
    # Selecionar arestas que podem informar SOMENTE escala
    # ------------------------------------------------------------

    scale_edge_rows = []


    for _, row in registration_df.iterrows():

        a = int(
            row[
                "index_a"
            ]
        )

        b = int(
            row[
                "index_b"
            ]
        )

        component_a = component_of[
            a
        ]

        component_b = component_of[
            b
        ]

        temporal_gap = abs(
            b - a
        )

        n_inliers = pd.to_numeric(
            row.get(
                "inliers",
                np.nan
            ),
            errors="coerce"
        )

        median_error = pd.to_numeric(
            row.get(
                "error_median_sift_px",
                np.nan
            ),
            errors="coerce"
        )

        rotation_deg = pd.to_numeric(
            row.get(
                "rotation_deg",
                np.nan
            ),
            errors="coerce"
        )

        scale_est = pd.to_numeric(
            row.get(
                "scale",
                np.nan
            ),
            errors="coerce"
        )

        registration_status = str(
            row.get(
                "status",
                ""
            )
        ).strip().lower()


        finite_registration = bool(
            np.isfinite(
                n_inliers
            )
            and
            np.isfinite(
                median_error
            )
            and
            np.isfinite(
                rotation_deg
            )
            and
            np.isfinite(
                scale_est
            )
        )


        # --------------------------------------------------------
        # v3.1.3 — política conservadora para arestas de escala
        # --------------------------------------------------------
        #
        # A classificação geométrica continua sendo a primeira barreira:
        # "rejeitado" significa que a transformação não é confiável o
        # suficiente para substituir/alterar escala, mesmo que alguns
        # inliers tenham produzido um valor numérico de scale.
        #
        status_allowed = (
            registration_status
            in
            SCALE_EDGE_ALLOWED_STATUSES
        )

        accepted = bool(
            finite_registration

            and
            status_allowed

            and
            temporal_gap
            <=
            SCALE_EDGE_MAX_TEMPORAL_GAP

            and
            n_inliers
            >=
            SCALE_EDGE_MIN_INLIERS

            and
            median_error
            <=
            SCALE_EDGE_MAX_MEDIAN_ERROR_PX

            and
            abs(
                rotation_deg
            )
            <=
            SCALE_EDGE_MAX_ABS_ROTATION_DEG

            and
            SCALE_EDGE_MIN_RELATIVE_SCALE
            <=
            scale_est
            <=
            SCALE_EDGE_MAX_RELATIVE_SCALE
        )


        # Diagnóstico explícito do motivo de aceitação/rejeição.
        rejection_reasons = []

        if not finite_registration:
            rejection_reasons.append(
                "registro_incompleto"
            )

        if not status_allowed:
            rejection_reasons.append(
                f"status_{registration_status or 'vazio'}_nao_permitido"
            )

        if (
            temporal_gap
            >
            SCALE_EDGE_MAX_TEMPORAL_GAP
        ):
            rejection_reasons.append(
                "gap_temporal_alto"
            )

        if (
            np.isfinite(
                n_inliers
            )
            and
            n_inliers
            <
            SCALE_EDGE_MIN_INLIERS
        ):
            rejection_reasons.append(
                "poucos_inliers"
            )

        if (
            np.isfinite(
                median_error
            )
            and
            median_error
            >
            SCALE_EDGE_MAX_MEDIAN_ERROR_PX
        ):
            rejection_reasons.append(
                "erro_reprojecao_alto"
            )

        if (
            np.isfinite(
                rotation_deg
            )
            and
            abs(
                rotation_deg
            )
            >
            SCALE_EDGE_MAX_ABS_ROTATION_DEG
        ):
            rejection_reasons.append(
                "rotacao_relativa_alta"
            )

        if (
            np.isfinite(
                scale_est
            )
            and
            not (
                SCALE_EDGE_MIN_RELATIVE_SCALE
                <=
                scale_est
                <=
                SCALE_EDGE_MAX_RELATIVE_SCALE
            )
        ):
            rejection_reasons.append(
                "escala_relativa_fora_limite"
            )

        scale_edge_decision = (
            "aceita"
            if accepted
            else ";".join(
                rejection_reasons
            )
        )


        baseline_ratio = (
            pre_scale_edge_mpp[
                b
            ]
            /
            pre_scale_edge_mpp[
                a
            ]
        )


        if (
            accepted
            and
            baseline_ratio > 0
        ):

            rhs_log = (
                math.log(
                    scale_est
                )
                -
                math.log(
                    baseline_ratio
                )
            )

            weight = math.sqrt(
                float(
                    n_inliers
                )
                /
                max(
                    float(
                        median_error
                    ),
                    SCALE_EDGE_ERROR_FLOOR_PX
                )
            )

        else:

            rhs_log = np.nan
            weight = np.nan


        scale_edge_rows.append({

            "index_a":
                a,

            "index_b":
                b,

            "filename_a":
                gdf.iloc[
                    a
                ][
                    "filename"
                ],

            "filename_b":
                gdf.iloc[
                    b
                ][
                    "filename"
                ],

            "component_a":
                component_a,

            "component_b":
                component_b,

            "cross_component":
                component_a
                !=
                component_b,

            "registration_status":
                registration_status,

            "status_allowed_for_scale":
                status_allowed,

            "scale_edge_decision":
                scale_edge_decision,

            "temporal_gap":
                temporal_gap,

            "inliers":
                n_inliers,

            "median_error_px":
                median_error,

            "rotation_deg":
                rotation_deg,

            "visual_scale_b_over_a":
                scale_est,

            "baseline_mpp_a":
                pre_scale_edge_mpp[
                    a
                ],

            "baseline_mpp_b":
                pre_scale_edge_mpp[
                    b
                ],

            "baseline_ratio_b_over_a":
                baseline_ratio,

            "rhs_log":
                rhs_log,

            "weight":
                weight,

            "accepted_as_scale_edge":
                accepted,

        })


    scale_edges_df = pd.DataFrame(
        scale_edge_rows
    )


    scale_edges_df[
        "used_between_components"
    ] = (

        scale_edges_df[
            "accepted_as_scale_edge"
        ]

        &

        scale_edges_df[
            "cross_component"
        ]

    )


    # ------------------------------------------------------------
    # Componentes-âncora
    # ------------------------------------------------------------
    #
    # Preferimos exatamente os componentes aceitos na calibração
    # global. Se não houver nenhum, usamos os componentes
    # visualmente informativos como fallback.

    if len(
        accepted_df
    ) > 0:

        scale_anchor_components = set(
            accepted_df[
                "component_id"
            ]
            .astype(
                int
            )
            .tolist()
        )

    else:

        scale_anchor_components = set(
            informative_df[
                "component_id"
            ]
            .astype(
                int
            )
            .tolist()
        )


    # ------------------------------------------------------------
    # Grafo entre COMPONENTES
    # ------------------------------------------------------------

    component_scale_adjacency = {
        component_id: set()
        for component_id in range(
            len(
                components
            )
        )
    }


    usable_scale_edges = (
        scale_edges_df[
            scale_edges_df[
                "used_between_components"
            ]
        ]
        .copy()
    )


    for _, edge in usable_scale_edges.iterrows():

        ca = int(
            edge[
                "component_a"
            ]
        )

        cb = int(
            edge[
                "component_b"
            ]
        )

        component_scale_adjacency[
            ca
        ].add(
            cb
        )

        component_scale_adjacency[
            cb
        ].add(
            ca
        )


    def scale_graph_connected_sets():
        visited = set()
        groups = []

        for start in range(
            len(
                components
            )
        ):

            if start in visited:
                continue

            queue = [
                start
            ]

            visited.add(
                start
            )

            group = []

            while queue:

                current = queue.pop(
                    0
                )

                group.append(
                    current
                )

                for neighbor in component_scale_adjacency[
                    current
                ]:

                    if neighbor not in visited:

                        visited.add(
                            neighbor
                        )

                        queue.append(
                            neighbor
                        )

            groups.append(
                sorted(
                    group
                )
            )

        return groups


    # ------------------------------------------------------------
    # Resolver multiplicadores q_c
    # ------------------------------------------------------------

    component_scale_edge_factor = {
        component_id: 1.0
        for component_id in range(
            len(
                components
            )
        )
    }


    component_scale_edge_supported = {
        component_id: False
        for component_id in range(
            len(
                components
            )
        )
    }


    component_scale_edge_anchor = {
        component_id:
            component_id
            in
            scale_anchor_components

        for component_id in range(
            len(
                components
            )
        )
    }


    if (
        USE_SCALE_EDGE_REGULARIZATION
        and
        len(
            usable_scale_edges
        ) > 0
    ):

        for group in scale_graph_connected_sets():

            group_set = set(
                group
            )

            anchors_here = (
                group_set
                &
                scale_anchor_components
            )

            # Sem âncora forte:
            # não alteramos nenhuma escala.
            if not anchors_here:
                continue

            variable_components = sorted(
                group_set
                -
                anchors_here
            )

            for component_id in group:
                component_scale_edge_supported[
                    component_id
                ] = True

            if not variable_components:
                continue

            variable_index = {
                component_id: k
                for k, component_id
                in enumerate(
                    variable_components
                )
            }


            group_edges = usable_scale_edges[
                usable_scale_edges[
                    "component_a"
                ].isin(
                    group_set
                )
                &
                usable_scale_edges[
                    "component_b"
                ].isin(
                    group_set
                )
            ].copy()


            def residuals_scale_network(
                x
            ):

                residuals = []

                for _, edge in group_edges.iterrows():

                    ca = int(
                        edge[
                            "component_a"
                        ]
                    )

                    cb = int(
                        edge[
                            "component_b"
                        ]
                    )


                    xa = (
                        x[
                            variable_index[
                                ca
                            ]
                        ]
                        if ca
                        in
                        variable_index
                        else 0.0
                    )


                    xb = (
                        x[
                            variable_index[
                                cb
                            ]
                        ]
                        if cb
                        in
                        variable_index
                        else 0.0
                    )


                    residuals.append(

                        (
                            (
                                xb
                                -
                                xa
                            )
                            -
                            float(
                                edge[
                                    "rhs_log"
                                ]
                            )
                        )

                        *

                        float(
                            edge[
                                "weight"
                            ]
                        )

                    )

                return np.asarray(
                    residuals,
                    dtype=np.float64
                )


            x0 = np.zeros(
                len(
                    variable_components
                ),
                dtype=np.float64
            )


            lower = np.full_like(
                x0,
                math.log(
                    SCALE_EDGE_COMPONENT_FACTOR_MIN
                )
            )


            upper = np.full_like(
                x0,
                math.log(
                    SCALE_EDGE_COMPONENT_FACTOR_MAX
                )
            )


            opt_scale = least_squares(

                residuals_scale_network,

                x0,

                bounds=(
                    lower,
                    upper
                ),

                method="trf",

                loss="soft_l1",

                f_scale=1.0,

                max_nfev=1000,

                verbose=0

            )


            for component_id in variable_components:

                factor = math.exp(

                    float(
                        opt_scale.x[
                            variable_index[
                                component_id
                            ]
                        ]
                    )

                )


                component_scale_edge_factor[
                    component_id
                ] = factor


    # ------------------------------------------------------------
    # Aplicar fatores aos componentes
    # ------------------------------------------------------------

    before_scale_edge_component_scale = {
        component_id:
            metric_scale_from_matrix(
                component_to_utm[
                    component_id
                ]
            )

        for component_id in range(
            len(
                components
            )
        )
    }


    for component_id in range(
        len(
            components
        )
    ):

        factor = component_scale_edge_factor[
            component_id
        ]

        if (
            USE_SCALE_EDGE_REGULARIZATION
            and
            abs(
                factor - 1.0
            )
            >
            1e-9
        ):

            component_to_utm[
                component_id
            ] = (
                rescale_component_about_centroid(

                    component_to_utm[
                        component_id
                    ],

                    component_id,

                    factor

                )
            )


    # ------------------------------------------------------------
    # Atualizar diagnóstico geométrico dos componentes
    # ------------------------------------------------------------

    component_scale_adjustment_rows = []


    for component_id, nodes in enumerate(
        components
    ):

        T_component = component_to_utm[
            component_id
        ]

        before_scale = (
            before_scale_edge_component_scale[
                component_id
            ]
        )

        after_scale = (
            metric_scale_from_matrix(
                T_component
            )
        )

        factor = (
            component_scale_edge_factor[
                component_id
            ]
        )


        src_centers, dst_centers = (
            component_center_correspondences(
                nodes,
                flip_visual_y=False
            )
        )


        predicted_centers = transform_points(
            T_component,
            src_centers
        )


        gps_errors = np.linalg.norm(
            predicted_centers
            -
            dst_centers,
            axis=1
        )


        component_scale_adjustment_rows.append({

            "component_id":
                component_id,

            "n_images":
                len(
                    nodes
                ),

            "scale_edge_anchor":
                component_scale_edge_anchor[
                    component_id
                ],

            "scale_edge_supported":
                component_scale_edge_supported[
                    component_id
                ],

            "scale_edge_factor":
                factor,

            "before_scale_edge_m_per_visual":
                before_scale,

            "after_scale_edge_m_per_visual":
                after_scale,

            "gps_fit_median_after_scale_edge_m":
                float(
                    np.median(
                        gps_errors
                    )
                ),

            "gps_fit_rms_after_scale_edge_m":
                float(
                    np.sqrt(
                        np.mean(
                            gps_errors**2
                        )
                    )
                ),

        })


    component_scale_adjustment_df = pd.DataFrame(
        component_scale_adjustment_rows
    )


    # Incorporar os novos campos na tabela geométrica principal.

    component_geo_df = component_geo_df.drop(
        columns=[
            c
            for c in [
                "scale_edge_anchor",
                "scale_edge_supported",
                "scale_edge_factor",
                "before_scale_edge_m_per_visual",
                "after_scale_edge_m_per_visual",
                "gps_fit_median_after_scale_edge_m",
                "gps_fit_rms_after_scale_edge_m",
            ]
            if c in component_geo_df.columns
        ],
        errors="ignore"
    )


    component_geo_df = component_geo_df.merge(
        component_scale_adjustment_df,
        on=[
            "component_id",
            "n_images"
        ],
        how="left"
    )


    # Atualizar campos que agora representam a geometria FINAL.

    component_geo_df[
        "final_component_m_per_visual"
    ] = component_geo_df[
        "after_scale_edge_m_per_visual"
    ]


    component_geo_df[
        "final_to_agl_corrected_ratio"
    ] = (

        component_geo_df[
            "final_component_m_per_visual"
        ]

        /

        component_geo_df[
            "agl_corrected_component_m_per_visual"
        ]

    )


    adjusted_mask = (
        np.abs(
            component_geo_df[
                "scale_edge_factor"
            ]
            -
            1.0
        )
        >
        1e-9
    )


    component_geo_df.loc[
        adjusted_mask,
        "scale_source"
    ] = (

        component_geo_df.loc[
            adjusted_mask,
            "scale_source"
        ]
        .astype(
            str
        )
        +
        "+scale_edge"
    )


    component_geo_df[
        "final_geo_fit_median_m"
    ] = component_geo_df[
        "gps_fit_median_after_scale_edge_m"
    ]


    component_geo_df[
        "final_geo_fit_rms_m"
    ] = component_geo_df[
        "gps_fit_rms_after_scale_edge_m"
    ]


    component_geo_df[
        "final_det"
    ] = component_geo_df[
        "component_id"
    ].map(
        lambda component_id:
            float(
                np.linalg.det(
                    component_to_utm[
                        int(
                            component_id
                        )
                    ][
                        :2,
                        :2
                    ]
                )
            )
    )


    component_geo_df[
        "parity_ok"
    ] = (
        component_geo_df[
            "final_det"
        ]
        <
        0
    )


    # ------------------------------------------------------------
    # Salvar diagnósticos da rede de escala
    # ------------------------------------------------------------

    scale_edges_df.to_csv(
        OUTPUT_DIR
        /
        "arestas_escala.csv",
        index=False
    )


    component_scale_adjustment_df.to_csv(
        OUTPUT_DIR
        /
        "ajuste_escala_componentes.csv",
        index=False
    )


    component_geo_df.to_csv(
        OUTPUT_DIR
        /
        "componentes_geometricos.csv",
        index=False
    )


    print()
    print("=" * 75)
    print("REGULARIZAÇÃO POR ARESTAS DE ESCALA")
    print("=" * 75)

    print()
    print(
        "Arestas aceitas para escala:",
        int(
            scale_edges_df[
                "accepted_as_scale_edge"
            ].sum()
        )
    )

    print(
        "Arestas usadas entre componentes:",
        int(
            scale_edges_df[
                "used_between_components"
            ].sum()
        )
    )

    blocked_rejected_scale_edges = scale_edges_df[
        (
            scale_edges_df[
                "registration_status"
            ]
            ==
            "rejeitado"
        )
        &
        scale_edges_df[
            "cross_component"
        ]
    ].copy()

    print(
        "Arestas rejeitadas bloqueadas para escala:",
        len(
            blocked_rejected_scale_edges
        )
    )

    print(
        "Componentes-âncora:",
        sorted(
            scale_anchor_components
        )
    )

    print(
        "Componentes efetivamente reescalados:",
        int(
            adjusted_mask.sum()
        )
    )

    print()

    display(
        component_scale_adjustment_df
    )


    print()
    print(
        "Arestas de escala entre componentes:"
    )

    display(
        scale_edges_df[
            scale_edges_df[
                "used_between_components"
            ]
        ][
            [
                "index_a",
                "index_b",
                "component_a",
                "component_b",
                "registration_status",
                "inliers",
                "median_error_px",
                "rotation_deg",
                "visual_scale_b_over_a",
                "baseline_ratio_b_over_a",
                "weight",
            ]
        ]
    )


    # ============================================================
    # POSES FINAIS pixel -> UTM
    # ============================================================

    final_T_utm = {}

    for i in range(
        len(
            gdf
        )
    ):

        component_id = component_of[
            i
        ]

        final_T_utm[
            i
        ] = (

            component_to_utm[
                component_id
            ]

            @

            local_visual_poses[
                i
            ]

        )

    bad_pose_det = []

    for i in range(
        len(
            gdf
        )
    ):
        det_i = float(
            np.linalg.det(
                final_T_utm[
                    i
                ][
                    :2,
                    :2
                ]
            )
        )

        if not (
            det_i < 0
        ):
            bad_pose_det.append(
                (
                    i,
                    det_i,
                    gdf.iloc[
                        i
                    ][
                        "filename"
                    ]
                )
            )

    if len(
        bad_pose_det
    ) > 0:

        print()
        print(
            "[WARN] Fotos com paridade incorreta em final_T_utm:"
        )

        for item in bad_pose_det:
            print(item)

    else:

        print()
        print(
            "Todas as poses finais têm paridade correta (det < 0)."
        )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 26
    # ===========================================================================
    def similarity_scale_from_matrix(
        T
    ):
        """
        Escala isotrópica da parte linear de uma similaridade.

        Em final_T_utm, a unidade é metros por pixel original.
        """

        A = np.asarray(
            T,
            dtype=np.float64
        )[:2, :2]


        det = float(
            np.linalg.det(
                A
            )
        )


        return math.sqrt(
            abs(
                det
            )
        )


    def fov_diag_from_ground_scale(
        m_per_px,
        width,
        height,
        height_m
    ):
        """
        FOV diagonal equivalente que produziria a escala aprendida
        se a altura informada fosse verdadeira.
        """

        if (
            not np.isfinite(
                m_per_px
            )
            or
            not np.isfinite(
                height_m
            )
            or
            height_m <= 0
        ):
            return np.nan


        diag_px = math.hypot(
            max(
                width - 1,
                1
            ),
            max(
                height - 1,
                1
            )
        )


        ground_diag_m = (
            m_per_px
            *
            diag_px
        )


        return math.degrees(
            2.0
            *
            math.atan(
                ground_diag_m
                /
                (
                    2.0
                    *
                    height_m
                )
            )
        )


    final_pose_rows = []


    for i, row in gdf.iterrows():

        width = int(
            row[
                "image_width"
            ]
        )

        height = int(
            row[
                "image_height"
            ]
        )


        center = np.array([
            [
                (width - 1) / 2.0,
                (height - 1) / 2.0
            ]
        ])


        final_center = transform_points(

            final_T_utm[
                i
            ],

            center

        )[0]


        learned_m_per_px = (
            similarity_scale_from_matrix(
                final_T_utm[
                    i
                ]
            )
        )


        prior_m_per_px = float(
            row[
                "prior_m_per_px"
            ]
        )


        prior_scale_ratio = (
            learned_m_per_px
            /
            prior_m_per_px
            if (
                np.isfinite(
                    prior_m_per_px
                )
                and
                prior_m_per_px > 0
            )
            else np.nan
        )


        height_prior_m = float(
            row[
                "height_prior_m"
            ]
        )


        # Se o FOV-prior estivesse correto, esta seria a altura
        # equivalente sugerida pela escala final.
        height_equiv_m = (
            height_prior_m
            *
            prior_scale_ratio
            if np.isfinite(
                prior_scale_ratio
            )
            else np.nan
        )


        # Se a altura-prior estivesse correta, este seria o FOV
        # diagonal equivalente sugerido pela escala final.
        fov_equiv_deg = (
            fov_diag_from_ground_scale(
                learned_m_per_px,
                width,
                height,
                height_prior_m
            )
        )


        final_pose_rows.append({

            "index":
                i,

            "filename":
                row[
                    "filename"
                ],

            "component_id":
                component_of[
                    i
                ],

            "component_size":
                int(
                    len(
                        components[
                            component_of[i]
                        ]
                    )
                ),

            "scale_source":
                component_geo_df.set_index(
                    "component_id"
                ).loc[
                    component_of[i],
                    "scale_source"
                ],

            "global_scale_correction":
                float(
                    global_scale_correction
                ),

            "scale_edge_factor":
                float(
                    component_scale_edge_factor[
                        component_of[i]
                    ]
                ),

            "scale_edge_anchor":
                bool(
                    component_scale_edge_anchor[
                        component_of[i]
                    ]
                ),

            "coarse_x_utm":
                float(
                    row[
                        "x0"
                    ]
                ),

            "coarse_y_utm":
                float(
                    row[
                        "y0"
                    ]
                ),

            "final_x_utm":
                float(
                    final_center[
                        0
                    ]
                ),

            "final_y_utm":
                float(
                    final_center[
                        1
                    ]
                ),

            "height_prior_m":
                height_prior_m,

            "height_agl_corrected_m":
                float(
                    gdf.iloc[
                        i
                    ][
                        "height_agl_corrected_m"
                    ]
                ),

            "learned_agl_offset_m":
                float(
                    learned_agl_offset_m
                ),

            "height_prior_source":
                row[
                    "height_prior_source"
                ],

            "fov_diag_prior_deg":
                float(
                    row[
                        "fov_diag_prior_deg"
                    ]
                ),

            "fov_prior_source":
                row[
                    "fov_prior_source"
                ],

            "prior_m_per_px":
                prior_m_per_px,

            "learned_m_per_px":
                learned_m_per_px,

            "learned_cm_per_px":
                learned_m_per_px
                *
                100.0,

            "prior_scale_ratio":
                prior_scale_ratio,

            "height_equiv_if_fov_prior_correct_m":
                height_equiv_m,

            "fov_equiv_if_height_prior_correct_deg":
                fov_equiv_deg,

        })


    final_pose_df = pd.DataFrame(
        final_pose_rows
    )


    final_pose_df.to_csv(
        OUTPUT_DIR
        /
        "poses_finais_utm.csv",
        index=False
    )


    # ============================================================
    # VISUALIZAÇÃO DAS POSES
    # ============================================================

    fig, ax = plt.subplots(
        figsize=(
            12,
            10
        )
    )


    for component_id, nodes in enumerate(
        components
    ):

        subset = final_pose_df[
            final_pose_df[
                "component_id"
            ]
            ==
            component_id
        ]


        ax.scatter(

            subset[
                "final_x_utm"
            ],

            subset[
                "final_y_utm"
            ],

            s=30,

            label=
                f"C{component_id}"

        )


    for _, edge in ok_edges_df.iterrows():

        a = int(
            edge[
                "index_a"
            ]
        )

        b = int(
            edge[
                "index_b"
            ]
        )


        pa = (
            final_pose_df
            .set_index(
                "index"
            )
            .loc[
                a
            ]
        )


        pb = (
            final_pose_df
            .set_index(
                "index"
            )
            .loc[
                b
            ]
        )


        ax.plot(

            [
                pa[
                    "final_x_utm"
                ],
                pb[
                    "final_x_utm"
                ]
            ],

            [
                pa[
                    "final_y_utm"
                ],
                pb[
                    "final_y_utm"
                ]
            ],

            linewidth=1

        )


    for _, row in final_pose_df.iterrows():

        ax.text(

            row[
                "final_x_utm"
            ],

            row[
                "final_y_utm"
            ],

            str(
                int(
                    row[
                        "index"
                    ]
                )
            ),

            fontsize=8,

            ha="center",

            va="center"

        )


    ax.set_aspect(
        "equal"
    )


    ax.set_title(
        "Poses finais auto-calibradas em UTM"
    )


    if (
        len(
            components
        )
        >
        1
    ):

        ax.legend()


    plt.tight_layout()
    poses_plot_path = OUTPUT_DIR / "diagnostico_poses_finais.png"
    fig.savefig(
        poses_plot_path,
        dpi=160,
        bbox_inches="tight"
    )
    plt.close(fig)
    print("Diagnóstico:", poses_plot_path)


    print()
    print(
        "Escala aprendida "
        "(cm/pixel):"
    )

    display(
        final_pose_df[
            [
                "index",
                "filename",
                "component_id",
                "component_size",
                "scale_source",
                "scale_edge_factor",
                "scale_edge_anchor",
                "height_prior_m",
                "height_prior_source",
                "fov_diag_prior_deg",
                "fov_prior_source",
                "learned_cm_per_px",
                "prior_scale_ratio",
                "height_equiv_if_fov_prior_correct_m",
                "fov_equiv_if_height_prior_correct_deg",
            ]
        ]
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 27
    # ===========================================================================
    # ============================================================
    # 10.1. DIAGNÓSTICO DE CONECTIVIDADE, GPS E PRIORS
    # ============================================================
    #
    # Este diagnóstico NÃO remove fotografias.
    # Ele apenas identifica casos que merecem inspeção.


    degree_ok = {
        i: 0
        for i in range(
            len(gdf)
        )
    }


    for _, edge in ok_edges_df.iterrows():

        a = int(
            edge[
                "index_a"
            ]
        )

        b = int(
            edge[
                "index_b"
            ]
        )

        degree_ok[
            a
        ] += 1

        degree_ok[
            b
        ] += 1


    component_sizes = {
        component_id:
            len(
                nodes
            )
        for component_id, nodes
        in enumerate(
            components
        )
    }


    final_pose_lookup = (
        final_pose_df
        .set_index(
            "index"
        )
    )


    diagnostic_rows = []


    for i, row in gdf.iterrows():

        component_id = component_of[
            i
        ]


        final_row = final_pose_lookup.loc[
            i
        ]


        diagnostic_rows.append({

            "index":
                i,

            "filename":
                row[
                    "filename"
                ],

            "component_id":
                component_id,

            "component_size":
                component_sizes[
                    component_id
                ],

            "degree_ok":
                degree_ok[
                    i
                ],

            "x0_gps":
                float(
                    row[
                        "x0"
                    ]
                ),

            "y0_gps":
                float(
                    row[
                        "y0"
                    ]
                ),

            "final_x":
                float(
                    final_row[
                        "final_x_utm"
                    ]
                ),

            "final_y":
                float(
                    final_row[
                        "final_y_utm"
                    ]
                ),

            "height_prior_m":
                float(
                    final_row[
                        "height_prior_m"
                    ]
                ),

            "height_prior_source":
                final_row[
                    "height_prior_source"
                ],

            "fov_diag_prior_deg":
                float(
                    final_row[
                        "fov_diag_prior_deg"
                    ]
                ),

            "fov_prior_source":
                final_row[
                    "fov_prior_source"
                ],

            "learned_cm_per_px":
                float(
                    final_row[
                        "learned_cm_per_px"
                    ]
                ),

            "prior_scale_ratio":
                float(
                    final_row[
                        "prior_scale_ratio"
                    ]
                ),

        })


    diagnostic_df = pd.DataFrame(
        diagnostic_rows
    )


    diagnostic_df[
        "gps_to_final_m"
    ] = np.sqrt(

        (
            diagnostic_df[
                "final_x"
            ]
            -
            diagnostic_df[
                "x0_gps"
            ]
        ) ** 2

        +

        (
            diagnostic_df[
                "final_y"
            ]
            -
            diagnostic_df[
                "y0_gps"
            ]
        ) ** 2

    )


    diagnostic_df[
        "prior_scale_alert"
    ] = (

        (
            diagnostic_df[
                "prior_scale_ratio"
            ]
            <
            PRIOR_SCALE_ALERT_MIN
        )

        |

        (
            diagnostic_df[
                "prior_scale_ratio"
            ]
            >
            PRIOR_SCALE_ALERT_MAX
        )

    )


    diagnostic_df = (
        diagnostic_df
        .sort_values(

            [
                "component_size",
                "degree_ok",
                "gps_to_final_m"
            ],

            ascending=[
                True,
                True,
                False
            ]

        )
        .reset_index(
            drop=True
        )
    )


    display(
        diagnostic_df
    )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 28
    # ===========================================================================
    # ============================================================
    # 10.2. MARCAR FOTOS QUE MERECEM INSPEÇÃO
    # ============================================================
    #
    # "suspeita" continua sendo apenas um alerta estrutural/GPS.
    #
    # Um conflito com FOV/altura-prior fica em prior_scale_alert,
    # mas NÃO é motivo automático para excluir a foto:
    # justamente porque os priors podem estar errados.


    diagnostic_df[
        "suspeita"
    ] = False


    diagnostic_df[
        "motivo"
    ] = ""


    # ------------------------------------------------------------
    # Regra 1 — componente unitário
    # ------------------------------------------------------------

    mask = (
        diagnostic_df[
            "component_size"
        ]
        ==
        1
    )


    diagnostic_df.loc[
        mask,
        "suspeita"
    ] = True


    diagnostic_df.loc[
        mask,
        "motivo"
    ] += (
        "componente_unitario; "
    )


    # ------------------------------------------------------------
    # Regra 2 — componente pequeno e pouco conectado
    # ------------------------------------------------------------

    mask = (

        (
            diagnostic_df[
                "component_size"
            ]
            <=
            SMALL_COMPONENT_MAX_SIZE
        )

        &

        (
            diagnostic_df[
                "degree_ok"
            ]
            <=
            LOW_DEGREE_MAX
        )

    )


    diagnostic_df.loc[
        mask,
        "suspeita"
    ] = True


    diagnostic_df.loc[
        mask,
        "motivo"
    ] += (
        "componente_pequeno_pouco_conectado; "
    )


    # ------------------------------------------------------------
    # Regra 3 — grande deslocamento final em relação ao GPS
    # ------------------------------------------------------------

    mask = (
        diagnostic_df[
            "gps_to_final_m"
        ]
        >
        SUSPECT_GPS_DISTANCE_M
    )


    diagnostic_df.loc[
        mask,
        "suspeita"
    ] = True


    diagnostic_df.loc[
        mask,
        "motivo"
    ] += (
        "desvio_gps_alto; "
    )


    suspect_df = (
        diagnostic_df[
            diagnostic_df[
                "suspeita"
            ]
        ]
        .copy()
    )


    prior_alert_df = (
        diagnostic_df[
            diagnostic_df[
                "prior_scale_alert"
            ]
        ]
        .copy()
    )


    print(
        "Fotos marcadas para inspeção estrutural/GPS:",
        len(
            suspect_df
        )
    )


    print(
        "Fotos com prior de escala muito diferente do aprendido:",
        len(
            prior_alert_df
        )
    )


    print(
        "Exclusão automática:",
        AUTO_EXCLUDE_SUSPECTS
    )


    if len(
        suspect_df
    ) > 0:

        display(
            suspect_df
        )


    if len(
        prior_alert_df
    ) > 0:

        print()
        print(
            "Conflitos entre prior e escala aprendida "
            "(não excluem fotos):"
        )

        display(
            prior_alert_df[
                [
                    "index",
                    "filename",
                    "height_prior_m",
                    "height_prior_source",
                    "fov_diag_prior_deg",
                    "fov_prior_source",
                    "learned_cm_per_px",
                    "prior_scale_ratio",
                ]
            ]
        )



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 30
    # ===========================================================================
    def show_pair_inliers(
        index_a,
        index_b,
        max_draw=150,
        output_path=None
    ):
        feat_a = features_cache[index_a]
        feat_b = features_cache[index_b]

        kp_a = feat_a["kp"]
        kp_b = feat_b["kp"]

        des_a = feat_a["des"]
        des_b = feat_b["des"]

        if des_a is None or des_b is None:
            raise RuntimeError(
                "Uma das imagens não possui descritores SIFT."
            )

        img_a = cv2.imread(
            str(feat_a["path"]),
            cv2.IMREAD_GRAYSCALE
        )

        img_b = cv2.imread(
            str(feat_b["path"]),
            cv2.IMREAD_GRAYSCALE
        )

        if img_a is None or img_b is None:
            raise RuntimeError(
                "Não foi possível abrir uma das imagens."
            )

        if feat_a["scale"] < 1.0:
            h, w = feat_a["shape_sift"]
            img_a = cv2.resize(
                img_a,
                (w, h),
                interpolation=cv2.INTER_AREA
            )

        if feat_b["scale"] < 1.0:
            h, w = feat_b["shape_sift"]
            img_b = cv2.resize(
                img_b,
                (w, h),
                interpolation=cv2.INTER_AREA
            )

        knn = get_matcher().knnMatch(
            des_a,
            des_b,
            k=2
        )

        good = []

        for pair in knn:
            if len(pair) < 2:
                continue

            m, n = pair

            if (
                m.distance
                < LOWE_RATIO * n.distance
            ):
                good.append(m)

        if len(good) < MIN_MATCHES_TO_TRY:
            raise RuntimeError(
                f"Poucos matches: {len(good)}"
            )

        pts_a = np.float32([
            kp_a[m.queryIdx].pt
            for m in good
        ])

        pts_b = np.float32([
            kp_b[m.trainIdx].pt
            for m in good
        ])

        _, mask = cv2.estimateAffinePartial2D(
            pts_b,
            pts_a,
            method=cv2.RANSAC,
            ransacReprojThreshold=RANSAC_THRESHOLD_PX,
            maxIters=RANSAC_MAX_ITERS,
            confidence=RANSAC_CONFIDENCE,
            refineIters=50
        )

        if mask is None:
            raise RuntimeError(
                "RANSAC não encontrou uma transformação."
            )

        keep = (
            mask
            .ravel()
            .astype(bool)
        )

        inlier_matches = [
            m
            for m, flag in zip(
                good,
                keep
            )
            if flag
        ]

        inlier_matches = sorted(
            inlier_matches,
            key=lambda m: m.distance
        )

        drawn = cv2.drawMatches(
            img_a,
            kp_a,
            img_b,
            kp_b,
            inlier_matches[:max_draw],
            None,
            flags=cv2.DrawMatchesFlags_NOT_DRAW_SINGLE_POINTS
        )

        plt.figure(
            figsize=(24, 12)
        )

        plt.imshow(
            drawn,
            cmap="gray"
        )

        plt.axis("off")

        plt.title(
            f"{gdf.iloc[index_a]['filename']} × "
            f"{gdf.iloc[index_b]['filename']} — "
            f"{int(keep.sum())}/{len(good)} inliers"
        )

        plt.tight_layout()

        if output_path is None:
            output_path = (
                OUTPUT_DIR
                /
                f"inliers_{index_a}_{index_b}.jpg"
            )

        output_path = Path(output_path)

        plt.savefig(
            output_path,
            dpi=150,
            bbox_inches="tight"
        )

        plt.close()

        print("Inliers salvos em:", output_path)

        return output_path



    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 33
    # ===========================================================================
    # ============================================================
    # 11. MONTAR O MOSAICO FINAL
    # ============================================================
    #
    # Nesta etapa:
    #
    # - usamos as poses finais final_T_utm;
    # - fotos suspeitas só são excluídas se AUTO_EXCLUDE_SUSPECTS=True;
    # - cada pixel pertence a UMA ÚNICA fotografia;
    # - nas sobreposições, escolhemos a foto cujo centro
    #   está mais próximo;
    # - ao final, rotacionamos automaticamente o mosaico
    #   para deixar seu eixo principal na horizontal;
    # - RGB e source_map são rotacionados juntos.
    #
    # Não há blending.


    # ============================================================
    # 1. LER IMAGEM RGB
    # ============================================================

    def read_image_rgb(path):

        arr = cv2.imread(
            str(path),
            cv2.IMREAD_COLOR
        )

        if arr is None:

            with Image.open(path) as im:

                return np.asarray(
                    im.convert("RGB")
                )

        return cv2.cvtColor(
            arr,
            cv2.COLOR_BGR2RGB
        )


    # ============================================================
    # 2. DEFINIR QUAIS FOTOS ENTRAM NO MOSAICO
    # ============================================================
    #
    # Por padrão usamos todas as fotos.
    # A exclusão de suspeitas é opcional.

    if (
        AUTO_EXCLUDE_SUSPECTS
        and
        "diagnostic_df" in globals()
        and
        "suspeita" in diagnostic_df.columns
    ):

        valid_indices_for_mosaic = set(
            diagnostic_df.loc[
                ~diagnostic_df["suspeita"],
                "index"
            ].astype(int)
        )

    else:

        valid_indices_for_mosaic = set(
            range(len(gdf))
        )


    excluded_indices = sorted(
        set(range(len(gdf)))
        -
        valid_indices_for_mosaic
    )


    print("=" * 75)
    print("FOTOS UTILIZADAS NO MOSAICO")
    print("=" * 75)

    print()
    print(
        "Fotos usadas:",
        len(valid_indices_for_mosaic)
    )

    print(
        "Fotos excluídas:",
        len(excluded_indices)
    )

    print(
        "Índices excluídos:",
        excluded_indices
    )


    if excluded_indices:

        print()

        for i in excluded_indices:

            print(
                " -",
                i,
                gdf.iloc[i]["filename"]
            )


    if not valid_indices_for_mosaic:

        raise RuntimeError(
            "Nenhuma fotografia foi aprovada para o mosaico."
        )


    # ============================================================
    # 3. ESTIMAR RESOLUÇÃO ESPACIAL APRENDIDA
    # ============================================================
    #
    # A resolução final NÃO vem mais de FOV x altura.
    #
    # Cada final_T_utm já informa quantos metros correspondem
    # a um pixel original daquela fotografia.
    #
    # Usamos o MAIOR pixels/metro entre as fotos válidas, para que
    # o mosaico preserve a resolução máxima das fotos.

    px_per_m_values = []


    for i in sorted(
        valid_indices_for_mosaic
    ):

        learned_m_per_px = (
            similarity_scale_from_matrix(
                final_T_utm[
                    i
                ]
            )
        )


        if (
            np.isfinite(
                learned_m_per_px
            )
            and
            learned_m_per_px > 0
        ):

            px_per_m_values.append(
                1.0
                /
                learned_m_per_px
            )


    if not px_per_m_values:

        raise RuntimeError(
            "Não foi possível inferir "
            "a resolução espacial final."
        )


    native_px_per_m = float(
        np.max(
            px_per_m_values
        )
    )


    px_per_m = (
        native_px_per_m
        *
        MOSAIC_SCALE
    )


    # ============================================================
    # 4. CALCULAR BOUNDS APENAS DAS FOTOS VÁLIDAS
    # ============================================================

    all_corners_utm = []


    for i, row in gdf.iterrows():

        if i not in valid_indices_for_mosaic:
            continue


        corners = transform_points(

            final_T_utm[i],

            image_corners(
                int(
                    row["image_width"]
                ),
                int(
                    row["image_height"]
                )
            )

        )


        all_corners_utm.append(
            corners
        )


    all_corners_utm = np.vstack(
        all_corners_utm
    )


    minx = float(
        all_corners_utm[:, 0].min()
    )

    miny = float(
        all_corners_utm[:, 1].min()
    )

    maxx = float(
        all_corners_utm[:, 0].max()
    )

    maxy = float(
        all_corners_utm[:, 1].max()
    )


    # ============================================================
    # 5. DIMENSÃO DO CANVAS
    # ============================================================

    width_px = max(

        1,

        int(
            math.ceil(
                (maxx - minx)
                *
                px_per_m
            )
        )

    )


    height_px = max(

        1,

        int(
            math.ceil(
                (maxy - miny)
                *
                px_per_m
            )
        )

    )


    requested_pixels = (
        width_px
        *
        height_px
    )


    # ============================================================
    # 6. LIMITES DO RASTER FINAL
    # ============================================================
    #
    # Por padrão não há teto de pixels (resolução máxima das fotos).
    # Só reduzimos se MAX_OUTPUT_PIXELS for informado ou se algum lado
    # exceder o limite do formato JPEG.

    reduction_factor = 1.0
    reduction_reason = None

    if (
        MAX_OUTPUT_PIXELS is not None
        and
        requested_pixels
        >
        MAX_OUTPUT_PIXELS
    ):

        reduction_factor = math.sqrt(
            MAX_OUTPUT_PIXELS
            /
            requested_pixels
        )

        reduction_reason = "MAX_OUTPUT_PIXELS"


    longest_side_px = max(
        width_px,
        height_px
    )

    if longest_side_px * reduction_factor > JPEG_MAX_DIMENSION:

        reduction_factor = (
            JPEG_MAX_DIMENSION
            /
            longest_side_px
        )

        reduction_reason = "o limite de dimensão do JPEG"


    if reduction_reason is not None:

        px_per_m *= reduction_factor


        width_px = max(

            1,

            int(
                math.ceil(
                    (maxx - minx)
                    *
                    px_per_m
                )
            )

        )


        height_px = max(

            1,

            int(
                math.ceil(
                    (maxy - miny)
                    *
                    px_per_m
                )
            )

        )


        print()
        print(
            "[WARN] Resolução reduzida automaticamente "
            f"para respeitar {reduction_reason}."
        )


    print()
    print(
        f"Resolução nativa estimada: "
        f"{native_px_per_m:.2f} px/m"
    )

    print(
        f"Resolução efetiva: "
        f"{px_per_m:.2f} px/m"
    )

    print(
        "Canvas inicial:",
        width_px,
        "x",
        height_px
    )

    print(
        "Pixels:",
        f"{width_px * height_px:,}"
    )


    # ============================================================
    # 7. TRANSFORMAÇÃO UTM -> CANVAS
    # ============================================================
    #
    # UTM:
    #     x cresce para direita
    #     y cresce para cima
    #
    # imagem:
    #     x cresce para direita
    #     y cresce para baixo

    UTM_TO_CANVAS = np.array([

        [
            px_per_m,
            0.0,
            -minx * px_per_m
        ],

        [
            0.0,
            -px_per_m,
            maxy * px_per_m
        ],

        [
            0.0,
            0.0,
            1.0
        ],

    ], dtype=np.float64)


    # ============================================================
    # 8. CRIAR CANVAS
    # ============================================================

    mosaic = np.zeros(
        (
            height_px,
            width_px,
            3
        ),
        dtype=np.uint8
    )


    best_distance = np.full(
        (
            height_px,
            width_px
        ),
        np.inf,
        dtype=np.float32
    )


    source_map = np.full(
        (
            height_px,
            width_px
        ),
        -1,
        dtype=np.int16
    )


    # ============================================================
    # 9. PROJETAR AS FOTOGRAFIAS
    # ============================================================

    count_ok = 0
    count_fail = 0


    for i, row in gdf.iterrows():

        # --------------------------------------------------------
        # IMPORTANTE:
        # se a exclusão automática estiver ativa, ignoramos aqui também
        # --------------------------------------------------------

        if i not in valid_indices_for_mosaic:
            continue


        path = Path(
            row["source_path"]
        )


        print(
            f"Mosaico "
            f"[{count_ok + count_fail + 1}/"
            f"{len(valid_indices_for_mosaic)}] "
            f"{path.name}"
        )


        try:

            img = read_image_rgb(
                path
            )


            h_img, w_img = (
                img.shape[:2]
            )


            # ----------------------------------------------------
            # pixel da foto -> UTM -> canvas
            # ----------------------------------------------------

            T_canvas = (
                UTM_TO_CANVAS
                @ final_T_utm[i]
            )


            # ----------------------------------------------------
            # Cantos no canvas
            # ----------------------------------------------------

            corners_canvas = transform_points(

                T_canvas,

                image_corners(
                    w_img,
                    h_img
                )

            )


            # ----------------------------------------------------
            # Centro da foto no canvas
            # ----------------------------------------------------

            center_canvas = transform_points(

                T_canvas,

                np.array([
                    [
                        (w_img - 1) / 2.0,
                        (h_img - 1) / 2.0
                    ]
                ])

            )[0]


            # ----------------------------------------------------
            # ROI
            # ----------------------------------------------------

            roi_x0 = max(

                0,

                int(
                    math.floor(
                        corners_canvas[
                            :, 0
                        ].min()
                    )
                )
                - 2

            )


            roi_y0 = max(

                0,

                int(
                    math.floor(
                        corners_canvas[
                            :, 1
                        ].min()
                    )
                )
                - 2

            )


            roi_x1 = min(

                width_px,

                int(
                    math.ceil(
                        corners_canvas[
                            :, 0
                        ].max()
                    )
                )
                + 3

            )


            roi_y1 = min(

                height_px,

                int(
                    math.ceil(
                        corners_canvas[
                            :, 1
                        ].max()
                    )
                )
                + 3

            )


            if (
                roi_x1 <= roi_x0
                or
                roi_y1 <= roi_y0
            ):

                continue


            roi_w = (
                roi_x1
                -
                roi_x0
            )

            roi_h = (
                roi_y1
                -
                roi_y0
            )


            # ----------------------------------------------------
            # Transformação local ao ROI
            # ----------------------------------------------------

            T_roi = T_canvas.copy()


            T_roi[
                0, 2
            ] -= roi_x0


            T_roi[
                1, 2
            ] -= roi_y0


            # ----------------------------------------------------
            # Projetar RGB
            # ----------------------------------------------------

            warped = cv2.warpAffine(

                img,

                T_roi[:2, :],

                (
                    roi_w,
                    roi_h
                ),

                flags=cv2.INTER_LINEAR,

                borderMode=cv2.BORDER_CONSTANT,

                borderValue=0

            )


            # ----------------------------------------------------
            # Projetar máscara geométrica
            # ----------------------------------------------------

            source_mask = np.full(
                (
                    h_img,
                    w_img
                ),
                255,
                dtype=np.uint8
            )


            warped_mask = cv2.warpAffine(

                source_mask,

                T_roi[:2, :],

                (
                    roi_w,
                    roi_h
                ),

                flags=cv2.INTER_NEAREST,

                borderMode=cv2.BORDER_CONSTANT,

                borderValue=0

            )


            valid = (
                warped_mask
                >
                0
            )


            # ====================================================
            # 10. DISTÂNCIA AO CENTRO DA FOTO
            # ====================================================

            yy, xx = np.indices(
                (
                    roi_h,
                    roi_w
                ),
                dtype=np.float32
            )


            canvas_x = (
                xx
                +
                roi_x0
            )


            canvas_y = (
                yy
                +
                roi_y0
            )


            dist2 = (

                (
                    canvas_x
                    -
                    center_canvas[0]
                ) ** 2

                +

                (
                    canvas_y
                    -
                    center_canvas[1]
                ) ** 2

            )


            mosaic_roi = mosaic[
                roi_y0:roi_y1,
                roi_x0:roi_x1
            ]


            distance_roi = best_distance[
                roi_y0:roi_y1,
                roi_x0:roi_x1
            ]


            source_roi = source_map[
                roi_y0:roi_y1,
                roi_x0:roi_x1
            ]


            # ====================================================
            # 11. ESCOLHER A FOTOGRAFIA DONA DO PIXEL
            # ====================================================

            take = (

                valid

                &

                (
                    dist2
                    <
                    distance_roi
                )

            )


            mosaic_roi[
                take
            ] = warped[
                take
            ]


            distance_roi[
                take
            ] = dist2[
                take
            ]


            source_roi[
                take
            ] = i


            count_ok += 1


        except Exception as e:

            print(
                "[WARN]",
                path.name,
                e
            )

            count_fail += 1


    # ============================================================
    # 12. RECORTAR MARGENS VAZIAS
    # ============================================================

    covered = (
        source_map
        >=
        0
    )


    ys, xs = np.where(
        covered
    )


    if len(xs) == 0:

        raise RuntimeError(
            "O mosaico ficou vazio."
        )


    crop_x0 = int(
        xs.min()
    )

    crop_x1 = int(
        xs.max() + 1
    )

    crop_y0 = int(
        ys.min()
    )

    crop_y1 = int(
        ys.max() + 1
    )


    mosaic_crop = mosaic[
        crop_y0:crop_y1,
        crop_x0:crop_x1
    ]


    source_map_crop = source_map[
        crop_y0:crop_y1,
        crop_x0:crop_x1
    ]


    print()
    print(
        "Antes da rotação:",
        mosaic_crop.shape[1],
        "x",
        mosaic_crop.shape[0]
    )


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 35
    # ===========================================================================
    # ============================================================
    # 13. ROTAÇÃO AUTOMÁTICA PARA HORIZONTAL
    # ============================================================
    #
    # Para evitar definitivamente a ambiguidade de sinal:
    #
    # 1. calculamos o eixo principal;
    # 2. testamos +ângulo;
    # 3. testamos -ângulo;
    # 4. recalculamos o eixo em cada resultado;
    # 5. escolhemos automaticamente aquele mais próximo de 0°.


    # ============================================================
    # 13.1. ÂNGULO DO EIXO PRINCIPAL
    # ============================================================

    def principal_axis_angle(
        mask,
        max_points=PCA_MAX_POINTS
    ):
        """
        Ângulo do eixo principal da área coberta.

        Para evitar uma matriz gigantesca em mosaicos grandes,
        amostramos deterministicamente no máximo max_points pixels
        e calculamos a orientação diretamente pela covariância 2D.
        """

        ys, xs = np.nonzero(
            mask
        )


        n = len(
            xs
        )


        if n < 2:
            return 0.0


        if (
            max_points is not None
            and
            n > max_points
        ):

            step = int(
                math.ceil(
                    n
                    /
                    max_points
                )
            )

            xs = xs[
                ::step
            ]

            ys = ys[
                ::step
            ]


        x = xs.astype(
            np.float64
        )

        y = ys.astype(
            np.float64
        )


        x -= x.mean()
        y -= y.mean()


        cxx = float(
            np.mean(
                x * x
            )
        )

        cxy = float(
            np.mean(
                x * y
            )
        )

        cyy = float(
            np.mean(
                y * y
            )
        )


        angle = (
            0.5
            *
            math.degrees(
                math.atan2(
                    2.0 * cxy,
                    cxx - cyy
                )
            )
        )


        while angle > 90:
            angle -= 180


        while angle < -90:
            angle += 180


        return float(
            angle
        )


    # ============================================================
    # 13.2. ROTACIONAR RGB + SOURCE MAP
    # ============================================================

    def rotate_mosaic_candidate(
        rgb_image,
        source_map_array,
        angle_deg
    ):

        h, w = (
            rgb_image.shape[:2]
        )


        center = (
            w / 2.0,
            h / 2.0
        )


        M = cv2.getRotationMatrix2D(
            center,
            angle_deg,
            1.0
        )


        cos_a = abs(
            M[0, 0]
        )

        sin_a = abs(
            M[0, 1]
        )


        new_w = int(
            math.ceil(
                h * sin_a
                +
                w * cos_a
            )
        )


        new_h = int(
            math.ceil(
                h * cos_a
                +
                w * sin_a
            )
        )


        # centralizar no canvas novo

        M[
            0, 2
        ] += (
            new_w / 2.0
            -
            center[0]
        )


        M[
            1, 2
        ] += (
            new_h / 2.0
            -
            center[1]
        )


        # --------------------------------------------------------
        # RGB
        # --------------------------------------------------------

        rotated_rgb = cv2.warpAffine(

            rgb_image,

            M,

            (
                new_w,
                new_h
            ),

            flags=cv2.INTER_LINEAR,

            borderMode=cv2.BORDER_CONSTANT,

            borderValue=(
                0,
                0,
                0
            )

        )


        # --------------------------------------------------------
        # SOURCE MAP
        # --------------------------------------------------------
        #
        # Usamos float temporariamente porque OpenCV não trabalha
        # bem com CV_32S no warpAffine.
        #
        # INTER_NEAREST preserva os rótulos.

        rotated_source = cv2.warpAffine(

            source_map_array.astype(
                np.float32
            ),

            M,

            (
                new_w,
                new_h
            ),

            flags=cv2.INTER_NEAREST,

            borderMode=cv2.BORDER_CONSTANT,

            borderValue=-1.0

        )


        rotated_source = np.rint(
            rotated_source
        ).astype(
            np.int16
        )


        # --------------------------------------------------------
        # Recortar margem externa vazia
        # --------------------------------------------------------

        covered_rotated = (
            rotated_source
            >=
            0
        )


        ys, xs = np.where(
            covered_rotated
        )


        if len(xs) == 0:

            raise RuntimeError(
                "Mosaico vazio após rotação."
            )


        x0 = int(
            xs.min()
        )

        x1 = int(
            xs.max() + 1
        )

        y0 = int(
            ys.min()
        )

        y1 = int(
            ys.max() + 1
        )


        rotated_rgb = rotated_rgb[
            y0:y1,
            x0:x1
        ]


        rotated_source = rotated_source[
            y0:y1,
            x0:x1
        ]


        return (
            rotated_rgb,
            rotated_source
        )


    # ============================================================
    # 13.3. TESTAR OS DOIS SENTIDOS
    # ============================================================

    def rotate_to_horizontal(
        rgb_image,
        source_map_array
    ):

        initial_mask = (
            source_map_array
            >=
            0
        )


        initial_angle = principal_axis_angle(
            initial_mask
        )


        print()
        print("=" * 75)
        print("ROTAÇÃO AUTOMÁTICA")
        print("=" * 75)

        print()
        print(
            f"Eixo principal inicial: "
            f"{initial_angle:+.3f}°"
        )


        # --------------------------------------------------------
        # Se já estiver horizontal, não fazer nada
        # --------------------------------------------------------

        if abs(initial_angle) < HORIZONTAL_ANGLE_TOL_DEG:

            print(
                "Mosaico já está praticamente horizontal."
            )

            return (
                rgb_image,
                source_map_array,
                0.0,
                initial_angle
            )


        # --------------------------------------------------------
        # Candidato A
        # --------------------------------------------------------

        rgb_a, source_a = rotate_mosaic_candidate(

            rgb_image,
            source_map_array,
            initial_angle

        )


        residual_a = principal_axis_angle(
            source_a >= 0
        )


        # --------------------------------------------------------
        # Candidato B
        # --------------------------------------------------------

        rgb_b, source_b = rotate_mosaic_candidate(

            rgb_image,
            source_map_array,
            -initial_angle

        )


        residual_b = principal_axis_angle(
            source_b >= 0
        )


        print()
        print(
            f"Candidato A: "
            f"rotação={initial_angle:+.3f}° "
            f"-> residual={residual_a:+.3f}°"
        )


        print(
            f"Candidato B: "
            f"rotação={-initial_angle:+.3f}° "
            f"-> residual={residual_b:+.3f}°"
        )


        # --------------------------------------------------------
        # Escolher o resultado mais horizontal
        # --------------------------------------------------------

        if (
            abs(residual_a)
            <=
            abs(residual_b)
        ):

            print()
            print(
                "Escolhido: candidato A"
            )


            return (
                rgb_a,
                source_a,
                initial_angle,
                residual_a
            )


        else:

            print()
            print(
                "Escolhido: candidato B"
            )


            return (
                rgb_b,
                source_b,
                -initial_angle,
                residual_b
            )


    # ============================================================
    # 13.4. APLICAR ROTAÇÃO
    # ============================================================

    rotation_applied_deg = 0.0
    residual_angle_deg = principal_axis_angle(
        source_map_crop >= 0
    )


    if AUTO_ROTATE_OUTPUT_HORIZONTAL:

        (
            mosaic_crop,
            source_map_crop,
            rotation_applied_deg,
            residual_angle_deg

        ) = rotate_to_horizontal(

            mosaic_crop,
            source_map_crop

        )


    print()
    print(
        f"Rotação aplicada: "
        f"{rotation_applied_deg:+.3f}°"
    )

    print(
        f"Inclinação residual: "
        f"{residual_angle_deg:+.3f}°"
    )

    print(
        "Dimensão após rotação:",
        mosaic_crop.shape[1],
        "x",
        mosaic_crop.shape[0]
    )


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 37
    # ===========================================================================
    # ============================================================
    # 14. SALVAR MOSAICO
    # ============================================================

    output_mosaic = (
        OUTPUT_DIR
        /
        "mosaico.jpg"
    )


    Image.fromarray(
        mosaic_crop
    ).save(
        output_mosaic,
        quality=JPEG_QUALITY,
        optimize=True
    )


    # ============================================================
    # 15. SALVAR SOURCE MAP
    # ============================================================

    source_map_path = (
        OUTPUT_DIR
        /
        "mosaico_source_map.npy"
    )


    np.save(
        source_map_path,
        source_map_crop
    )


    # ============================================================
    # 16. TABELA DE CONTRIBUIÇÃO DAS FOTOS
    # ============================================================

    source_rows = []


    for i, row in gdf.iterrows():

        source_rows.append({

            "index":
                i,

            "filename":
                row["filename"],

            "component_id":
                component_of[i],

            "incluida_no_mosaico":
                i in valid_indices_for_mosaic,

            "pixels_no_mosaico":
                int(
                    np.sum(
                        source_map_crop
                        ==
                        i
                    )
                )

        })


    source_table = pd.DataFrame(
        source_rows
    )


    source_table_path = (
        OUTPUT_DIR
        /
        "mosaico_fontes.csv"
    )


    source_table.to_csv(
        source_table_path,
        index=False
    )


    # ============================================================
    # 17. SALVAR METADADOS DO OUTPUT
    # ============================================================

    output_info = {

        "n_fotos_total":
            int(
                len(gdf)
            ),

        "n_fotos_usadas":
            int(
                len(
                    valid_indices_for_mosaic
                )
            ),

        "indices_excluidos":
            excluded_indices,

        "native_px_per_m":
            float(
                native_px_per_m
            ),

        "effective_px_per_m":
            float(
                px_per_m
            ),

        "rotation_applied_deg":
            float(
                rotation_applied_deg
            ),

        "residual_axis_angle_deg":
            float(
                residual_angle_deg
            ),

        "output_width_px":
            int(
                mosaic_crop.shape[1]
            ),

        "output_height_px":
            int(
                mosaic_crop.shape[0]
            ),

        "default_height_prior_m":
            float(
                DEFAULT_HEIGHT_M
            ),

        "default_fov_prior_deg":
            float(
                DEFAULT_FOV_DIAG_DEG
            ),

        "learned_cm_per_px_median":
            float(
                final_pose_df[
                    "learned_cm_per_px"
                ].median()
            ),

        "prior_scale_ratio_median":
            float(
                final_pose_df[
                    "prior_scale_ratio"
                ].median()
            ),

        "learned_agl_offset_used":
            bool(
                learned_agl_offset_used
            ),

        "learned_agl_offset_m":
            float(
                learned_agl_offset_m
            ),

        "agl_offset_support_components":
            int(
                agl_support_components
            ),

        "global_scale_used":
            bool(
                global_scale_used
            ),

        "global_scale_correction":
            float(
                global_scale_correction
            ),

        "global_scale_support_components":
            int(
                n_support_components
            ),

        "global_scale_apply_to_all_components":
            bool(
                GLOBAL_SCALE_APPLY_TO_ALL_COMPONENTS
            ),

        "scale_edge_regularization_used":
            bool(
                USE_SCALE_EDGE_REGULARIZATION
            ),

        "scale_edges_accepted":
            int(
                scale_edges_df[
                    "accepted_as_scale_edge"
                ].sum()
            ),

        "scale_edges_between_components":
            int(
                scale_edges_df[
                    "used_between_components"
                ].sum()
            ),

        "scale_edge_components_adjusted":
            int(
                sum(
                    abs(
                        factor - 1.0
                    )
                    >
                    1e-9
                    for factor
                    in component_scale_edge_factor.values()
                )
            )

    }


    with open(
        OUTPUT_DIR
        /
        "mosaico_info.json",
        "w"
    ) as f:

        json.dump(
            output_info,
            f,
            indent=2
        )


    # ============================================================
    # 18. RESUMO
    # ============================================================

    print()
    print("=" * 75)
    print("MOSAICO FINAL CONCLUÍDO")
    print("=" * 75)

    print()
    print(
        "Mosaico:",
        output_mosaic
    )

    print(
        "Source map:",
        source_map_path
    )

    print(
        "Tabela:",
        source_table_path
    )

    print(
        "Metadados:",
        OUTPUT_DIR
        /
        "mosaico_info.json"
    )

    print()
    print(
        "Fotos processadas:",
        count_ok
    )

    print(
        "Falhas:",
        count_fail
    )

    print(
        "Fotos excluídas:",
        len(
            excluded_indices
        )
    )

    print()
    print(
        "Dimensão final:",
        mosaic_crop.shape[1],
        "x",
        mosaic_crop.shape[0]
    )


    # ===========================================================================
    # PIPELINE DERIVADO DO NOTEBOOK — CÉLULA 39
    # ===========================================================================
    preview_path = OUTPUT_DIR / "mosaico_preview.jpg"

    with Image.open(output_mosaic) as im:
        preview = im.copy()

        preview.thumbnail(
            (5000, 5000),
            Image.Resampling.LANCZOS
        )

        preview.save(
            preview_path,
            quality=90,
            optimize=True
        )

    print("Preview:", preview_path)


    boundary = np.zeros_like(
        source_map_crop,
        dtype=bool
    )

    boundary[:, 1:] |= (
        source_map_crop[:, 1:]
        != source_map_crop[:, :-1]
    )

    boundary[1:, :] |= (
        source_map_crop[1:, :]
        != source_map_crop[:-1, :]
    )

    valid_boundary = (
        boundary
        & (source_map_crop >= 0)
    )

    seam_preview = mosaic_crop.copy()
    seam_preview[valid_boundary] = 255

    seam_path = OUTPUT_DIR / "mosaico_costuras.jpg"

    Image.fromarray(
        seam_preview
    ).save(
        seam_path,
        quality=92,
        optimize=True
    )

    with Image.open(seam_path) as im:
        seam_small = im.copy()

        seam_small.thumbnail(
            (5000, 5000),
            Image.Resampling.LANCZOS
        )

    print("Mapa de costuras:", seam_path)



    print()
    print("=" * 75)
    print("CONCLUÍDO")
    print("=" * 75)

    print("Mosaico:", output_mosaic)
    print("Preview:", preview_path)
    print("Costuras:", seam_path)
    print("Source map:", source_map_path)
    print("Diretório:", OUTPUT_DIR)

    if not args.no_zip:

        result_zip = (
            OUTPUT_DIR.parent
            /
            f"{OUTPUT_DIR.name}.zip"
        )

        if result_zip.exists():
            result_zip.unlink()

        shutil.make_archive(
            str(
                result_zip.with_suffix("")
            ),
            "zip",
            OUTPUT_DIR
        )

        print("ZIP:", result_zip)


    if (
        _temp_extract_dir is not None
        and
        args.keep_extracted
    ):

        print(
            "Imagens extraídas mantidas em:",
            _temp_extract_dir
        )



if __name__ == "__main__":
    main()
