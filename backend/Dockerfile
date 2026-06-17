# Use an official lightweight Python base image
FROM python:3.10-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

# Set HOME to /app so that ~ (expanduser) resolves to a reliable, writable location
ENV HOME=/app
ENV TORCH_HOME=/app/.cache/torch
ENV SAM2_BUILD_ALLOW_CPU_ONLY=1

# Install system dependencies (build-essential, git, and OpenCV GUI requirements)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file first for layer caching
COPY requirements.txt .

# Install CPU-specific PyTorch to keep build sizes small and reduce memory footprint on Render
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install Python package requirements
RUN pip install --no-cache-dir -r requirements.txt

# Install segment-anything-2 from PyPI
RUN pip install --no-cache-dir segment-anything-2

# Copy the rest of the application code
COPY . .

# Pre-download and cache model weights during the Docker image build stage.
# This prevents 30-second request timeouts on first start in Render.
RUN python -c " \
import os; \
import torch; \
print('Pre-downloading MiDaS model...'); \
torch.hub.load('intel-isl/MiDaS', 'MiDaS_small'); \
print('Pre-downloading SAM2 model...'); \
from ai.segmentation import InteractiveSAMEngine; \
engine = InteractiveSAMEngine(model_variant='sam2_hiera_tiny', device='cpu'); \
engine._get_predictor(); \
print('All model weights cached successfully!')"

# Expose the application port
EXPOSE 8000

# Run the FastAPI app with Uvicorn
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
