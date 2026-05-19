import requests
import json

def test_endpoints():
    url_detect = "http://localhost:8000/detect_objects"
    url_mask = "http://localhost:8000/auto_mask"
    
    # We will use the bedroom_sample.png located in the workspace root
    img_path = "../bedroom_sample.png"
    
    print("Testing /detect_objects endpoint...")
    try:
        with open(img_path, "rb") as f:
            files = {"image": f}
            response = requests.post(url_detect, files=files)
            
        print("Status code:", response.statusCode if hasattr(response, 'statusCode') else response.status_code)
        res_json = response.json()
        print("Detected objects:")
        print(json.dumps(res_json, indent=2))
        
        objects = res_json.get("objects", [])
        if objects:
            # Test auto_mask using the first detected object's bounding box
            first_obj = objects[0]
            box_str = ",".join(map(str, first_obj["box"]))
            print(f"\nTesting /auto_mask endpoint with bounding box: {box_str} ({first_obj['label']})...")
            
            with open(img_path, "rb") as f:
                files = {"image": f}
                data = {"box": box_str}
                response_mask = requests.post(url_mask, files=files, data=data)
                
            print("Status code:", response_mask.status_code)
            if response_mask.status_code == 200:
                out_mask_path = "test_sam2_detected_mask.png"
                with open(out_mask_path, "wb") as f_out:
                    f_out.write(response_mask.content)
                print(f"Success! Saved mask to {out_mask_path}")
            else:
                print("Failed auto_mask:", response_mask.text)
        else:
            print("No objects detected to test auto_mask box prompt.")
            
    except Exception as e:
        print("Error during test:", e)

if __name__ == "__main__":
    test_endpoints()
