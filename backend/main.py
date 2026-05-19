from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Response
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import numpy as np
import uvicorn
import os
import uuid
import shutil
from pathlib import Path
from dotenv import load_dotenv
from gradio_client import Client, handle_file
import tempfile
import torch

# Determine best available device for blazing fast inference
DEVICE = "cuda" if torch.cuda.is_available() else ("mps" if hasattr(torch.backends, "mps") and torch.backends.mps.is_available() else "cpu")
print(f"Hardware Acceleration Device: {DEVICE}")

# Load environment variables from .env file
load_dotenv()

# Lazy-loaded models
yolo_model = None
fastsam_model = None

def get_yolo_model():
    global yolo_model
    if yolo_model is None:
        from ultralytics import YOLO
        yolo_model = YOLO("yolov8n.pt")
    return yolo_model

def get_fastsam_model():
    global fastsam_model
    if fastsam_model is None:
        from ultralytics import FastSAM
        fastsam_model = FastSAM("FastSAM-s.pt")
    return fastsam_model

from ai.inpaint import InpaintService
from ai.utils import save_upload_file, ensure_dirs

app = FastAPI(title="FabricFlow AI API")

@app.on_event("startup")
def startup_event():
    print("Pre-loading local AI models for blazing-fast inference...")
    get_yolo_model()
    get_fastsam_model()
    print("Local AI models loaded successfully!")

# Allow CORS for local dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path("uploads")
OUTPUT_DIR = Path("outputs")
ensure_dirs([UPLOAD_DIR, OUTPUT_DIR])

inpaint_service = InpaintService()

@app.get("/")
def read_root():
    return {"status": "ok", "message": "FabricFlow AI API is running"}

@app.post("/generate")
async def generate_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    prompt: str = Form(...),
    design: UploadFile = File(None)
):
    try:
        # Generate unique IDs for this request
        request_id = str(uuid.uuid4())
        
        orig_img_path = UPLOAD_DIR / f"{request_id}_orig.png"
        mask_img_path = UPLOAD_DIR / f"{request_id}_mask.png"
        output_img_path = OUTPUT_DIR / f"{request_id}_output.png"
        
        # Save uploaded files
        save_upload_file(image, orig_img_path)
        save_upload_file(mask, mask_img_path)
        
        # Check if custom design file is provided
        if design and design.filename:
            design_img_path = UPLOAD_DIR / f"{request_id}_design.png"
            save_upload_file(design, design_img_path)
            
            print(f"Starting offline pattern blending for {request_id} with design: {design.filename}")
            output_path = inpaint_service.run_pattern_blend(
                image_path=str(orig_img_path),
                mask_path=str(mask_img_path),
                pattern_path=str(design_img_path),
                output_path=str(output_img_path)
            )
        else:
            # Run cloud AI inpainting
            print(f"Starting cloud AI inpainting for {request_id} with prompt: {prompt}")
            output_path = inpaint_service.run_inpaint(
                image_path=str(orig_img_path),
                mask_path=str(mask_img_path),
                prompt=prompt,
                output_path=str(output_img_path)
            )
        
        return {"status": "success", "request_id": request_id, "message": "Image generated successfully"}
        
    except Exception as e:
        print(f"Error generating image: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/result/{request_id}")
async def get_result(request_id: str):
    file_path = OUTPUT_DIR / f"{request_id}_output.png"
    if file_path.exists():
        return FileResponse(file_path, media_type="image/png")
    raise HTTPException(status_code=404, detail="Result not found")

def numpy_flood_fill(image: Image.Image, seed_point: tuple, tolerance: int = 40) -> Image.Image:
    # 1. Downsample for blazing-fast computation & natural noise reduction
    orig_size = image.size
    calc_size = (384, 384)
    img_low = image.resize(calc_size, Image.Resampling.BILINEAR)
    
    img_arr = np.array(img_low.convert("RGB"))
    h, w, c = img_arr.shape
    
    # 2. Extract relative tapped seed point
    sx_pct, sy_pct = seed_point
    sx = int(sx_pct * w)
    sy = int(sy_pct * h)
    
    sx = max(0, min(sx, w - 1))
    sy = max(0, min(sy, h - 1))
    
    target_color = img_arr[sy, sx].astype(np.int32)
    
    # 3. Compute L1 color distance map
    color_diff = np.abs(img_arr.astype(np.int32) - target_color)
    l1_dist = np.sum(color_diff, axis=2)
    matching_pixels = l1_dist <= tolerance
    
    # 4. Standard iterative BFS flood fill
    from collections import deque
    queue = deque([(sy, sx)])
    mask = np.zeros((h, w), dtype=np.uint8)
    mask[sy, sx] = 2
    
    filled_mask = np.zeros((h, w), dtype=np.uint8)
    
    dx = [0, 0, 1, -1]
    dy = [1, -1, 0, 0]
    
    while queue:
        cy, cx = queue.popleft()
        filled_mask[cy, cx] = 255
        
        for i in range(4):
            ny, nx = cy + dy[i], cx + dx[i]
            if 0 <= ny < h and 0 <= nx < w:
                if mask[ny, nx] == 0 and matching_pixels[ny, nx]:
                    mask[ny, nx] = 2
                    queue.append((ny, nx))
                    
    # 5. Convert to PIL image
    mask_img = Image.fromarray(filled_mask, "L")
    
    # 6. Resize back to original size with Bilinear interpolation for smooth, anti-aliased edges
    mask_hd = mask_img.resize(orig_size, Image.Resampling.BILINEAR)
    
    # 7. Apply a clean high-pass threshold
    mask_hd = mask_hd.point(lambda p: 255 if p > 128 else 0)
    
    return mask_hd

@app.post("/detect_objects")
async def detect_objects(image: UploadFile = File(...)):
    try:
        from io import BytesIO
        image_content = await image.read()
        pil_image = Image.open(BytesIO(image_content)).convert("RGB")
        
        # Load YOLOv8 model
        model = get_yolo_model()
        
        # Run prediction
        # Classes of interest: 56 (chair), 57 (couch/sofa), 59 (bed), 60 (dining table)
        classes_of_interest = [56, 57, 59, 60]
        # Lowered confidence from 0.25 to 0.15 to ensure beds/bedsheets are easily identified
        results = model.predict(pil_image, classes=classes_of_interest, conf=0.15, device=DEVICE, imgsz=640)
        
        detected_objects = []
        if results and len(results) > 0:
            result = results[0]
            boxes = result.boxes
            w, h = pil_image.size
            for box in boxes:
                # Get class id and label
                cls_id = int(box.cls[0].item())
                label = result.names[cls_id]
                conf = float(box.conf[0].item())
                
                # Get xyxy coordinates (absolute pixels)
                xyxy = box.xyxy[0].tolist()
                x1, y1, x2, y2 = xyxy
                
                # Normalize coordinates to [0.0, 1.0] relative to image dimensions
                x1_pct = max(0.0, min(1.0, x1 / w))
                y1_pct = max(0.0, min(1.0, y1 / h))
                x2_pct = max(0.0, min(1.0, x2 / w))
                y2_pct = max(0.0, min(1.0, y2 / h))
                
                detected_objects.append({
                    "label": label,
                    "confidence": conf,
                    "box": [x1_pct, y1_pct, x2_pct, y2_pct]
                })
        
        return {"status": "success", "objects": detected_objects}
        
    except Exception as e:
        print(f"Error detecting objects: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/auto_mask")
async def auto_mask(
    image: UploadFile = File(...),
    x_pct: float = Form(0.0),
    y_pct: float = Form(0.0),
    tolerance: int = Form(40),
    box: str = Form(None)
):
    try:
        from io import BytesIO
        
        # Read image file contents
        image_content = await image.read()
        pil_image = Image.open(BytesIO(image_content)).convert("RGB")
        
        # Attempt local FastSAM mask extraction first
        try:
            print(f"Requesting local FastSAM mask extraction. Tap: ({x_pct:.2f}, {y_pct:.2f}), Box: {box}, tolerance {tolerance}")
            
            model = get_fastsam_model()
            w, h = pil_image.size
            
            if box:
                # Box format: "x1,y1,x2,y2"
                coords = [float(c) for c in box.split(",")]
                x1 = coords[0] * w
                y1 = coords[1] * h
                x2 = coords[2] * w
                y2 = coords[3] * h
                
                print(f"Running FastSAM box prompt: [{x1:.1f}, {y1:.1f}, {x2:.1f}, {y2:.1f}]")
                results = model.predict(pil_image, bboxes=[[x1, y1, x2, y2]], conf=0.15, device=DEVICE, imgsz=640)
            else:
                cx = int(x_pct * w)
                cy = int(y_pct * h)
                
                print(f"Running FastSAM point prompt. Tap: ({cx}, {cy})")
                # Exclusively using point prompt instead of a restrictive dynamic box ensures the full bedsheet is identified, while running fast.
                results = model.predict(
                    pil_image, 
                    points=[[cx, cy]], 
                    labels=[1], 
                    conf=0.15, 
                    device=DEVICE,
                    imgsz=640
                )
                
            if results and len(results) > 0 and hasattr(results[0], "masks") and results[0].masks is not None and len(results[0].masks) > 0:
                print(f"FastSAM found {len(results[0].masks)} mask candidate(s).")
                mask_data = results[0].masks.data[0].cpu().numpy()
                mask_arr = (mask_data * 255).astype(np.uint8)
                mask_img = Image.fromarray(mask_arr, mode="L")
                
                # Resize back to original size with Bilinear interpolation
                mask_hd = mask_img.resize(pil_image.size, Image.Resampling.BILINEAR)
                
                # Apply high-pass threshold to clean noise
                mask_hd = mask_hd.point(lambda p: 255 if p > 120 else 0)
                
                # Soft feathering of the boundary edges (radius of 3px is perfect for premium, natural transitions)
                from PIL import ImageFilter
                mask_hd = mask_hd.filter(ImageFilter.GaussianBlur(radius=3))
                
                print("FastSAM soft feathered mask generated and resized successfully.")
            else:
                print("FastSAM found no masks. Falling back to local flood fill.")
                mask_hd = numpy_flood_fill(pil_image, (x_pct, y_pct), tolerance)
                
        except Exception as e:
            print(f"Local FastSAM extraction failed ({e}). Falling back to flood fill.")
            mask_hd = numpy_flood_fill(pil_image, (x_pct, y_pct), tolerance)
        
        # Save mask image to PNG bytes
        out_buffer = BytesIO()
        mask_hd.save(out_buffer, format="PNG")
        out_buffer.seek(0)
        
        return Response(content=out_buffer.getvalue(), media_type="image/png")
        
    except Exception as e:
        print(f"Error generating auto-mask: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
