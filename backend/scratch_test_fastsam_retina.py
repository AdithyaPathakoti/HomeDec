from PIL import Image
from ultralytics import FastSAM

def test():
    model = FastSAM("FastSAM-s.pt")
    pil_image = Image.open("../bedroom_sample.png").convert("RGB")
    w, h = pil_image.size
    cx, cy = int(0.5 * w), int(0.7 * h)
    
    # 1. Point only with retina masks
    results = model.predict(pil_image, points=[[cx, cy]], labels=[1], conf=0.15, device="cpu", imgsz=640, retina_masks=True)
    if results and results[0].masks:
        print(f"Point found {len(results[0].masks)} masks")
        results[0].save("test_fastsam_point_retina.png")
    else:
        print("Point found no masks")

if __name__ == "__main__":
    test()
