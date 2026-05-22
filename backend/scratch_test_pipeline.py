import os
import sys
import torch
from PIL import Image

# Add current directory to sys.path to allow importing local modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ai.pipeline import VastraPipeline
from ultralytics import YOLO, FastSAM

def run_tests():
    print("=== STARTING VASTRA AI PIPELINE INTEGRATION TESTS ===")
    
    # Paths to generated test images in the artifact directory
    bedroom_path = r"C:\Users\ADITHYA\.gemini\antigravity-ide\brain\6b2eb953-cd10-4c06-8097-d286d67ea180\bedroom_test_1779381364998.png"
    livingroom_path = r"C:\Users\ADITHYA\.gemini\antigravity-ide\brain\6b2eb953-cd10-4c06-8097-d286d67ea180\livingroom_test_1779381388038.png"
    fabric_path = r"e:\E DRIVE\FLUTTER INTERN\vastra\frontend\assets\fabrics\floral.jpg"
    
    if not os.path.exists(bedroom_path):
        print(f"Error: Bedroom test image not found at {bedroom_path}")
        return
    if not os.path.exists(livingroom_path):
        print(f"Error: Living room test image not found at {livingroom_path}")
        return
    if not os.path.exists(fabric_path):
        print(f"Error: Fabric swatch not found at {fabric_path}")
        return

    print("Loading test images...")
    bedroom_img = Image.open(bedroom_path).convert("RGB")
    livingroom_img = Image.open(livingroom_path).convert("RGB")
    fabric_img = Image.open(fabric_path).convert("RGB")

    print(f"Bedroom image size: {bedroom_img.size}")
    print(f"Living room image size: {livingroom_img.size}")
    print(f"Fabric image size: {fabric_img.size}")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using hardware device: {device}")

    print("Loading YOLOv8n and FastSAM-s models...")
    yolo = YOLO("yolov8n.pt")
    fastsam = FastSAM("FastSAM-s.pt")
    print("Models loaded successfully.")

    pipeline = VastraPipeline(yolo, fastsam, device=device)

    # 1. Test Bedsheets
    print("\n--- 1. Testing Bedsheets ---")
    try:
        bedsheets_out = pipeline.process(bedroom_img, "bedsheets", fabric_img)
        bedsheets_out.save("test_out_bedsheets.png")
        print("Bedsheets swap success! Saved output to test_out_bedsheets.png")
    except Exception as e:
        import traceback
        print(f"Bedsheets swap failed: {e}\n{traceback.format_exc()}")

    # 2. Test Pillows on Bed
    print("\n--- 2. Testing Pillows ---")
    try:
        pillows_out = pipeline.process(bedroom_img, "pillows", fabric_img)
        pillows_out.save("test_out_pillows.png")
        print("Pillows swap success! Saved output to test_out_pillows.png")
    except Exception as e:
        import traceback
        print(f"Pillows swap failed: {e}\n{traceback.format_exc()}")

    # 3. Test Curtains
    print("\n--- 3. Testing Curtains ---")
    try:
        curtains_out = pipeline.process(bedroom_img, "curtains", fabric_img)
        curtains_out.save("test_out_curtains.png")
        print("Curtains swap success! Saved output to test_out_curtains.png")
    except Exception as e:
        import traceback
        print(f"Curtains swap failed: {e}\n{traceback.format_exc()}")

    # 4. Test Sofa Covers
    print("\n--- 4. Testing Sofa Covers ---")
    try:
        sofa_out = pipeline.process(livingroom_img, "sofa_covers", fabric_img)
        sofa_out.save("test_out_sofa_covers.png")
        print("Sofa Covers swap success! Saved output to test_out_sofa_covers.png")
    except Exception as e:
        import traceback
        print(f"Sofa Covers swap failed: {e}\n{traceback.format_exc()}")

    # 5. Test Carpets
    print("\n--- 5. Testing Carpets ---")
    try:
        carpets_out = pipeline.process(livingroom_img, "carpets", fabric_img)
        carpets_out.save("test_out_carpets.png")
        print("Carpets swap success! Saved output to test_out_carpets.png")
    except Exception as e:
        import traceback
        print(f"Carpets swap failed: {e}\n{traceback.format_exc()}")

    print("\n=== INTEGRATION TESTS COMPLETED ===")

if __name__ == "__main__":
    run_tests()
