"""
Vastra FastAPI Backend - main.py
=================================

Interactive SAM3 Decoupled Architecture.

Endpoints:
  GET  /health          - liveness check
  POST /api/upload      - upload image -> run SAM2 encoder -> cache embedding -> return session_id
  POST /api/interact    - send points -> run SAM2 decoder -> return preview overlay PNG
  POST /api/render      - confirm mask + fabric texture -> run texture engine -> return final PNG
"""

import sys

# Reconfigure stdout/stderr to use UTF-8 to prevent charmap/CP1252 encoding errors on Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

import time
import uuid
import asyncio
import base64
import threading
from io import BytesIO
from typing import List, Optional
from pathlib import Path

import cv2
import numpy as np
import torch
import uvicorn
from PIL import Image
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from ai.segmentation import InteractiveSAMEngine
from ai.pipeline import TextureProjectionEngine
from ai.fabric_registry import resolve_texture
from ai.inpaint import InpaintService
from ai.depth import DepthEstimationService
from ai.utils import ensure_dirs, compress_image, pil_to_bytes, contour_dominance_filter, anti_fringe_dilate


# ── Device Detection ──────────────────────────────────────────────────────────
DEVICE = (
    "cuda"
    if torch.cuda.is_available()
    else (
        "mps"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
        else "cpu"
    )
)
print(f"[Vastra] Hardware device: {DEVICE}")


# ── Session Cache with TTL ────────────────────────────────────────────────────
SESSION_TTL_SECONDS = 600  # 10-minute expiration
_session_store: dict = {}
_session_lock = threading.Lock()


class SessionData(dict):
    """Stores cached data for a single upload session, supporting both attribute and dict-like access."""

    def __init__(
        self,
        session_id: str,
        image_np: np.ndarray,
        image_embedding: dict,
        original_size: tuple,
    ):
        super().__init__()
        self["session_id"] = session_id
        self["image_np"] = image_np
        self["image_embedding"] = image_embedding
        self["original_size"] = original_size
        self["created_at"] = time.time()
        self["last_mask"] = None
        self["last_logits"] = None
        self["depth_map"] = None

    @property
    def depth_map(self) -> Optional[np.ndarray]:
        return self.get("depth_map")

    @depth_map.setter
    def depth_map(self, value: Optional[np.ndarray]):
        self["depth_map"] = value

    @property
    def session_id(self) -> str:
        return self["session_id"]

    @property
    def image_np(self) -> np.ndarray:
        return self["image_np"]

    @image_np.setter
    def image_np(self, value: np.ndarray):
        self["image_np"] = value

    @property
    def image_embedding(self) -> dict:
        return self["image_embedding"]

    @property
    def original_size(self) -> tuple:
        return self["original_size"]

    @property
    def created_at(self) -> float:
        return self["created_at"]

    @property
    def last_mask(self) -> Optional[np.ndarray]:
        return self["last_mask"]

    @last_mask.setter
    def last_mask(self, value: Optional[np.ndarray]):
        self["last_mask"] = value

    @property
    def last_logits(self) -> Optional[np.ndarray]:
        return self.get("last_logits")

    @last_logits.setter
    def last_logits(self, value: Optional[np.ndarray]):
        self["last_logits"] = value

    def is_expired(self) -> bool:
        return (time.time() - self["created_at"]) > SESSION_TTL_SECONDS


def _get_session(session_id: str) -> SessionData:
    """Retrieve a session or raise 404."""
    with _session_lock:
        session = _session_store.get(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")
    if session.is_expired():
        with _session_lock:
            _session_store.pop(session_id, None)
        raise HTTPException(
            status_code=410, detail=f"Session '{session_id}' expired (TTL={SESSION_TTL_SECONDS}s)."
        )
    return session


def _cleanup_expired_sessions():
    """Remove all expired sessions from the cache."""
    with _session_lock:
        expired = [sid for sid, s in _session_store.items() if s.is_expired()]
        for sid in expired:
            del _session_store[sid]
    if expired:
        print(f"[Vastra] Cleaned up {len(expired)} expired session(s).")


# ── Lazy-loaded AI singletons ────────────────────────────────────────────────
_sam_engine: Optional[InteractiveSAMEngine] = None
_texture_engine: Optional[TextureProjectionEngine] = None


def get_sam_engine() -> InteractiveSAMEngine:
    global _sam_engine
    if _sam_engine is None:
        print("[Vastra] Initializing InteractiveSAMEngine...")
        _sam_engine = InteractiveSAMEngine(device=DEVICE)
    return _sam_engine


def get_texture_engine() -> TextureProjectionEngine:
    global _texture_engine
    if _texture_engine is None:
        print("[Vastra] Initializing TextureProjectionEngine...")
        _texture_engine = TextureProjectionEngine()
    return _texture_engine


_depth_service: Optional[DepthEstimationService] = None


def get_depth_service() -> DepthEstimationService:
    global _depth_service
    if _depth_service is None:
        print("[Vastra] Initializing DepthEstimationService...")
        _depth_service = DepthEstimationService(device=DEVICE)
    return _depth_service


# ── Pydantic Models ──────────────────────────────────────────────────────────

class PointPrompt(BaseModel):
    x: float = Field(..., ge=0.0, le=1.0, description="Normalized X coordinate [0.0, 1.0]")
    y: float = Field(..., ge=0.0, le=1.0, description="Normalized Y coordinate [0.0, 1.0]")
    label: int = Field(..., ge=0, le=1, description="1 = positive (foreground), 0 = negative (background)")


class InteractRequest(BaseModel):
    session_id: str
    product_category: str
    points: List[PointPrompt]


class RenderRequest(BaseModel):
    session_id: str
    confirmed_mask: Optional[str] = Field(None, description="Base64-encoded PNG of the confirmed binary mask")
    fabric_texture_id: str = Field(..., description="Filename (without extension) of the fabric texture in assets/fabrics/")
    fabric_image_base64: Optional[str] = Field(None, description="Base64-encoded custom fabric image bytes")
    product_category: Optional[str] = Field(None, description="Category of the product being rendered")
    refine_with_diffusion: bool = Field(False, description="Whether to refine the classically rendered result using a diffusion inpainting model (strength 0.15-0.25)")
    tile_scale: float = Field(1.0, description="Scale multiplier for the fabric tiling pattern")
    rotation: float = Field(0.0, description="Rotation angle in degrees for the fabric pattern")
    offset_x: float = Field(0.0, description="Horizontal shift of the fabric pattern (as fraction of tile width)")
    offset_y: float = Field(0.0, description="Vertical shift of the fabric pattern (as fraction of tile height)")


class UpdateMaskRequest(BaseModel):
    session_id: str
    mask_base64: str


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Vastra AI API",
    description="Interactive SAM3 decoupled architecture for AI-powered interior fabric visualization",
    version="3.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ensure_dirs(["uploads", "outputs", "assets/fabrics"])


@app.on_event("startup")
def startup_event():
    """Pre-load AI models and start the session cleanup background task."""
    print("[Vastra] Pre-loading AI models on startup...")
    get_sam_engine()
    get_texture_engine()
    get_depth_service()
    print("[Vastra] All models initialized. Ready to serve.")


async def _session_cleanup_loop():
    """Background coroutine that evicts expired sessions every 60 seconds."""
    while True:
        await asyncio.sleep(60)
        _cleanup_expired_sessions()


@app.on_event("startup")
async def start_cleanup_task():
    asyncio.create_task(_session_cleanup_loop())


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Liveness check."""
    active_sessions = len([s for s in _session_store.values() if not s.is_expired()])
    return {
        "status": "ok",
        "device": DEVICE,
        "version": "3.0.0",
        "active_sessions": active_sessions,
        "message": "Vastra Interactive SAM3 API is running",
    }


@app.post("/api/upload")
async def api_upload(room_image: UploadFile = File(...)):
    """
    Upload a room image -> Run SAM2 Image Encoder -> Cache embedding -> Return session_id.

    Accepts:
      - room_image: JPEG/PNG of the room (multipart file upload)

    Returns:
      - JSON: { session_id, image_width, image_height, message }

    The generated feature embedding is cached in-memory with a 10-minute TTL.
    """
    try:
        # Read and decode the uploaded image
        room_bytes = await room_image.read()
        room_pil = Image.open(BytesIO(room_bytes)).convert("RGB")

        # Compress to prevent OOM on large uploads
        room_pil = compress_image(room_pil, max_dimension=1280)
        room_np = np.array(room_pil)
        h, w = room_np.shape[:2]

        print(f"[Vastra] /api/upload - image={w}x{h}")

        # Save to uploads/ for debugging
        session_id = uuid.uuid4().hex[:12]
        upload_path = Path("uploads") / f"{session_id}.png"
        room_pil.save(str(upload_path), "PNG")

        # Run the SAM2 Image Encoder (expensive — runs once)
        engine = get_sam_engine()
        embedding = engine.predict_encoder(room_np)

        # Run the Depth Estimation (expensive — runs once)
        depth_service = get_depth_service()
        depth_map = depth_service.predict_depth(room_np)

        # Cache the session
        session = SessionData(
            session_id=session_id,
            image_np=room_np,
            image_embedding=embedding,
            original_size=(h, w),
        )
        session.depth_map = depth_map
        session.last_logits = None
        with _session_lock:
            _session_store[session_id] = session

        print(f"[Vastra] Session '{session_id}' created. TTL={SESSION_TTL_SECONDS}s.")

        return {
            "session_id": session_id,
            "image_width": w,
            "image_height": h,
            "message": "Image encoded successfully. Use /api/interact to segment.",
        }

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"[Vastra] Upload error:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/interact")
async def api_interact(request: InteractRequest):
    """
    Interactive segmentation pass.

    Receives session_id, product_category, and an array of point prompts.
    Fetches the cached embedding, runs the SAM2 Decoder, applies post-processing,
    and returns a high-res preview overlay as a PNG image.

    Points use normalized [0.0–1.0] floating-point coordinates:
      - label=1: positive tap (foreground)
      - label=0: negative refinement tap (background)

    Returns:
      - PNG image bytes (the preview overlay composited on the room image)
    """
    valid_categories = {"bedsheets", "curtains", "sofa_covers", "pillows", "carpets", "rugs"}
    if request.product_category not in valid_categories:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid product_category '{request.product_category}'. "
                   f"Must be one of: {sorted(valid_categories)}",
        )

    if not request.points:
        raise HTTPException(status_code=422, detail="At least one point is required.")

    try:
        session = _get_session(request.session_id)
        h, w = session.original_size

        print(
            f"[Vastra] /api/interact - session={request.session_id}, "
            f"category={request.product_category}, points={len(request.points)}"
        )

        # Convert pydantic models to dicts for the engine
        points = [{"x": p.x, "y": p.y, "label": p.label} for p in request.points]

        # Run SAM2 Decoder (fast - reuses cached embedding)
        engine = get_sam_engine()
        raw_mask, low_res_logits = engine.predict_decoder(
            image_embedding=session.image_embedding,
            points=points,
            image_size=(h, w),
            low_res_logits=session.last_logits,
        )

        # Store the low-res logits for stateful iterative refinement
        session.last_logits = low_res_logits

        # Post-processing: contour dominance filter + anti-fringe dilation
        clean_mask = contour_dominance_filter(raw_mask, points=points)
        
        # Anti-fringe dilation: 2px to cover original fabric rim peeking through mask boundary
        clean_mask = anti_fringe_dilate(clean_mask, dilate_px=2, blur_sigma=1.2)

        # Cache the latest mask on the session for potential /api/render or manual brush edits
        session.last_mask = clean_mask

        # Generate preview overlay using clean mask
        overlay_np = InteractiveSAMEngine.generate_preview_overlay(
            session.image_np, clean_mask
        )

        # Encode to PNG
        overlay_pil = Image.fromarray(overlay_np, "RGB")
        result_bytes = pil_to_bytes(overlay_pil, fmt="PNG")

        return Response(content=result_bytes, media_type="image/png")

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"[Vastra] Interact error:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/session/{session_id}/mask")
async def api_session_mask(session_id: str):
    """Retrieve the current binary mask of the session as a PNG image."""
    session = _get_session(session_id)
    if session.last_mask is None:
        raise HTTPException(status_code=400, detail="No mask has been generated yet.")
    
    mask_pil = Image.fromarray(session.last_mask, "L")
    buf = BytesIO()
    mask_pil.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")


@app.post("/api/session/mask")
async def api_update_mask(request: UpdateMaskRequest):
    """Update the session mask manually (manual brush edits) and return new preview overlay."""
    session = _get_session(request.session_id)
    try:
        mask_bytes = base64.b64decode(request.mask_base64)
        mask_pil = Image.open(BytesIO(mask_bytes)).convert("L")
        h, w = session.original_size
        
        mask_np = np.array(mask_pil.resize((w, h), Image.Resampling.NEAREST))
        _, mask_np = cv2.threshold(mask_np, 127, 255, cv2.THRESH_BINARY)
        
        # Apply morphological opening to keep manual drawing edges clean
        kernel = np.ones((3, 3), np.uint8)
        mask_np = cv2.morphologyEx(mask_np, cv2.MORPH_OPEN, kernel)
        
        # Apply anti-fringe dilation
        mask_np = anti_fringe_dilate(mask_np, dilate_px=1, blur_sigma=1.0)
        
        session.last_mask = mask_np
        
        # Generate new preview overlay
        overlay_np = InteractiveSAMEngine.generate_preview_overlay(
            session.image_np, mask_np
        )
        overlay_pil = Image.fromarray(overlay_np, "RGB")
        result_bytes = pil_to_bytes(overlay_pil, fmt="PNG")
        
        return Response(content=result_bytes, media_type="image/png")
    except Exception as e:
        import traceback
        print(f"[Vastra] Update mask error:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/render")
async def api_render(request: RenderRequest):
    """
    Final texture rendering pass.

    Receives session_id, a confirmed binary mask (base64 PNG), and a fabric_texture_id.
    Executes the full photorealistic texture projection engine and returns the final image.

    Returns:
      - PNG image bytes (the final photorealistic room image with replaced fabric)
    """
    try:
        session = _get_session(request.session_id)
        h, w = session.original_size

        print(
            f"[Vastra] /api/render - session={request.session_id}, "
            f"texture={request.fabric_texture_id}"
        )

        # ── Decode the confirmed mask from base64 PNG ────────────────────────
        if request.confirmed_mask:
            try:
                mask_bytes = base64.b64decode(request.confirmed_mask)
                mask_pil = Image.open(BytesIO(mask_bytes)).convert("L")
                mask_np = np.array(mask_pil.resize((w, h), Image.Resampling.NEAREST))
                _, mask_np = cv2.threshold(mask_np, 127, 255, cv2.THRESH_BINARY)
            except Exception as e:
                raise HTTPException(
                    status_code=422, detail=f"Invalid confirmed_mask: {e}"
                )
        else:
            if session.last_mask is None:
                raise HTTPException(
                    status_code=400,
                    detail="No mask has been generated for this session yet. Run /api/interact first."
                )
            mask_np = session.last_mask

        # Apply post-processing (smoothing and edge cleanup) strictly inside /api/render
        mask_np = contour_dominance_filter(mask_np)
        # 3px dilation to fully cover original fabric fringe at boundary
        mask_np = anti_fringe_dilate(mask_np, dilate_px=3, blur_sigma=1.5)

        # ── Load fabric texture ──────────────────────────────────────────────
        if request.fabric_image_base64:
            try:
                fabric_bytes = base64.b64decode(request.fabric_image_base64)
                fabric_pil = Image.open(BytesIO(fabric_bytes)).convert("RGB")
                fabric_pil = compress_image(fabric_pil, max_dimension=1024)
                fabric_np = np.array(fabric_pil)
            except Exception as e:
                raise HTTPException(
                    status_code=422, detail=f"Invalid fabric_image_base64: {e}"
                )
        else:
            fabric_path = _resolve_fabric_path(request.fabric_texture_id)
            if fabric_path is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Fabric texture '{request.fabric_texture_id}' not found in assets/fabrics/.",
                )
            fabric_pil = Image.open(fabric_path).convert("RGB")
            fabric_pil = compress_image(fabric_pil, max_dimension=1024)
            fabric_np = np.array(fabric_pil)

        print(f"[Vastra] Loaded fabric texture: shape={fabric_np.shape}")

        # ── Run the texture projection engine ────────────────────────────────
        engine = get_texture_engine()

        # Category from request or default
        category = request.product_category or "bedsheets"
        
        # Classical projection engine (pass session_id for deterministic tile offsets)
        result_np = engine.render(
            room_np=session.image_np,
            mask_np=mask_np,
            fabric_np=fabric_np,
            product_category=category,
            session_id=request.session_id,
            tile_scale=request.tile_scale,
            rotation=request.rotation,
            offset_x=request.offset_x,
            offset_y=request.offset_y,
            depth_map=session.depth_map,
        )

        # Hybrid diffusion refinement
        if request.refine_with_diffusion:
            print("[Vastra] /api/render - Executing hybrid diffusion refinement...")
            try:
                temp_dir = Path("uploads")
                temp_classical_path = temp_dir / f"{request.session_id}_classical_temp.png"
                temp_mask_path = temp_dir / f"{request.session_id}_mask_temp.png"
                temp_depth_path = temp_dir / f"{request.session_id}_depth_temp.png"
                temp_output_path = temp_dir / f"{request.session_id}_refined_temp.png"
                
                # Save classical render and mask to temporary files
                Image.fromarray(result_np, "RGB").save(str(temp_classical_path), "PNG")
                Image.fromarray(mask_np, "L").save(str(temp_mask_path), "PNG")
                
                # Save depth map (rescaled to 0-255 uint8) to temporary file
                if session.depth_map is not None:
                    depth_vis = (session.depth_map * 255).astype(np.uint8)
                    Image.fromarray(depth_vis, "L").save(str(temp_depth_path), "PNG")
                else:
                    # Fallback empty black image if depth is missing
                    Image.fromarray(np.zeros((h, w), dtype=np.uint8), "L").save(str(temp_depth_path), "PNG")
                
                # Load and run inpainting service at low strength
                inpainter = InpaintService()
                prompt = f"photorealistic {category.replace('_', ' ')}, matching fabric pattern, high quality folds and wrinkles, interior design"
                
                inpainter.run_inpaint(
                    image_path=str(temp_classical_path),
                    mask_path=str(temp_mask_path),
                    depth_path=str(temp_depth_path),
                    prompt=prompt,
                    output_path=str(temp_output_path),
                    strength=0.15
                )
                
                # Load refined result
                refined_pil = Image.open(str(temp_output_path)).convert("RGB")
                result_np = np.array(refined_pil)
                
                # Cleanup temp files
                for p in [temp_classical_path, temp_mask_path, temp_depth_path, temp_output_path]:
                    if p.exists():
                        p.unlink()
            except Exception as e:
                print(f"[Vastra] Diffusion refinement failed: {e}. Falling back to classical result.")

        # Encode to PNG
        result_pil = Image.fromarray(result_np, "RGB")
        result_bytes = pil_to_bytes(result_pil, fmt="PNG")

        # Also save to outputs/ for debugging
        output_path = Path("outputs") / f"{request.session_id}_render.png"
        result_pil.save(str(output_path), "PNG")

        return Response(content=result_bytes, media_type="image/png")

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"[Vastra] Render error:\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))


# ── Helpers ───────────────────────────────────────────────────────────────────

def _resolve_fabric_path(texture_id: str) -> Optional[str]:
    """
    Resolve a fabric_texture_id to an actual file path in assets/fabrics/
    by delegating to the fabric_registry module.
    """
    return resolve_texture(texture_id)


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
