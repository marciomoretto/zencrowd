"""Worker do Cloud Run Job: roda o P2PNet nas janelas do mosaico atribuidas a esta task.

Layout no storage (bucket do GCS ou diretorio local em modo de teste):

    <run>/mosaic.<ext>                 mosaico em resolucao maxima (enviado pelo Rails)
    <run>/<round>/manifest.json        {"threshold", "device", "mosaic", "items": [{id, x, y, width, height}]}
    <run>/<round>/results/<id>.json    resultado de cada janela (escrito por este worker)

Cada task processa os itens cujo indice e congruente ao seu CLOUD_RUN_TASK_INDEX.
"""
import json
import os
import shutil
import sys
import tempfile
import traceback
from pathlib import Path

REPO = Path(os.environ.get("P2PNET_REPO", "/opt/p2pnet"))
sys.path.insert(0, str(REPO))

import pyvips  # noqa: E402
import torch  # noqa: E402

import p2pnet_infer as p2p  # noqa: E402

JPEG_QUALITY = 95
OOM_MARKERS = ("out of memory", "can't allocate memory", "cannot allocate memory", "defaultcpuallocator")


class GcsStore:
    def __init__(self, bucket_name, root):
        from google.cloud import storage

        self.bucket = storage.Client().bucket(bucket_name)
        self.root = root.strip("/")

    def _blob(self, name):
        return self.bucket.blob(f"{self.root}/{name}")

    def download(self, name, destination):
        self._blob(name).download_to_filename(str(destination))

    def read_json(self, name):
        return json.loads(self._blob(name).download_as_bytes())

    def write_json(self, name, payload):
        self._blob(name).upload_from_string(json.dumps(payload), content_type="application/json")

    def exists(self, name):
        return self._blob(name).exists()


class LocalStore:
    """Usado para testar o worker sem GCS (COUNT_LOCAL_DIR)."""

    def __init__(self, directory):
        self.root = Path(directory)

    def download(self, name, destination):
        shutil.copyfile(self.root / name, destination)

    def read_json(self, name):
        return json.loads((self.root / name).read_text())

    def write_json(self, name, payload):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload))

    def exists(self, name):
        return (self.root / name).exists()


def build_store():
    local_dir = os.environ.get("COUNT_LOCAL_DIR")
    if local_dir:
        return LocalStore(local_dir)

    return GcsStore(os.environ["COUNT_BUCKET"], os.environ["COUNT_RUN_PREFIX"])


def is_oom(error):
    if isinstance(error, MemoryError):
        return True

    message = str(error).lower()
    return any(marker in message for marker in OOM_MARKERS)


def process_item(model, device, threshold, mosaic_path, item, workdir):
    window_path = Path(workdir) / f"{item['id']}.jpg"

    try:
        image = pyvips.Image.new_from_file(str(mosaic_path), access="sequential")
        image.crop(item["x"], item["y"], item["width"], item["height"]).write_to_file(
            str(window_path), Q=JPEG_QUALITY
        )

        _raw, resized, tensor = p2p.preprocess_image(str(window_path))
        points, _count = p2p.infer(model, tensor, threshold, device)

        return {
            "id": item["id"],
            "status": "ok",
            "points": points.tolist(),
            "resized_width": resized.size[0],
            "resized_height": resized.size[1],
        }
    except (MemoryError, RuntimeError) as error:
        if is_oom(error):
            return {"id": item["id"], "status": "oom"}

        return {"id": item["id"], "status": "error", "error": str(error)[:500]}
    except Exception as error:  # noqa: BLE001
        traceback.print_exc()
        return {"id": item["id"], "status": "error", "error": f"{type(error).__name__}: {error}"[:500]}
    finally:
        window_path.unlink(missing_ok=True)


def main():
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", "0"))
    task_count = int(os.environ.get("CLOUD_RUN_TASK_COUNT", "1"))
    round_name = os.environ.get("COUNT_ROUND", "round-0")

    store = build_store()
    manifest = store.read_json(f"{round_name}/manifest.json")
    items = [item for index, item in enumerate(manifest["items"]) if index % task_count == task_index]
    if not items:
        print(f"task {task_index}/{task_count}: sem itens")
        return

    workdir = Path(tempfile.mkdtemp(prefix="count_"))
    try:
        mosaic_path = workdir / Path(manifest["mosaic"]).name
        store.download(manifest["mosaic"], mosaic_path)

        torch.set_num_threads(os.cpu_count() or 1)
        device = p2p.resolve_device(manifest.get("device", "cpu"))
        weight_path = os.environ.get("P2PNET_WEIGHT_PATH", str(REPO / "weights" / "SHTechA.pth"))
        model = p2p.load_model(weight_path, device, "vgg16_bn", 2, 2)

        threshold = float(manifest.get("threshold", 0.5))
        print(f"task {task_index}/{task_count}: {len(items)} janelas, device={device}", flush=True)

        for item in items:
            result_name = f"{round_name}/results/{item['id']}.json"
            if store.exists(result_name):
                continue

            result = process_item(model, device, threshold, mosaic_path, item, workdir)
            store.write_json(result_name, result)
            print(f"{item['id']}: {result['status']}", flush=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
