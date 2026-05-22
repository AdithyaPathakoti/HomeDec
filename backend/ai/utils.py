from PIL import Image
import io
import os
import shutil
from pathlib import Path


def save_upload_file(upload_file, destination: Path) -> None:
    """Save a FastAPI UploadFile to a local path synchronously."""
    try:
        with open(destination, "wb") as f:
            shutil.copyfileobj(upload_file.file, f)
    finally:
        upload_file.file.seek(0)


def ensure_dirs(dirs) -> None:
    """Create directories if they do not exist."""
    for d in dirs:
        Path(d).mkdir(parents=True, exist_ok=True)


def load_image(path: str) -> Image.Image:
    """Open an image file as a PIL RGB image."""
    return Image.open(path).convert("RGB")


def compress_image(pil_image: Image.Image, max_dimension: int = 1920, quality: int = 85) -> Image.Image:
    """Resize image so its longest side is ≤ max_dimension, preserving aspect ratio."""
    w, h = pil_image.size
    if max(w, h) <= max_dimension:
        return pil_image
    if w >= h:
        new_w = max_dimension
        new_h = int(h * max_dimension / w)
    else:
        new_h = max_dimension
        new_w = int(w * max_dimension / h)
    return pil_image.resize((new_w, new_h), Image.Resampling.LANCZOS)


def pil_to_bytes(pil_image: Image.Image, fmt: str = "PNG") -> bytes:
    """Serialize a PIL image to raw bytes."""
    buf = io.BytesIO()
    pil_image.save(buf, format=fmt)
    buf.seek(0)
    return buf.getvalue()


def numpy_to_pil(arr, mode: str = "RGB") -> Image.Image:
    """Convert a numpy ndarray to a PIL Image."""
    import numpy as np
    return Image.fromarray(arr.astype(np.uint8), mode)
