import time
from PIL import Image
from ultralytics import FastSAM

def test_fastsam():
    print("Loading FastSAM model...")
    model = FastSAM("FastSAM-s.pt")
    
    img_path = "../bedroom_sample.png"
    pil_image = Image.open(img_path).convert("RGB")
    w, h = pil_image.size
    
    # Simulate tapping on the bedsheet (e.g. x=0.5, y=0.7)
    cx, cy = int(0.5 * w), int(0.7 * h)
    tolerance = 40
    
    # 1. Box + Point (what main.py does)
    half_size = max(20, int(tolerance * 4.5))
    x1 = max(0, cx - half_size)
    y1 = max(0, cy - half_size)
    x2 = min(w, cx + half_size)
    y2 = min(h, cy + half_size)
    
    t0 = time.time()
    results1 = model.predict(pil_image, bboxes=[[x1, y1, x2, y2]], points=[[cx, cy]], labels=[1], conf=0.15, device="cpu", imgsz=640)
    t1 = time.time()
    print(f"Box+Point time: {t1-t0:.2f}s")
    if results1 and results1[0].masks:
        print(f"Box+Point found {len(results1[0].masks)} masks")
        results1[0].save("test_fastsam_box_point.png")
    else:
        print("Box+Point found no masks")
        
    # 2. Point only
    t0 = time.time()
    results2 = model.predict(pil_image, points=[[cx, cy]], labels=[1], conf=0.15, device="cpu", imgsz=640)
    t1 = time.time()
    print(f"Point time: {t1-t0:.2f}s")
    if results2 and results2[0].masks:
        print(f"Point found {len(results2[0].masks)} masks")
        results2[0].save("test_fastsam_point.png")
    else:
        print("Point found no masks")

if __name__ == "__main__":
    test_fastsam()
