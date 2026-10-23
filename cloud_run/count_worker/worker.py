"""Worker do Cloud Run Job: roda o P2PNet nas janelas atribuidas a esta task.

Layout no storage (bucket do GCS ou diretorio local em modo de teste):

    <run>/mosaic.<ext>                 mosaico em resolucao maxima (enviado pelo Rails), quando a contagem e no mosaico
    <run>/<round>/manifest.json        {"threshold", "device", "mosaic", "items": [{id, x, y, width, height, image?}]}
    <run>/<round>/results/<id>.json    resultado de cada janela (escrito por este worker)

Sem "image", a janela e recortada do mosaico e cada task pega os itens cujo indice e congruente ao seu
CLOUD_RUN_TASK_INDEX. Com "image" (objeto da foto original no bucket), a janela e recortada da foto e as fotos sao
divididas entre as tasks, para que cada uma baixe so as fotos que vai processar.
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

import numpy as np  # noqa: E402
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

    def download_object(self, name, destination):
        self.bucket.blob(name).download_to_filename(str(destination))


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

    def download_object(self, name, destination):
        shutil.copyfile(self.root / name, destination)


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


def items_for_task(items, task_index, task_count):
    if not any(item.get("image") for item in items):
        return [item for index, item in enumerate(items) if index % task_count == task_index]

    images = sorted({item["image"] for item in items})
    mine = {image for index, image in enumerate(images) if index % task_count == task_index}
    return sorted((item for item in items if item["image"] in mine), key=lambda item: item["image"])


class SourceImages:
    """Baixa cada foto uma unica vez e apaga a anterior ao trocar de foto (itens chegam agrupados por foto)."""

    def __init__(self, store, workdir, mosaic_name=None):
        self.store = store
        self.workdir = Path(workdir)
        self.mosaic_name = mosaic_name
        self.current = (None, None)

    def path_for(self, item):
        image = item.get("image")
        if image is None:
            name, path = self.mosaic_name, self.workdir / Path(self.mosaic_name).name
            if not path.exists():
                self.store.download(name, path)
            return path

        if self.current[0] != image:
            if self.current[1] is not None:
                self.current[1].unlink(missing_ok=True)
            path = self.workdir / f"source_{abs(hash(image))}{Path(image).suffix or '.jpg'}"
            self.store.download_object(image, path)
            self.current = (image, path)

        return self.current[1]


TEXTURE_HALF = 6  # janela 13x13 para o desvio-padrao do cinza
GREEN_HALF = 12  # janela 25x25 para a fracao de pixels verdes
GREEN_EXG = 0.08  # excesso de verde normalizado (2G - R - B) / (R + G + B) acima do qual o pixel conta como verde


def filter_points(image, points, min_texture, max_green_fraction):
    """Descarta deteccoes que nao parecem cabecas: superficie lisa (mar, areia) ou vizinhanca quase toda verde
    (copas de arvore, agua esverdeada). O P2PNet marca essas areas com score alto, entao o limiar nao resolve.
    Medido nas fotos do evento 25: remove ~86% dos falsos no mar e ~88% nas arvores e ~0,5% das cabecas."""
    if len(points) == 0 or (min_texture <= 0 and max_green_fraction <= 0):
        return points, 0

    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    gray = rgb.mean(axis=2)
    exg = (2 * rgb[..., 1] - rgb[..., 0] - rgb[..., 2]) / (rgb.sum(axis=2) + 1)
    green = exg > GREEN_EXG
    height, width = gray.shape

    keep = []
    for x, y in points:
        xi = int(min(max(round(x), 0), width - 1))
        yi = int(min(max(round(y), 0), height - 1))
        if min_texture > 0:
            patch = gray[max(yi - TEXTURE_HALF, 0):yi + TEXTURE_HALF + 1, max(xi - TEXTURE_HALF, 0):xi + TEXTURE_HALF + 1]
            if patch.std() < min_texture:
                keep.append(False)
                continue
        if max_green_fraction > 0:
            patch = green[max(yi - GREEN_HALF, 0):yi + GREEN_HALF + 1, max(xi - GREEN_HALF, 0):xi + GREEN_HALF + 1]
            if patch.mean() > max_green_fraction:
                keep.append(False)
                continue
        keep.append(True)

    keep = np.array(keep, dtype=bool)
    return points[keep], int((~keep).sum())


def process_item(model, device, threshold, mosaic_path, item, workdir, filters=None):
    window_path = Path(workdir) / f"{item['id']}.jpg"

    try:
        image = pyvips.Image.new_from_file(str(mosaic_path), access="sequential")
        image.crop(item["x"], item["y"], item["width"], item["height"]).write_to_file(
            str(window_path), Q=JPEG_QUALITY
        )

        _raw, resized, tensor = p2p.preprocess_image(str(window_path))
        points, _count = p2p.infer(model, tensor, threshold, device)
        filters = filters or {}
        points, discarded = filter_points(
            resized, points, float(filters.get("min_texture", 0)), float(filters.get("max_green_fraction", 0))
        )

        return {
            "id": item["id"],
            "status": "ok",
            "points": points.tolist(),
            "discarded": discarded,
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
    items = items_for_task(manifest["items"], task_index, task_count)
    if not items:
        print(f"task {task_index}/{task_count}: sem itens")
        return

    workdir = Path(tempfile.mkdtemp(prefix="count_"))
    try:
        sources = SourceImages(store, workdir, manifest.get("mosaic"))

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

            result = process_item(model, device, threshold, sources.path_for(item), item, workdir, manifest.get("filters"))
            store.write_json(result_name, result)
            print(f"{item['id']}: {result['status']}", flush=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
