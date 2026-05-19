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
                # Fallback to another popular running space if primary is down
                fallback_space = "ameerazam08/FLUX.1-dev-Inpainting-Model-Beta-GPU"
                print(f"Attempting to connect to fallback space {fallback_space}...")
                try:
                    if hf_token:
                        self.client = Client(fallback_space, hf_token=hf_token)
                    else:
                        self.client = Client(fallback_space)
                    self.model_id = fallback_space
                    print("Fallback cloud API connected successfully.")
                except Exception as ex:
                    print(f"All cloud API connection attempts failed: {ex}")
                    raise ex

    def run_inpaint(self, image_path: str, mask_path: str, prompt: str, output_path: str) -> str:
        # Ensure client is loaded
        self.load_model()
        
        # Load original images (HD)
        orig_image = load_image(image_path)
        orig_mask = load_image(mask_path).convert("L") # Convert mask to grayscale
        orig_size = orig_image.size
        
        print(f"Sending inpainting request to cloud ({self.model_id}). Prompt: '{prompt}'")
        
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
                    strength=0.99,
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
            
            # Composite: combine the generated HD image (for masked area) with the untouched original HD image.
            # This guarantees that the rest of the bedroom remains perfectly untouched and pixel-perfect.
            # PIL composite: white in mask = use image1 (generated_hd), black in mask = use image2 (orig_image)
            final_image = Image.composite(generated_hd, orig_image, orig_mask)
            
            # Save as PNG directly to the destination path expected by FastAPI
            final_image.save(output_path, "PNG")
            print(f"Saved final HD composite image to {output_path}")
            return output_path
            
        except Exception as e:
            print(f"Error during cloud inpainting: {e}")
            raise e

    def run_pattern_blend(self, image_path: str, mask_path: str, pattern_path: str, output_path: str) -> str:
        """
        Overlays a pattern/design image onto the masked area of the room image
        while perfectly preserving original bedsheet shadows, creases, lighting, and folds.
        Runs completely offline in milliseconds using numpy and PIL!
        """
        import numpy as np
        
        print(f"Starting local pattern blending. Pattern image: {pattern_path}")
        
        # 1. Load images
        orig_image = load_image(image_path)
        mask_image = load_image(mask_path).convert("L")
        pattern_image = load_image(pattern_path)
        
        w, h = orig_image.size
        
        # 2. Resize and tile the pattern image to cover the room image dimensions
        # 256x256 is an excellent tiling size for rich fabric details
        tile_size = 256
        pattern_resized = pattern_image.resize((tile_size, tile_size), Image.Resampling.LANCZOS)
        
        tiled_image = Image.new("RGB", (w, h))
        for x in range(0, w, tile_size):
            for y in range(0, h, tile_size):
                tiled_image.paste(pattern_resized, (x, y))
                
        # 3. Extract shadows, folds, and highlights from original bedsheet
        room_np = np.array(orig_image, dtype=np.float32)
        pattern_np = np.array(tiled_image, dtype=np.float32)
        mask_np = np.array(mask_image, dtype=np.float32) / 255.0
        
        # Calculate luminance (0.299 * R + 0.587 * G + 0.114 * B)
        luminance = 0.299 * room_np[:, :, 0] + 0.587 * room_np[:, :, 1] + 0.114 * room_np[:, :, 2]
        
        # Calculate reference base brightness of the bedsheet in the masked area
        # Use 75th percentile to represent clear base fabric highlights
        masked_lumi = luminance[mask_np > 0.1]
        if len(masked_lumi) > 0:
            ref_brightness = np.percentile(masked_lumi, 75)
            # Clip to reasonable highlight values
            ref_brightness = np.clip(ref_brightness, 80.0, 220.0)
        else:
            ref_brightness = 180.0
            
        # Shading factor is original luminance / base reference brightness
        # Clamp to [0.15, 1.35] to preserve fabric contrast while preventing over/underexposure
        shading_factor = luminance / ref_brightness
        shading_factor = np.clip(shading_factor, 0.15, 1.35)
        
        # Apply shading factor to the tiled pattern
        blended_np = pattern_np * shading_factor[:, :, np.newaxis]
        blended_np = np.clip(blended_np, 0, 255).astype(np.uint8)
        
        blended_image = Image.fromarray(blended_np)
        
        # 4. Composite the realistic shaded pattern onto the original room
        final_image = Image.composite(blended_image, orig_image, mask_image)
        
        # Save and return
        final_image.save(output_path, "PNG")
        print(f"Successfully generated realistic pattern blended image at {output_path}")
        return output_path
