"""
Vastra AI Utilities - Geometric Alignment & Post-Processing
=============================================================

Utility functions for image handling, mask post-processing, and geometric
alignment used across the Vastra AI pipeline.

Includes:
  - File I/O helpers (save_upload_file, ensure_dirs, load_image)
  - Image transforms (compress_image, pil_to_bytes, numpy_to_pil)
  - Contour Dominance Filtering (isolate largest mask structure)
  - Anti-Fringe Mask Dilation (eliminate rim artifacts)
"""

from PIL import Image
import io
import os
import shutil
import cv2
import numpy as np
from pathlib import Path


# ═════════════════════════════════════════════════════════════════════════════
#  File I/O Helpers
# ═════════════════════════════════════════════════════════════════════════════

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


# ═════════════════════════════════════════════════════════════════════════════
#  Image Transforms
# ═════════════════════════════════════════════════════════════════════════════

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
    return Image.fromarray(arr.astype(np.uint8), mode)


# ═════════════════════════════════════════════════════════════════════════════
#  Contour Dominance Filtering
# ═════════════════════════════════════════════════════════════════════════════

def contour_dominance_filter(mask_np: np.ndarray, points: list = None) -> np.ndarray:
    """
    Isolate continuous mask structures containing positive prompts and drop all noise.

    If points are provided, we retain any contour that contains (or is very close to)
    at least one positive tap point (label == 1), and does NOT contain any negative tap point.
    If no points are provided, we fallback to retaining the largest contour.

    Args:
        mask_np: Binary mask (H, W), dtype uint8, 255 = foreground.
        points: Optional list of dicts with keys 'x', 'y', 'label' (normalized coords).

    Returns:
        np.ndarray: Cleaned binary mask (H, W), dtype uint8.
    """
    if mask_np is None or mask_np.size == 0 or mask_np.max() == 0:
        return np.zeros_like(mask_np) if mask_np is not None else np.zeros((1, 1), dtype=np.uint8)

    # Ensure binary
    _, binary = cv2.threshold(mask_np, 127, 255, cv2.THRESH_BINARY)
    h, w = mask_np.shape[:2]

    # Map points to pixel coordinates if provided
    pos_pixel_points = []
    neg_pixel_points = []
    if points:
        for pt in points:
            px_x = pt["x"] * w
            px_y = pt["y"] * h
            if pt.get("label") == 1:
                pos_pixel_points.append((px_x, px_y))
            else:
                neg_pixel_points.append((px_x, px_y))

    # Apply morphological erosion to disconnect components connected by narrow bridges
    kernel = np.ones((5, 5), np.uint8)
    eroded = cv2.erode(binary, kernel, iterations=2)

    # Find all external contours (topological boundary detection)
    contours, _ = cv2.findContours(
        eroded, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )

    eroded_used = True
    if not contours:
        # Fallback to original binary if erosion cleared everything
        contours, _ = cv2.findContours(
            binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        eroded_used = False

    retained_contours = []

    # Filter contours
    for contour in contours:
        has_pos = False
        if pos_pixel_points:
            for (px_x, px_y) in pos_pixel_points:
                # signed distance test: >= 0 is inside/on edge.
                # We allow up to 25 pixels outside for eroded shapes.
                dist = cv2.pointPolygonTest(contour, (px_x, px_y), True)
                if dist >= -25.0:
                    has_pos = True
                    break
        else:
            has_pos = True

        has_neg = False
        if neg_pixel_points:
            for (px_x, px_y) in neg_pixel_points:
                dist = cv2.pointPolygonTest(contour, (px_x, px_y), True)
                if dist >= -15.0:
                    has_neg = True
                    break

        if has_pos:
            retained_contours.append(contour)

    # Fallback to the largest contour if no contours matched
    if not retained_contours and not pos_pixel_points:
        orig_contours, _ = cv2.findContours(
            binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        if orig_contours:
            largest_contour = max(orig_contours, key=cv2.contourArea)
            largest_area = cv2.contourArea(largest_contour)
            if largest_area >= 1.0:
                retained_contours.append(largest_contour)
                eroded_used = False

    # Draw all retained contours filled onto a clean canvas
    clean_mask = np.zeros_like(mask_np)
    if retained_contours:
        cv2.drawContours(clean_mask, retained_contours, -1, 255, cv2.FILLED)

    # Restore the original mask boundaries for the retained components via dilation
    if retained_contours and eroded_used:
        clean_mask = cv2.dilate(clean_mask, kernel, iterations=2)
        clean_mask = cv2.bitwise_and(clean_mask, binary)

    # Explicitly punch out a circle around all negative tap points, scaled by image resolution
    if neg_pixel_points:
        radius = max(25, int(max(w, h) * 0.03))
        for (px_x, px_y) in neg_pixel_points:
            cv2.circle(clean_mask, (int(px_x), int(px_y)), radius, 0, -1)

    return clean_mask


# ═════════════════════════════════════════════════════════════════════════════
#  Anti-Fringe Mask Dilation
# ═════════════════════════════════════════════════════════════════════════════

def anti_fringe_dilate(
    mask_np: np.ndarray,
    dilate_px: int = 2,
    blur_sigma: float = 1.0,
) -> np.ndarray:
    """
    Apply a tiny morphological dilation followed by a gentle Gaussian edge
    feather to eliminate rim artifacts (anti-fringe).

    Purpose:
      When projecting a new fabric texture onto a segmented region, the
      original fabric color can peek through as a thin fringe/rim around
      the mask boundary. This function pushes the mask edge outward by
      1-2 pixels and softens the transition to prevent that artifact.

    Algorithm:
      1. Dilate the mask with a small elliptical kernel (dilate_px radius).
         This expands the mask boundary outward by 1-2 pixels.
      2. Apply a gentle Gaussian blur to feather the hard dilated edge.
         This creates a smooth alpha transition at the boundary.
      3. Re-threshold to binary to maintain a clean mask.

    Args:
        mask_np: Binary mask (H, W), dtype uint8, 255 = foreground.
        dilate_px: Dilation kernel radius in pixels (default: 2).
        blur_sigma: Gaussian blur sigma for edge feathering (default: 1.0).

    Returns:
        np.ndarray: Anti-fringed binary mask (H, W), dtype uint8.
    """
    if mask_np is None or mask_np.size == 0 or mask_np.max() == 0:
        return np.zeros_like(mask_np) if mask_np is not None else np.zeros((1, 1), dtype=np.uint8)

    # Ensure binary input
    _, binary = cv2.threshold(mask_np, 127, 255, cv2.THRESH_BINARY)

    # Step 1: Morphological dilation with small elliptical kernel
    kernel_size = max(3, dilate_px * 2 + 1)  # Ensure odd kernel size
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (kernel_size, kernel_size)
    )
    dilated = cv2.dilate(binary, kernel, iterations=1)

    # Step 2: Gentle Gaussian blur to feather the hard edge
    blur_ksize = max(3, int(blur_sigma * 4) | 1)  # Ensure odd
    feathered = cv2.GaussianBlur(
        dilated.astype(np.float32), (blur_ksize, blur_ksize), blur_sigma
    )

    # Step 3: Re-threshold to clean binary mask
    _, result = cv2.threshold(
        feathered.astype(np.uint8), 127, 255, cv2.THRESH_BINARY
    )

    # Report expansion
    original_area = np.count_nonzero(binary)
    expanded_area = np.count_nonzero(result)
    expansion_px = expanded_area - original_area
    if expansion_px > 0:
        print(
            f"[anti_fringe_dilate] Expanded mask by {expansion_px} pixels "
            f"({original_area} -> {expanded_area})."
        )

    return result
