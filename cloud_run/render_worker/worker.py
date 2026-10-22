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
from pathlib import Path

STATUS_FILE = "status.json"
INPUT_PREFIX = "input"
OUTPUT_PREFIX = "output"
MOSAIC_OUTPUT_NAME = "mosaico.jpg"


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


def download_inputs(store, input_dir):
    input_names = store.list_names(INPUT_PREFIX)
    if not input_names:
        raise RuntimeError("Nenhuma imagem encontrada no prefixo de entrada.")

    for index, name in enumerate(input_names):
        target_name = f"{index:05d}_{Path(name).name}"
        store.download(name, input_dir / target_name)


def run_mosaic(input_dir, output_dir):
    script_path = Path(__file__).with_name("mosaico_dji.py")
    if not script_path.exists():
        raise RuntimeError("Script mosaico_dji.py nao encontrado no worker.")

    command = [
        "python",
        str(script_path),
        str(input_dir),
        "--output-dir",
        str(output_dir),
        "--overwrite",
        "--no-zip",
    ]

    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout or "sem detalhes").strip()
        tail = "\n".join(details.splitlines()[-10:])
        raise RuntimeError(f"motor DJI falhou (codigo {completed.returncode}): {tail[:1200]}")

    output_file = output_dir / MOSAIC_OUTPUT_NAME
    if not output_file.exists() or output_file.stat().st_size <= 0:
        raise RuntimeError("motor DJI concluiu sem gerar mosaico valido.")

    return output_file


def main():
    store = build_store()
    workdir = Path(tempfile.mkdtemp(prefix="mosaic_render_"))

    try:
        input_dir = workdir / "input"
        output_dir = workdir / "output"
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        download_inputs(store, input_dir)
        mosaic_file = run_mosaic(input_dir, output_dir)
        store.upload(mosaic_file, f"{OUTPUT_PREFIX}/{MOSAIC_OUTPUT_NAME}")
        store.write_json(STATUS_FILE, {"status": "ok"})
    except Exception as error:  # noqa: BLE001
        traceback.print_exc()
        store.write_json(STATUS_FILE, {"status": "error", "error": f"{type(error).__name__}: {error}"[:1200]})
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
