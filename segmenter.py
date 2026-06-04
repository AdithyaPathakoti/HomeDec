#!/usr/bin/env python3
"""
Object Segmentation Script using LangSAM (Language Segment Anything)
Accepts a target item prompt and an image path, and outputs:
- A raw binary mask (mask.png)
- A visual overlay image (overlay.png) with a bright green highlight and outline to verify edge accuracy.
"""

import argparse
import os
import sys
import numpy as np
import cv2
import torch
from PIL import Image

def get_args():
    parser = argparse.ArgumentParser(
        description="Segment an object in an image using natural language prompts."
    )
    parser.add_argument(
        "--image", 
        type=str, 
        required=True, 
        help="Path to the input image file."
    )
    parser.add_argument(
        "--prompt", 
        type=str, 
        default="the comforter blanket . the pillows . the floor rug", 
        help="Target item string to segment (default: 'the comforter blanket . the pillows . the floor rug')."
    )
    parser.add_argument(
        "--output-mask", 
        type=str, 
        default="mask.png", 
        help="Path to save the output raw binary mask (default: mask.png)."
    )
    parser.add_argument(
        "--output-overlay", 
        type=str, 
        default="overlay.png", 
        help="Path to save the output visual overlay (default: overlay.png)."
    )
    parser.add_argument(
        "--box-threshold", 
        type=float, 
        default=0.20, 
        help="Box threshold for GroundingDINO detection (default: 0.20)."
    )
    parser.add_argument(
        "--text-threshold", 
        type=float, 
        default=0.23, 
        help="Text threshold for GroundingDINO detection (default: 0.23)."
    )
    parser.add_argument(
        "--alpha", 
        type=float, 
        default=0.35, 
        help="Opacity value (0.0 to 1.0) of the bright green highlight overlay (default: 0.35)."
    )
    parser.add_argument(
        "--device", 
        type=str, 
        default="cpu", 
        help="Hardware device to run inference on (default: cpu)."
    )
    return parser.parse_args()

def generate_precise_mask(masks_np):
    """
    Combines multiple masks, fuses waffle-weave grid dither and shadow gaps using a 45x45 Morphological Close,
    fills the interior completely via outermost contour-filling, and applies a slight Gaussian blur (5x5).
    """
    # 1. Combine all masks using logical OR
    if len(masks_np.shape) == 3:
        combined_mask_bool = np.any(masks_np, axis=0)
        mask_np = combined_mask_bool.astype(np.uint8) * 255
    else:
        mask_np = (masks_np > 0).astype(np.uint8) * 255
        
    # 2. Create a large 45x45 rectangular kernel to melt the waffle-weave texture grid
    melt_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (45, 45))
    
    # 3. Apply morphological closing directly to obliterate waffle grid lines and shadow gaps
    fused_mask = cv2.morphologyEx(mask_np, cv2.MORPH_CLOSE, melt_kernel)
    
    # 4. Extract outermost edge contours from the fused mask
    contours, _ = cv2.findContours(fused_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    # 5. Create a blank black canvas and draw filled contours to ensure 100% solidity
    filled_mask = np.zeros_like(mask_np)
    cv2.drawContours(filled_mask, contours, -1, 255, cv2.FILLED)
    
    # 6. Gaussian Blur (5x5 kernel) to smooth edges
    smoothed_mask = cv2.GaussianBlur(filled_mask, (5, 5), 0)
    
    # Threshold again to keep it a clean binary mask after Gaussian blur
    _, final_mask = cv2.threshold(smoothed_mask, 127, 255, cv2.THRESH_BINARY)
    
    return final_mask

def create_visual_overlay(image_pil, mask_np, alpha=0.35, highlight_color=(0, 255, 0), outline_thickness=2):
    """
    Creates a visual overlay where the segmented object is highlighted with a 
    translucent bright green color, and its boundaries are outlined with a solid green line.
    """
    # Ensure input PIL image is in RGB format and convert to NumPy array
    img_np = np.array(image_pil.convert("RGB"))
    
    # Create the translucent highlight
    overlay = img_np.copy()
    overlay[mask_np > 0] = highlight_color
    
    # Blend the overlay with the original image
    blended = cv2.addWeighted(overlay, alpha, img_np, 1.0 - alpha, 0)
    
    # Find and draw contours for perfect edge-accuracy verification
    # RETR_EXTERNAL gets outer boundaries; CHAIN_APPROX_SIMPLE compresses horizontal/vertical/diagonal segments
    contours, _ = cv2.findContours(mask_np, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(blended, contours, -1, highlight_color, outline_thickness)
    
    return Image.fromarray(blended)

def main():
    args = get_args()
    
    # 1. Input Validation
    if not os.path.exists(args.image):
        print(f"Error: Input image file '{args.image}' does not exist.")
        sys.exit(1)
        
    print(f"Loading image from '{args.image}'...")
    try:
        image_pil = Image.open(args.image).convert("RGB")
    except Exception as e:
        print(f"Error: Failed to open image. Details: {e}")
        sys.exit(1)
        
    # 2. Loading LangSAM Model
    print(f"Initializing LangSAM model on device: {args.device}...")
    try:
        # Import LangSAM inside main to avoid delay when checking help/args
        from lang_sam import LangSAM
        
        # Initialize model. It will auto-download weights on first run.
        model = LangSAM(device=args.device)
    except Exception as e:
        print(f"Error: Failed to initialize LangSAM model. Details: {e}")
        sys.exit(1)
        
    # 3. Model Inference
    print(f"Running LangSAM segmentation with prompt: '{args.prompt}'...")
    print(f"Settings -> Box Threshold: {args.box_threshold}, Text Threshold: {args.text_threshold}")
    try:
        results = model.predict(
            [image_pil], 
            [args.prompt], 
            box_threshold=args.box_threshold, 
            text_threshold=args.text_threshold
        )
        result = results[0]
        masks = result["masks"]
        boxes = result["boxes"]
        phrases = result["labels"]
        logits = result["scores"]
    except Exception as e:
        import traceback
        print(f"Error: Inference failed. Details: {e}")
        print(traceback.format_exc())
        sys.exit(1)
        
    # 4. Processing Predictions
    h, w = image_pil.size[1], image_pil.size[0]
    combined_mask_np = np.zeros((h, w), dtype=np.uint8)
    
    if masks is None or len(masks) == 0:
        print(f"Warning: No objects matching '{args.prompt}' were detected.")
        print("Outputs will consist of a black mask and the original image.")
    else:
        # Convert PyTorch tensor/lists to NumPy
        if hasattr(masks, "cpu"):
            masks_np = masks.cpu().numpy()
        else:
            masks_np = np.array(masks)
            
        print(f"Detected {len(masks_np)} instance(s) matching '{args.prompt}'.")
        for idx, (phrase, logit) in enumerate(zip(phrases, logits)):
            print(f"  - Instance #{idx+1}: '{phrase}' (Confidence: {logit:.3f})")
            
        # Select ONLY predictions that correspond to 'the comforter blanket'
        selected_indices = []
        for idx, phrase in enumerate(phrases):
            phrase_lower = phrase.lower()
            if "comforter" in phrase_lower or "blanket" in phrase_lower:
                selected_indices.append(idx)
                
        if len(selected_indices) == 0:
            print("Warning: 'the comforter blanket' was not isolated in any predictions.")
            combined_mask_np = np.zeros((h, w), dtype=np.uint8)
        else:
            print(f"Isolated {len(selected_indices)} comforter blanket predictions for precise segmentation.")
            # If masks_np has shape (N, H, W)
            if len(masks_np.shape) == 3:
                masks_np_filtered = masks_np[selected_indices]
            else:
                masks_np_filtered = masks_np
                
            # Combine all masks, heal holes, and smooth edges using generate_precise_mask
            combined_mask_np = generate_precise_mask(masks_np_filtered)
            
    # 5. Saving Results
    # Sanitize text prompt for safe filename representation
    prompt_sanitized = args.prompt.replace(" ", "_").replace("'", "").replace('"', "")
    output_mask_filename = f"mask_{prompt_sanitized}.png"
    
    print(f"Saving raw binary mask to '{output_mask_filename}'...")
    try:
        Image.fromarray(combined_mask_np).save(output_mask_filename)
    except Exception as e:
        print(f"Error: Failed to save mask image. Details: {e}")
        
    print(f"Generating and saving visual overlay to '{args.output_overlay}'...")
    try:
        overlay_pil = create_visual_overlay(image_pil, combined_mask_np, alpha=args.alpha)
        overlay_pil.save(args.output_overlay)
    except Exception as e:
        print(f"Error: Failed to save overlay image. Details: {e}")
        
    print("\nSegmentation process completed successfully!")
    print(f"Outputs generated:")
    print(f"  - Binary Mask:    {os.path.abspath(output_mask_filename)}")
    print(f"  - Visual Overlay: {os.path.abspath(args.output_overlay)}")

if __name__ == "__main__":
    main()
