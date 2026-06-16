import os
import torch
import cv2
import numpy as np

class DepthEstimationService:
    def __init__(self, device: str = None):
        if device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        else:
            self.device = device
        self.model = None
        self.transform = None
        print(f"[DepthEstimationService] Initialized with device={self.device}")

    def load_model(self):
        if self.model is None:
            print("[DepthEstimationService] Loading MiDaS model small...")
            # Load MiDaS_small from PyTorch Hub
            self.model = torch.hub.load("intel-isl/MiDaS", "MiDaS_small")
            self.model.to(self.device)
            self.model.eval()
            
            # Load transforms
            midas_transforms = torch.hub.load("intel-isl/MiDaS", "transforms")
            self.transform = midas_transforms.small_transform
            print("[DepthEstimationService] MiDaS model loaded.")

    def predict_depth(self, image_np: np.ndarray) -> np.ndarray:
        """
        Estimate a depth map from the input RGB image.
        
        Args:
            image_np: RGB image numpy array, shape (H, W, 3), dtype uint8.
            
        Returns:
            np.ndarray: Normalized depth map, shape (H, W), dtype float32,
                        values normalized to range [0.0 (farthest), 1.0 (closest)].
        """
        self.load_model()
        h, w = image_np.shape[:2]
        
        # Prepare input batch
        input_batch = self.transform(image_np).to(self.device)
        
        with torch.no_grad():
            prediction = self.model(input_batch)
            prediction = torch.nn.functional.interpolate(
                prediction.unsqueeze(1),
                size=(h, w),
                mode="bicubic",
                align_corners=False,
            ).squeeze()
            
        depth_map = prediction.cpu().numpy()
        
        # Normalize to [0.0, 1.0] range
        d_min, d_max = depth_map.min(), depth_map.max()
        if d_max > d_min:
            depth_map = (depth_map - d_min) / (d_max - d_min)
        else:
            depth_map = np.zeros_like(depth_map, dtype=np.float32)
            
        return depth_map
