from PIL import Image
import os
import shutil
from gradio_client import Client, handle_file
from .utils import load_image

class InpaintService:
    def __init__(self):
        self.client = None
        # Use the official, highly-stable stable-diffusion-xl-inpainting space by diffusers
        self.model_id = "diffusers/stable-diffusion-xl-inpainting"
        print(f"InpaintService initialized. Configured model: {self.model_id} (Cloud GPU)")

    def load_model(self):
        """Lazy load the Gradio Client connection to ensure fast backend startup."""
        if self.client is None:
            print(f"Connecting to cloud API space {self.model_id}...")
            # Check for optional Hugging Face token in the environment to bypass rate limits
            hf_token = os.getenv("HF_TOKEN")
            try:
                if hf_token:
                    print("Hugging Face API token detected. Authenticating...")
                    self.client = Client(self.model_id, hf_token=hf_token)
                else:
                    self.client = Client(self.model_id)
                print("Cloud API connected successfully.")
            except Exception as e:
                print(f"Failed to connect to primary space {self.model_id}: {e}")
                raise e

    def run_inpaint(self, image_path: str, mask_path: str, depth_path: str, prompt: str, output_path: str, strength: float = 0.02) -> str:
        # Ensure client is loaded
        self.load_model()
        
        # Load original images (HD)
        orig_image = load_image(image_path)
        orig_mask = load_image(mask_path).convert("L") # Convert mask to grayscale
        orig_size = orig_image.size
        
        print(f"Sending inpainting request to cloud ({self.model_id}). Prompt: '{prompt}' | Strength: {strength}")
        
        try:
            # Prepare inputs according to the Gradio 4 Imageeditor specification
            input_image_data = {
                "background": handle_file(image_path),
                "layers": [handle_file(mask_path)],
                "composite": None
            }
            
            # Additional negative prompt to improve quality and avoid distortions
            negative_prompt = "poorly drawn, distorted, low resolution, ugly, bad lighting"
            
            # Dynamically route prediction call depending on model type (SDXL or FLUX.1-Dev)
            if "flux" in self.model_id.lower():
                print(f"Routing to FLUX.1-Dev endpoint (/process)...")
                result = self.client.predict(
                    input_image_editor=input_image_data,
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    controlnet_conditioning_scale=0.9,
                    guidance_scale=3.5,
                    seed=124,
                    num_inference_steps=24,
                    true_guidance_scale=3.5,
                    api_name="/process"
                )
                if isinstance(result, dict) and "path" in result:
                    generated_webp_path = result["path"]
                else:
                    generated_webp_path = result
            else:
                # Call SDXL predict endpoint
                print(f"Routing to SDXL endpoint (/predict)...")
                result = self.client.predict(
                    input_image=input_image_data,
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    guidance_scale=7.5,
                    steps=20,
                    strength=strength,
                    scheduler="EulerDiscreteScheduler",
                    api_name="/predict"
                )
                
                if not result or len(result) < 2:
                    raise ValueError(f"Invalid API response structure: {result}")
                    
                # The second item in the list is the generated/modified image path
                generated_webp_path = result[1]
                
            print(f"Successfully generated image in cloud: {generated_webp_path}")
            
            # Load the generated image (usually webp)
            generated_img = Image.open(generated_webp_path)
            
            # Resize the low-res/model-res generated image back to the HD original size
            generated_hd = generated_img.resize(orig_size, Image.Resampling.LANCZOS)
            
            # Local depth gradient detail blending
            import numpy as np
            import cv2
            
            # Load depth map
            depth_img = Image.open(depth_path).convert("L")
            depth_np = np.array(depth_img, dtype=np.float32) / 255.0
            
            # Compute depth gradients
            grad_x = cv2.Sobel(depth_np, cv2.CV_32F, 1, 0, ksize=5)
            grad_y = cv2.Sobel(depth_np, cv2.CV_32F, 0, 1, ksize=5)
            grad_mag = np.sqrt(grad_x**2 + grad_y**2)
            
            # Normalize gradient magnitude to [0.0, 1.0]
            max_grad = grad_mag.max()
            if max_grad > 1e-4:
                grad_mag = grad_mag / max_grad
            else:
                grad_mag = np.zeros_like(grad_mag)
                
            # Smooth weight map to avoid hard transitions
            grad_mag_smooth = cv2.GaussianBlur(grad_mag, (9, 9), 3.0)
            
            # Convert PIL images to numpy for pixel-wise blending
            orig_np = np.array(orig_image, dtype=np.float32)
            gen_np = np.array(generated_hd, dtype=np.float32)
            
            # Blend the classical render (orig_np) with the diffusion output (gen_np) using depth gradient weight
            # High gradient (folds/valleys) -> use diffusion; low gradient (flat areas) -> use classical
            weight_3d = grad_mag_smooth[:, :, np.newaxis]
            blended_np = gen_np * weight_3d + orig_np * (1.0 - weight_3d)
            blended_np = np.clip(blended_np, 0.0, 255.0).astype(np.uint8)
            blended_img = Image.fromarray(blended_np, "RGB")
            
            # Composite: combine the blended image (for masked area) with the untouched original HD image.
            # This guarantees that the rest of the bedroom remains perfectly untouched and pixel-perfect.
            # PIL composite: white in mask = use image1 (blended_img), black in mask = use image2 (orig_image)
            final_image = Image.composite(blended_img, orig_image, orig_mask)
            
            # Save as PNG directly to the destination path expected by FastAPI
            final_image.save(output_path, "PNG")
            print(f"Saved final HD composite image to {output_path}")
            return output_path
            
        except Exception as e:
            print(f"Error during cloud inpainting: {e}")
            raise e

    def run_pattern_blend(self, image_path: str, mask_path: str, pattern_path: str, output_path: str, verify_dir: str = None) -> str:
        """
        Replaces the original bedsheet/comforter at 100% opacity with the target fabric
        swatch, preserving only the large-scale macroscopic fold/crease/shadow geometry
        from the original scene.

        Algorithm: Macro-Shading via Low-Pass Luminance Extraction
        -----------------------------------------------------------
        The critical insight is that the shading map must be computed from a HEAVILY
        BLURRED version of the original luminance, not the raw per-pixel values.

        Why:  The original fabric has its own high-frequency printed pattern (dark leaves,
              light background, etc.).  If we use raw per-pixel luminance as the fold map,
              those fine-detail variations get stamped directly onto the new fabric -
              making it look like the original pattern is "bleeding through."

        Fix:  Apply a large Gaussian blur (radius ~1/8 of mask width) to the luminance
              map before normalising it.  The blur destroys all print-pattern detail while
              preserving only the large-scale macro folds, creases and ambient shadows.
              The new fabric's own pattern (beige + brown leaves) then renders at 100%
              fidelity, shaded only by those real macro-structural shadows.

        Phase 1  Proportional tiling: tile size = 25% of mask bbox width.
        Phase 2  Macro-luminance extraction: heavy Gaussian blur on grayscale luma.
        Phase 3  Relative fold map: blurred_luma / mean_blurred_luma, clamped [0.55, 1.15].
        Phase 4  Relight: new_fabric * fold_map inside mask, orig everywhere else.
        Phase 5  Hard-binary composite: mask=255->new fabric, mask=0->original room.
        """
        import numpy as np
        import cv2

        print(f"[run_pattern_blend] Starting macro-shading blend. Pattern: {pattern_path}")

        # ── Load & hard-binarize mask ─────────────────────────────────────────
        orig_image    = load_image(image_path)
        raw_mask      = load_image(mask_path).convert("L")
        pattern_image = load_image(pattern_path)

        raw_mask_np    = np.array(raw_mask, dtype=np.uint8)
        # Hard binarize: any non-zero pixel (including soft Gaussian-blur edges
        # written by the segmenter) becomes fully opaque 255.
        binary_mask_np = np.where(raw_mask_np > 0, 255, 0).astype(np.uint8)
        mask_bool      = binary_mask_np > 0
        mask_image_pil = Image.fromarray(binary_mask_np, mode="L")
        print(f"[run_pattern_blend] Mask: {np.unique(binary_mask_np)} | "
              f"{mask_bool.sum()} px ({100*mask_bool.mean():.1f}% of frame)")

        w, h = orig_image.size

        # ── Phase 1: Proportional Fabric Tiling ──────────────────────────────
        ys, xs = np.where(mask_bool)
        if len(xs) > 0:
            bbox_w = int(xs.max() - xs.min())
            tile_size = max(64, min(512, bbox_w // 4))
        else:
            tile_size = 256
        print(f"[run_pattern_blend] Phase 1 - tile_size={tile_size}px")

        pattern_resized = pattern_image.resize((tile_size, tile_size), Image.Resampling.LANCZOS)
        tiled_image     = Image.new("RGB", (w, h))
        for x in range(0, w, tile_size):
            for y in range(0, h, tile_size):
                tiled_image.paste(pattern_resized, (x, y))

        # ── Phase 2: Macro-Luminance Extraction (KEY FIX) ────────────────────
        room_np    = np.array(orig_image,  dtype=np.float32)
        pattern_np = np.array(tiled_image, dtype=np.float32)

        # Step A: Compute raw grayscale luminance of the original room image.
        # This is a pure scalar map — no colour channels, no chrominance.
        room_luma = (0.299 * room_np[:, :, 0]
                   + 0.587 * room_np[:, :, 1]
                   + 0.114 * room_np[:, :, 2])

        # Step B: *** HEAVY GAUSSIAN BLUR ***
        # Blur radius ~12.5% of mask bounding-box width (must be an odd integer).
        # This destroys all high-frequency pattern detail from the original fabric
        # (its own printed leaves, folds in the weave, etc.) while preserving
        # only the large-scale gradient changes from real creases and shadows.
        blur_r     = max(21, (bbox_w // 8) | 1)   # round up to odd
        macro_luma = cv2.GaussianBlur(room_luma, (blur_r, blur_r), 0)
        print(f"[run_pattern_blend] Phase 2 - Macro blur radius: {blur_r}px")
        if verify_dir:
            luma_vis = np.clip(macro_luma, 0, 255).astype(np.uint8)
            luma_path = os.path.join(verify_dir, "luminance_map.png")
            cv2.imwrite(luma_path, luma_vis)
            print(f"[run_pattern_blend] Saved intermediate luminance map to '{luma_path}'")

        # ── Phase 3: Relative Fold Map (centred at 1.0) ───────────────────────
        # Normalise by mean of the blurred luma INSIDE the mask only.
        inside_macro = macro_luma[mask_bool]
        mean_macro   = float(np.mean(inside_macro)) if len(inside_macro) > 0 else 128.0
        mean_macro   = max(mean_macro, 30.0)
        print(f"[run_pattern_blend] Phase 3 - Mean macro-luma inside mask: {mean_macro:.1f}")

        # fold = 1.0 -> average surface, no change to new fabric colour.
        # fold < 1.0 -> real shadow/fold, darkens the new fabric naturally.
        # fold > 1.0 -> genuine highlight, brightens slightly.
        rel_fold_map = macro_luma / mean_macro
        rel_fold_map = np.clip(rel_fold_map, 0.55, 1.15)

        # ── Phase 4: Relight New Fabric with Macro Fold Map ──────────────────
        # Apply ONLY inside the mask; outside stays at fold=1.0 (but is
        # composited away in Phase 5 so it doesn't matter).
        fold_final   = np.where(mask_bool, rel_fold_map, 1.0)
        relit_np     = pattern_np * fold_final[:, :, np.newaxis]
        relit_np     = np.clip(relit_np, 0, 255).astype(np.uint8)

        mean_rgb = relit_np[mask_bool].mean(axis=0)
        print(f"[run_pattern_blend] Phase 4 - Relit fabric mean RGB inside mask: "
              f"R={mean_rgb[0]:.1f} G={mean_rgb[1]:.1f} B={mean_rgb[2]:.1f}")

        # ── Phase 5: Hard-Binary Pixel-Perfect Compositing ───────────────────
        # Image.composite(im1, im2, mask):
        #   mask pixel = 255 -> im1 (relit new fabric, 100% opacity)
        #   mask pixel = 0   -> im2 (original room, completely untouched)
        # No alpha blending. No original colour bleeds inside the mask.
        relit_pil   = Image.fromarray(relit_np, "RGB")
        final_image = Image.composite(relit_pil, orig_image, mask_image_pil)

        final_image.save(output_path, "PNG")
        print(f"[run_pattern_blend] Done -> {output_path}")
        if verify_dir:
            comp_path = os.path.join(verify_dir, "final_composition.png")
            final_image.save(comp_path, "PNG")
            print(f"[run_pattern_blend] Saved intermediate final composition to '{comp_path}'")
        return output_path


class VastraInpainter(InpaintService):
    """
    VastraInpainter subclassing InpaintService.
    Exposes a unified interface to swap fabric texture cleanly onto target masks.
    """
    def __init__(self):
        super().__init__()

    def run(self, source_image: str, mask_image: str, texture_image: str, save_path: str, verify_dir: str = None) -> str:
        """
        Runs the fabric inpainting flow. Uses high-fidelity pattern blending locally
        to map the fabric texture while preserving room highlights, shadows, and folds.
        
        Args:
            source_image (str): Path to original room image.
            mask_image (str): Path to binary mask image.
            texture_image (str): Path to fabric/texture pattern image.
            save_path (str): Destination path to save the final swapped output.
            verify_dir (str, optional): Subfolder to save intermediate steps.
            
        Returns:
            str: Path of the saved image.
        """
        print(f"[VastraInpainter] Executing fabric swap pipeline...")
        return self.run_pattern_blend(
            image_path=source_image,
            mask_path=mask_image,
            pattern_path=texture_image,
            output_path=save_path,
            verify_dir=verify_dir
        )

    def apply_fabric_swap(self, source_image: str, mask_image: str, texture_image: str, save_path: str, verify_dir: str = None) -> str:
        """Alias for standard run interface."""
        return self.run(source_image, mask_image, texture_image, save_path, verify_dir)
