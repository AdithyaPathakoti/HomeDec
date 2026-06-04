"""
Vastra FastAPI Backend – main.py

Endpoints:
  GET  /health            – liveness check
  POST /vastra/generate   – full automatic fabric-redesign pipeline
"""

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import numpy as np
import uvicorn
import torch
from io import BytesIO

from ai.pipeline import VastraPipeline
from ai.utils import ensure_dirs, compress_image, pil_to_bytes

# ── Device ─────────────────────────────────────────────────────────────────────
DEVICE = (
    "cuda"
    if torch.cuda.is_available()
    else ("mps" if hasattr(torch.backends, "mps") and torch.backends.mps.is_available() else "cpu")
)
print(f"[Vastra] Hardware device: {DEVICE}")

# ── Lazy-loaded model singletons ───────────────────────────────────────────────
_yolo_model = None
_pipeline = None


def get_yolo():
    global _yolo_model
    if _yolo_model is None:
        from ultralytics import YOLO
        print("[Vastra] Loading YOLOv8n...")
        _yolo_model = YOLO("yolov8n.pt")
        print("[Vastra] YOLOv8n ready.")
    return _yolo_model


def get_pipeline():
    global _pipeline
    if _pipeline is None:
        print("[Vastra] Initializing VastraPipeline singleton...")
        _pipeline = VastraPipeline(yolo_model=get_yolo(), device=DEVICE)
    return _pipeline


# ── App ────────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Vastra AI API",
    description="AI-powered interior fabric visualizer backend",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ensure_dirs(["uploads", "outputs"])


@app.on_event("startup")
def startup_event():
    print("[Vastra] Pre-loading AI models on startup...")
    pipeline = get_pipeline()
    pipeline._get_fastsam()
    pipeline._load_depth_model()
    print("[Vastra] All models loaded. Ready to serve.")


# ── Endpoints ──────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "ok",
        "device": DEVICE,
        "message": "Vastra AI API is running",
    }


@app.post("/vastra/generate")
async def vastra_generate(
    room_image: UploadFile = File(...),
    fabric_image: UploadFile = File(...),
    product_category: str = Form(...),
):
    """
    Automatic fabric redesign pipeline.

    Accepts:
      - room_image      : JPEG/PNG of the room to redesign
      - fabric_image    : JPEG/PNG of the fabric swatch
      - product_category: one of bedsheets | curtains | sofa_covers | pillows | carpets

    Returns:
      - PNG bytes of the redesigned room image (raw binary response)
    """
    valid_categories = {"bedsheets", "curtains", "sofa_covers", "pillows", "carpets"}
    if product_category not in valid_categories:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid product_category '{product_category}'. "
                   f"Must be one of: {sorted(valid_categories)}",
        )

    try:
        # Read uploaded images
        room_bytes = await room_image.read()
        fabric_bytes = await fabric_image.read()

        room_pil = Image.open(BytesIO(room_bytes)).convert("RGB")
        fabric_pil = Image.open(BytesIO(fabric_bytes)).convert("RGB")

        # Compress to prevent OOM on large uploads
        room_pil = compress_image(room_pil, max_dimension=1280)
        fabric_pil = compress_image(fabric_pil, max_dimension=512)

        print(
            f"[Vastra] /vastra/generate – category={product_category}, "
            f"room={room_pil.size}, fabric={fabric_pil.size}"
        )

        # Run the pipeline
        pipeline = get_pipeline()
        result_pil = pipeline.process(room_pil, product_category, fabric_pil)

        # Serialize result as PNG bytes
        result_bytes = pil_to_bytes(result_pil, fmt="PNG")

        return Response(content=result_bytes, media_type="image/png")

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"[Vastra] Pipeline error:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
