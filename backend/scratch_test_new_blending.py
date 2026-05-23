import os
import sys
import torch
import numpy as np
import cv2
from PIL import Image, ImageFilter

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ai.pipeline import VastraPipeline
from ultralytics import YOLO, FastSAM

def run_new_blending_test():
    print("--- STARTING NEW PERSPECTIVE BLENDING PROTOTYPE ---")
    
    bedroom_path = r"C:\Users\ADITHYA\.gemini\antigravity-ide\brain\6b2eb953-cd10-4c06-8097-d286d67ea180\bedroom_test_1779381364998.png"
    fabric_path = r"e:\E DRIVE\FLUTTER INTERN\vastra\frontend\assets\fabrics\floral.jpg"
    
    if not os.path.exists(bedroom_path):
        print(f"Error: Bedroom test image not found at {bedroom_path}")
        return False
    if not os.path.exists(fabric_path):
        print(f"Error: Fabric swatch not found at {fabric_path}")
        return False

    room_pil = Image.open(bedroom_path).convert("RGB")
    fabric_pil = Image.open(fabric_path).convert("RGB")
    
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")
    
    yolo = YOLO("yolov8n.pt")
    fastsam = FastSAM("FastSAM-s.pt")
    pipeline = VastraPipeline(yolo, fastsam, device=device)
    
    # Run the initial detection & segmentation stages of the pipeline to get real inputs
    print("Running scene analysis, detection and segmentation...")
    img_np = np.array(room_pil)
    scene_profile = pipeline._analyze_scene(img_np)
    bbox, point_prompt = pipeline._smart_detect(room_pil, "bedsheets", scene_profile)
    mask_np = pipeline._precise_segment(room_pil, bbox, point_prompt, "bedsheets", scene_profile)
    mask_np = pipeline._clean_mask(img_np, mask_np)
    depth_map = pipeline._estimate_midas_depth(img_np)
    
    print(f"Bbox: {bbox}")
    print(f"Mask coverage: {float(mask_np.sum()) / (255.0 * mask_np.size) * 100:.2f}%")
    
    # ─── RUN OUR NEW ALGORITHM PROTOTYPE ───
    print("Running new perspective mapping and print-free shading...")
    w, h = room_pil.size
    fabric_np = np.array(fabric_pil.convert("RGB"), dtype=np.uint8)
    fw, fh = fabric_np.shape[1], fabric_np.shape[0]
    
    # 1. Smooth the depth map heavily to eliminate high-frequency noise
    depth_smooth = cv2.GaussianBlur(depth_map.astype(np.float32), (51, 51), 0)
    
    # Normalize depth_smooth to [0.1, 1.0] to prevent zero division
    d_min, d_max = depth_smooth.min(), depth_smooth.max()
    if d_max > d_min:
        depth_norm = (depth_smooth - d_min) / (d_max - d_min)
    else:
        depth_norm = np.ones_like(depth_smooth)
        
    # Map normalized depth to local scale range [0.4, 1.2]
    local_scale = depth_norm * 0.8 + 0.4
    base_scale = 0.7 # category specific tuning
    
    # 2. Centered texture coordinates around the bounding box center (cx, cy)
    if bbox is not None:
        bx1, by1, bx2, by2 = bbox
        cx = (bx1 + bx2) / 2.0
        cy = (by1 + by2) / 2.0
    else:
        cx = w / 2.0
        cy = h / 2.0
        
    # Generate pixel grid coordinates
    x_indices, y_indices = np.meshgrid(np.arange(w), np.arange(h))
    dx = x_indices - cx
    dy = y_indices - cy
    
    # Map pixel coordinates to texture coordinates using smooth depth
    tile_ref = 256.0
    map_u = (dx / (local_scale * base_scale)) * (fw / tile_ref) + (fw / 2.0)
    map_v = (dy / (local_scale * base_scale)) * (fh / tile_ref) + (fh / 2.0)
    
    # Seamless tiling wrap
    map_u = map_u % fw
    map_v = map_v % fh
    
    # Remap fabric swatch to room space
    fabric_mapped = cv2.remap(
        fabric_np,
        map_u.astype(np.float32),
        map_v.astype(np.float32),
        interpolation=cv2.INTER_LANCZOS4,
        borderMode=cv2.BORDER_REPLICATE
    )
    
    # 3. Print-Free Joint Bilateral Lighting Shading Transfer
    room_gray = cv2.cvtColor(img_np, cv2.COLOR_RGB2GRAY)
    
    # Guided filter to erase fabric print patterns while keeping fold shapes
    # Using pipeline's existing guided filter method
    room_smooth_gray = pipeline._guided_filter(room_gray, room_gray, r=16, eps=0.06)
    
    # High-frequency wrinkle details (difference of original gray and smoothed gray)
    details = room_gray.astype(np.float32) - room_smooth_gray.astype(np.float32)
    
    # Compute reference base brightness of the fabric in the original image (within the mask)
    masked_pixels = room_smooth_gray[mask_np > 50]
    if len(masked_pixels) > 0:
        ref_brightness = np.percentile(masked_pixels, 75)
        ref_brightness = np.clip(ref_brightness, 80.0, 220.0)
    else:
        ref_brightness = 180.0
        
    # Shading factor
    shading_factor = room_smooth_gray / ref_brightness
    shading_factor = np.clip(shading_factor, 0.20, 1.40)
    
    # Apply shading factor to the mapped fabric
    blended = fabric_mapped.astype(np.float32) * shading_factor[:, :, np.newaxis]
    
    # Add high-frequency wrinkle/crease details back
    wrinkle_strength = 0.85
    blended = blended + details[:, :, np.newaxis] * wrinkle_strength
    
    # Clip to valid RGB range [0, 255]
    blended = np.clip(blended, 0, 255).astype(np.uint8)
    
    # 4. Composite final output with Gaussian blurred mask
    mask_pil = Image.fromarray(mask_np, mode="L")
    mask_pil_blurred = mask_pil.filter(ImageFilter.GaussianBlur(radius=1.8))
    
    final_fabric_pil = Image.fromarray(blended, "RGB")
    result_pil = Image.composite(final_fabric_pil, room_pil, mask_pil_blurred)
    
    output_path = "test_new_bedsheets.png"
    result_pil.save(output_path)
    print(f"SUCCESS: Generated image saved to {output_path}")
    return True

if __name__ == "__main__":
    success = run_new_blending_test()
    sys.exit(0 if success else 1)
