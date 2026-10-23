"""Worker de Cloud Run Job para montar o mosaico DJI.

Layout no storage:
    <run>/input/*                imagens selecionadas pelo Rails
    <run>/output/mosaico.jpg     mosaico final gerado por este worker
    <run>/status.json            {"status":"ok"} ou {"status":"error","error":"..."}
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
STATUS_FILE = "status.json"
INPUT_PREFIX = "input"
OUTPUT_PREFIX = "output"
MOSAIC_OUTPUT_NAME = "mosaico.jpg"
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


class LocalStore:
    """Permite testes locais do worker sem GCS (MOSAIC_LOCAL_DIR)."""

    def __init__(self, directory):
        self.root = Path(directory)

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


def build_store():
    local_dir = os.environ.get("MOSAIC_LOCAL_DIR")
    if local_dir:
        return LocalStore(local_dir)

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


def run_mosaic(input_dir, output_dir):
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
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        setup_imagemagick_policy(workdir)

        download_inputs(store, input_dir)
        mosaic_file = run_mosaic(input_dir, output_dir)
        log("motor concluido")
        store.upload(mosaic_file, f"{OUTPUT_PREFIX}/{MOSAIC_OUTPUT_NAME}")
        store.write_json(STATUS_FILE, {"status": "ok"})
        log("mosaico enviado")
    except Exception as error:  # noqa: BLE001
        traceback.print_exc()
        store.write_json(STATUS_FILE, {"status": "error", "error": f"{type(error).__name__}: {error}"[:1200]})
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
