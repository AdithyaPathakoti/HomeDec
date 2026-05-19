import shutil
from pathlib import Path
from fastapi import UploadFile
from PIL import Image

def ensure_dirs(dirs):
    for d in dirs:
        Path(d).mkdir(parents=True, exist_ok=True)

def save_upload_file(upload_file: UploadFile, destination: Path):
    try:
        with destination.open("wb") as buffer:
            shutil.copyfileobj(upload_file.file, buffer)
    finally:
        upload_file.file.close()

def load_image(image_path: str) -> Image.Image:
    img = Image.open(image_path).convert("RGB")
    return img

def resize_image(image: Image.Image, size=(512, 512)) -> Image.Image:
    return image.resize(size, Image.Resampling.LANCZOS)
