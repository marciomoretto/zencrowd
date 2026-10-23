"""Worker de Cloud Run Job para montar o mosaico DJI.

Layout no storage:
    <run>/manifest.json          {"mode": "render"|"prepare", "photos": [{"object", "key", "name"}], "cache_prefix"}
    <run>/input/*                (legado, sem manifest) imagens selecionadas pelo Rails
    <run>/output/mosaico.jpg     mosaico final gerado por este worker (so no modo render)
    <run>/status.json            {"status":"ok"} ou {"status":"error","error":"..."}
    <cache_prefix>/sift/*        SIFT por foto, reaproveitado entre execucoes
    <cache_prefix>/pairs/*       registro visual por par de fotos

No modo "prepare" (disparado enquanto as fotos ainda estao chegando) o motor so preenche o cache de SIFT e de
pares, para o render final reaproveitar quase tudo.
"""
import json
import os
import shutil
import subprocess
import tempfile
import traceback
import csv
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

START = time.monotonic()
DOWNLOAD_THREADS = 8
CACHE_THREADS = 16
STATUS_FILE = "status.json"
MANIFEST_FILE = "manifest.json"
INPUT_PREFIX = "input"
OUTPUT_PREFIX = "output"
MOSAIC_OUTPUT_NAME = "mosaico.jpg"
# Saidas extras para contar nas fotos originais (ver mosaico_dji.py, etapa 15.1).
PHOTOS_OUTPUT_NAME = "mosaico_fotos.json"
SOURCE_MAP_OUTPUT_NAME = "mosaico_fontes.png"
# O motor aloca ~9 bytes/pixel em arrays fixos (mosaico, distancia, fonte); 120M px
# cabe com folga nos 16 GiB do job e nos limites do ImageMagick.
DEFAULT_MAX_OUTPUT_PIXELS = 120_000_000


class GcsStore:
    def __init__(self, bucket_name, root):
        from google.cloud import storage

        self.bucket = storage.Client().bucket(bucket_name)
        self.root = root.strip("/")

    def _blob(self, name):
        return self.bucket.blob(f"{self.root}/{name}")

    def list_names(self, prefix):
        full_prefix = f"{self.root}/{prefix.strip('/')}/"
        return [blob.name.removeprefix(f"{self.root}/") for blob in self.bucket.list_blobs(prefix=full_prefix)]

    def download(self, name, destination):
        self._blob(name).download_to_filename(str(destination))

    def upload(self, source, name):
        self._blob(name).upload_from_filename(str(source))

    def write_json(self, name, payload):
        self._blob(name).upload_from_string(json.dumps(payload), content_type="application/json")

    def exists(self, name):
        return self._blob(name).exists()

    def read_json(self, name):
        return json.loads(self._blob(name).download_as_text())

    # Objetos fora do prefixo da execucao (fotos e cache), pelo nome completo no bucket.
    def list_objects(self, prefix):
        return [blob.name for blob in self.bucket.list_blobs(prefix=prefix)]

    def download_object(self, name, destination):
        self.bucket.blob(name).download_to_filename(str(destination))

    def upload_object(self, source, name):
        self.bucket.blob(name).upload_from_filename(str(source))


class LocalStore:
    """Permite testes locais do worker sem GCS: MOSAIC_LOCAL_DIR faz o papel do bucket e MOSAIC_RUN_PREFIX (opcional)
    o da pasta da execucao dentro dele."""

    def __init__(self, directory, run_prefix=""):
        self.bucket_root = Path(directory)
        self.root = self.bucket_root / run_prefix.strip("/") if run_prefix.strip("/") else self.bucket_root

    def list_names(self, prefix):
        base = self.root / prefix
        if not base.exists():
            return []

        return [str(path.relative_to(self.root)) for path in sorted(base.rglob("*")) if path.is_file()]

    def download(self, name, destination):
        shutil.copyfile(self.root / name, destination)

    def upload(self, source, name):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)

    def write_json(self, name, payload):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload))

    def exists(self, name):
        return (self.root / name).is_file()

    def read_json(self, name):
        return json.loads((self.root / name).read_text())

    def list_objects(self, prefix):
        base = self.bucket_root
        return [
            str(path.relative_to(base))
            for path in sorted(base.rglob("*"))
            if path.is_file() and str(path.relative_to(base)).startswith(prefix)
        ]

    def download_object(self, name, destination):
        shutil.copyfile(self.bucket_root / name, destination)

    def upload_object(self, source, name):
        target = self.bucket_root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)


def build_store():
    local_dir = os.environ.get("MOSAIC_LOCAL_DIR")
    if local_dir:
        return LocalStore(local_dir, os.environ.get("MOSAIC_RUN_PREFIX", ""))

    return GcsStore(os.environ["MOSAIC_BUCKET"], os.environ["MOSAIC_RUN_PREFIX"])


def log(message):
    print(f"[{time.monotonic() - START:7.1f}s] {message}", flush=True)


def download_inputs(store, input_dir):
    input_names = store.list_names(INPUT_PREFIX)
    if not input_names:
        raise RuntimeError("Nenhuma imagem encontrada no prefixo de entrada.")

    def download(item):
        index, name = item
        store.download(name, input_dir / f"{index:05d}_{Path(name).name}")

    with ThreadPoolExecutor(max_workers=DOWNLOAD_THREADS) as pool:
        list(pool.map(download, enumerate(input_names)))

    log(f"{len(input_names)} imagem(ns) baixada(s)")


def download_photos(store, photos, input_dir):
    """Baixa as fotos do manifest e devolve {nome local: chave da foto} para nomear o cache do motor."""
    if not photos:
        raise RuntimeError("Manifest sem fotos para montar o mosaico.")

    keys_by_filename = {}
    jobs = []
    for index, photo in enumerate(photos):
        local_name = f"{index:05d}_{Path(photo['name']).name}"
        keys_by_filename[local_name] = photo["key"]
        jobs.append((photo["object"], input_dir / local_name))

    with ThreadPoolExecutor(max_workers=DOWNLOAD_THREADS) as pool:
        list(pool.map(lambda job: store.download_object(*job), jobs))

    log(f"{len(photos)} imagem(ns) baixada(s)")
    return keys_by_filename


def cache_object_wanted(relative_name, keys):
    """So baixa o cache das fotos desta execucao: sift/<chave>__v.npz e pairs/<a>__<b>__v.json."""
    folder, _, filename = relative_name.partition("/")
    parts = filename.split("__")
    if folder == "sift":
        return len(parts) == 2 and parts[0] in keys
    if folder == "pairs":
        return len(parts) == 3 and parts[0] in keys and parts[1] in keys
    return False


def download_cache(store, cache_prefix, cache_dir, keys):
    prefix = f"{cache_prefix.strip('/')}/"
    names = [
        name
        for name in store.list_objects(prefix)
        if cache_object_wanted(name.removeprefix(prefix), keys)
    ]

    def download(name):
        target = cache_dir / name.removeprefix(prefix)
        target.parent.mkdir(parents=True, exist_ok=True)
        store.download_object(name, target)

    with ThreadPoolExecutor(max_workers=CACHE_THREADS) as pool:
        list(pool.map(download, names))

    log(f"cache: {len(names)} arquivo(s) baixado(s)")
    return {name.removeprefix(prefix) for name in names}


def upload_new_cache(store, cache_prefix, cache_dir, existing):
    new_files = [
        path
        for path in cache_dir.rglob("*")
        if path.is_file() and not path.name.startswith(".") and str(path.relative_to(cache_dir)) not in existing
    ]

    def upload(path):
        store.upload_object(path, f"{cache_prefix.strip('/')}/{path.relative_to(cache_dir)}")

    with ThreadPoolExecutor(max_workers=CACHE_THREADS) as pool:
        list(pool.map(upload, new_files))

    log(f"cache: {len(new_files)} arquivo(s) novo(s) enviado(s)")


def upload_photo_mapping(store, output_dir, photos):
    """Envia o mapa foto -> mosaico, identificando cada foto pelo objeto no bucket (e nao pelo nome local)."""
    mapping_path = output_dir / PHOTOS_OUTPUT_NAME
    source_map_path = output_dir / SOURCE_MAP_OUTPUT_NAME
    if not mapping_path.exists() or not source_map_path.exists():
        log("motor nao gerou o mapa foto -> mosaico; a contagem usara o proprio mosaico")
        return

    photos_by_local_name = {f"{index:05d}_{Path(photo['name']).name}": photo for index, photo in enumerate(photos)}
    mapping = json.loads(mapping_path.read_text(encoding="utf-8"))
    for entry in mapping["photos"]:
        photo = photos_by_local_name.get(entry["filename"]) or {}
        entry["key"] = photo.get("key")
        entry["object"] = photo.get("object")
        entry["name"] = photo.get("name")
    mapping_path.write_text(json.dumps(mapping), encoding="utf-8")

    store.upload(mapping_path, f"{OUTPUT_PREFIX}/{PHOTOS_OUTPUT_NAME}")
    store.upload(source_map_path, f"{OUTPUT_PREFIX}/{SOURCE_MAP_OUTPUT_NAME}")


def run_mosaic(input_dir, output_dir, extra_args=(), prepare_only=False):
    script_path = Path(__file__).with_name("mosaico_dji.py")
    if not script_path.exists():
        raise RuntimeError("Script mosaico_dji.py nao encontrado no worker.")

    base_command = [
        "python",
        "-u",
        str(script_path),
        str(input_dir),
        "--output-dir",
        str(output_dir),
        "--overwrite",
        "--no-zip",
        "--max-output-pixels",
        str(max_output_pixels()),
        *extra_args,
    ]

    # A saida do motor vai para o log do Cloud Run em tempo real; so o final e guardado para o erro.
    process = subprocess.Popen(
        base_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    tail = deque(maxlen=12)
    for line in process.stdout:
        line = line.rstrip()
        tail.append(line)
        log(f"motor: {line}")
    returncode = process.wait()

    if returncode != 0:
        raise RuntimeError(f"motor DJI falhou (codigo {returncode}): {chr(10).join(tail)[:1400]}")

    if prepare_only:
        return None

    output_file = output_dir / MOSAIC_OUTPUT_NAME
    if not output_file.exists() or output_file.stat().st_size <= 0:
        raise RuntimeError("motor DJI concluiu sem gerar mosaico valido.")

    problem = find_mosaic_problem(output_dir)
    if problem:
        raise RuntimeError(problem)

    return output_file


def max_output_pixels():
    raw_value = os.environ.get("MOSAIC_MAX_OUTPUT_PIXELS", "").strip()
    try:
        value = int(raw_value)
    except ValueError:
        return DEFAULT_MAX_OUTPUT_PIXELS

    return value if value > 0 else DEFAULT_MAX_OUTPUT_PIXELS


def find_mosaic_problem(output_dir):
    """Retorna a descricao do problema quando o mosaico nao combinou as fotos."""
    info_path = output_dir / "mosaico_info.json"
    sources_path = output_dir / "mosaico_fontes.csv"
    if not info_path.exists() or not sources_path.exists():
        return None

    try:
        info_payload = json.loads(info_path.read_text(encoding="utf-8"))
        total_images = int(info_payload.get("n_fotos_total", 0))
        used_images = int(info_payload.get("n_fotos_usadas", 0))

        contributing_sources = 0
        with sources_path.open("r", encoding="utf-8", newline="") as csv_file:
            reader = csv.DictReader(csv_file)
            for row in reader:
                pixels = int(row.get("pixels_no_mosaico", "0") or 0)
                if pixels > 0:
                    contributing_sources += 1

        if total_images > 1 and used_images > 1 and contributing_sources <= 1:
            return (
                "Mosaico invalido: apenas uma foto contribuiu para o resultado final "
                f"(total={total_images}, usadas={used_images}, contribuindo={contributing_sources}). "
                "As fotos provavelmente nao tem sobreposicao suficiente para serem combinadas."
            )
    except Exception:  # noqa: BLE001
        return None

    return None


def setup_imagemagick_policy(workdir):
    policy_dir = workdir / "imagemagick_policy"
    policy_dir.mkdir(parents=True, exist_ok=True)
    policy_xml = policy_dir / "policy.xml"
    policy_xml.write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<policymap>
  <policy domain="resource" name="width" value="120KP"/>
  <policy domain="resource" name="height" value="120KP"/>
  <policy domain="resource" name="area" value="35GP"/>
  <policy domain="resource" name="memory" value="14GiB"/>
  <policy domain="resource" name="map" value="14GiB"/>
  <policy domain="resource" name="disk" value="20GiB"/>
</policymap>
""",
        encoding="utf-8",
    )
    os.environ["MAGICK_CONFIGURE_PATH"] = str(policy_dir)


def main():
    store = build_store()
    workdir = Path(tempfile.mkdtemp(prefix="mosaic_render_"))

    try:
        input_dir = workdir / "input"
        output_dir = workdir / "output"
        cache_dir = workdir / "cache"
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        setup_imagemagick_policy(workdir)

        manifest = store.read_json(MANIFEST_FILE) if store.exists(MANIFEST_FILE) else None
        mode = (manifest or {}).get("mode", "render")
        cache_prefix = (manifest or {}).get("cache_prefix") or ""
        extra_args = []
        existing_cache = None

        if manifest:
            keys_by_filename = download_photos(store, manifest.get("photos") or [], input_dir)
            if cache_prefix:
                cache_dir.mkdir(parents=True, exist_ok=True)
                existing_cache = download_cache(store, cache_prefix, cache_dir, set(keys_by_filename.values()))
                keys_path = workdir / "cache_keys.json"
                keys_path.write_text(json.dumps(keys_by_filename))
                extra_args = ["--cache-dir", str(cache_dir), "--cache-keys", str(keys_path)]
        else:
            download_inputs(store, input_dir)

        if mode == "prepare":
            extra_args.append("--prepare-only")

        try:
            mosaic_file = run_mosaic(input_dir, output_dir, extra_args, prepare_only=(mode == "prepare"))
            log("motor concluido")
        finally:
            # O que o motor ja calculou fica valido mesmo se ele falhar depois.
            if existing_cache is not None:
                upload_new_cache(store, cache_prefix, cache_dir, existing_cache)

        if mosaic_file is not None:
            store.upload(mosaic_file, f"{OUTPUT_PREFIX}/{MOSAIC_OUTPUT_NAME}")
            if manifest:
                upload_photo_mapping(store, output_dir, manifest.get("photos") or [])
            log("mosaico enviado")

        store.write_json(STATUS_FILE, {"status": "ok", "mode": mode})
    except Exception as error:  # noqa: BLE001
        traceback.print_exc()
        store.write_json(STATUS_FILE, {"status": "error", "error": f"{type(error).__name__}: {error}"[:1200]})
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
