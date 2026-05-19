from gradio_client import Client, handle_file
from PIL import Image
import numpy as np
import io

def test_sam2_diff():
    client = Client('SkalskiP/segment-anything-model-2')
    
    # Create a dummy image (e.g. 512x512 with a solid color, but let's make it a gradient so the diff is obvious)
    img_arr = np.zeros((512, 512, 3), dtype=np.uint8)
    for x in range(512):
        for y in range(512):
            img_arr[y, x] = [x // 2, y // 2, 100]
            
    img = Image.fromarray(img_arr)
    img_path = "test_sam2_grad.png"
    img.save(img_path)
    
    try:
        # Ask SAM2 to mask the center
        prompter_input = {
            "image": handle_file(img_path),
            "points": [[200.0, 200.0, 2.0, 300.0, 300.0, 2.0]] # box prompt
        }
        
        result_path = client.predict(
            checkpoint_dropdown="tiny",
            mode_dropdown="box prompt",
            image_input=handle_file(img_path),
            image_prompter_input=prompter_input,
            api_name="/process_1"
        )
        
        annotated_img = Image.open(result_path).convert("RGB")
        ann_arr = np.array(annotated_img, dtype=np.int32)
        orig_arr = np.array(img, dtype=np.int32)
        
        diff = np.abs(ann_arr - orig_arr).sum(axis=2)
        mask = (diff > 5).astype(np.uint8) * 255
        
        mask_img = Image.fromarray(mask, mode="L")
        mask_img.save("test_sam2_extracted_mask.png")
        
        print("Success! Extracted mask saved.")
        
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    test_sam2_diff()
