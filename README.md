<div align="center">

# 🎨 HomeDec — AI-Powered Interior Fabric Visualizer

### Photorealistic fabric replacement on real room photographs using SAM2 segmentation and a 9-stage classical rendering engine.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.x-EE4C2C?style=for-the-badge&logo=pytorch&logoColor=white)](https://pytorch.org)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker&logoColor=white)](Dockerfile)

---

**HomeDec** lets users photograph any room, tap on a fabric surface (bedsheet, curtain, sofa, rug), and instantly preview alternative fabric patterns with photorealistic lighting, wrinkles, and depth — all in real time.

</div>

---

## ✨ Key Features

| Feature | Description |
|---|---|
| 🧠 **SAM2 Interactive Segmentation** | Point-and-tap object selection using Meta's Segment Anything Model 2 (Hiera-Tiny). Cached encoder embeddings enable **10–50ms** decoder passes for real-time mask refinement. |
| 🖼️ **9-Stage Photorealistic Rendering** | Classical computer vision pipeline with coordinate-based tiling, perspective warp, dual-Gaussian shading extraction, specular recovery, ambient occlusion, fold-following displacement, LAB relighting, and edge feathering. |
| 🎛️ **Real-Time Pattern Controls** | Adjust fabric scale, rotation, and X/Y offset with interactive sliders — each change re-renders through the full pipeline instantly. |
| 🤖 **Optional Diffusion Refinement** | Hybrid mode passes the classical render through a diffusion inpainting model for enhanced edge blending and shadow realism. |
| 📐 **Depth-Aware Processing** | MiDaS monocular depth estimation provides geometric context for perspective-accurate texture projection. |
| ✏️ **Manual Mask Editing** | Brush-based mask refinement with morphological cleanup and anti-fringe dilation for pixel-perfect selections. |
| 🎨 **Premium UI/UX** | Glassmorphic design system, particle backgrounds, animated glow buttons, before/after comparison slider, and luxury onboarding flow. |
| 📱 **Cross-Platform** | Flutter frontend runs on Android, iOS, Web, Windows, macOS, and Linux. |

---

## 🏗️ System Architecture

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/5bc88c33-ba2c-4887-983a-cda99a305ec6" />


---

## 🔬 The 9-Stage Texture Projection Pipeline

The core rendering engine replaces flat texture pasting with a physically-motivated pipeline that preserves lighting, wrinkles, and depth:

| Stage | Name | What It Does |
|:---:|---|---|
| 1 | **Coordinate-Based Remap Tiling** | Seamless pattern repetition via `cv2.remap` with `BORDER_WRAP` — supports real-time scale, rotation, and translation with no mirroring artifacts. |
| 2 | **Perspective Warp** | Row-wise horizontal compression simulates depth recession for flat surfaces (beds, carpets). |
| 3 | **Shading Map Extraction** | Dual Gaussian blur isolates macro room shadows and meso fold contours while removing original pattern detail. |
| 4 | **Specular Highlight Recovery** | Extracts bright specular sheen from the original fabric (pixels > μ + 1.5σ) and overlays them on the new texture. |
| 5 | **Ambient Occlusion** | Darkens fold valleys using `AO = 1.0 − (Local Mean / Global Mean)`. |
| 6 | **Fold-Following Warp** | Sobel gradient displacement field bends the fabric pattern along detected wrinkles (±8px clamped). |
| 7 | **LAB Channel Relighting** | Luminance modulation in CIELAB space with chrominance shifting to match room white balance. |
| 8 | **Detail Sharpening** | Unsharp masking restores fabric print crispness after compositing. |
| 9 | **Thin-Edge Composite** | 5px Gaussian alpha feather blends mask boundaries without color bleeding. |

---

## 🛠️ Tech Stack

### Backend (Python)

| Library | Purpose |
|---|---|
| **FastAPI + Uvicorn** | High-performance async REST API server |
| **PyTorch + Torchvision** | SAM2 and MiDaS deep learning inference |
| **OpenCV** | Image transforms, coordinate remapping, morphological ops |
| **NumPy** | High-performance array computation |
| **Pillow** | Image I/O, format conversion, color-space transforms |
| **Pydantic** | Request/response validation and serialization |

### Frontend (Flutter/Dart)

| Package | Purpose |
|---|---|
| **Provider** | Reactive state management across screens |
| **http** | Multipart uploads and REST API communication |
| **flutter_animate** | Premium micro-animations and transition effects |
| **google_fonts** | Custom typography (modern, clean typefaces) |
| **image_picker** | Camera and gallery image acquisition |
| **hive + hive_flutter** | Local NoSQL storage for fabric catalog caching |
| **share_plus** | Native sharing of rendered results |

---

## 📁 Project Structure

```
HomeDec/
├── backend/                        # FastAPI + PyTorch AI Server
│   ├── ai/
│   │   ├── segmentation.py         # SAM2 encoder/decoder engine
│   │   ├── pipeline.py             # 9-stage texture projection engine
│   │   ├── depth.py                # MiDaS monocular depth estimation
│   │   ├── inpaint.py              # Diffusion-based hybrid refinement
│   │   ├── fabric_registry.py      # Fabric texture resolution & registry
│   │   └── utils.py                # Image processing utilities
│   ├── assets/fabrics/             # Bundled fabric texture library
│   ├── main.py                     # FastAPI application & endpoints
│   ├── Dockerfile                  # Production container configuration
│   └── requirements.txt            # Python dependencies
│
├── frontend/                       # Flutter Cross-Platform Client
│   ├── lib/
│   │   ├── core/
│   │   │   ├── constants.dart      # API endpoints & app configuration
│   │   │   └── theme.dart          # Glassmorphic design system & tokens
│   │   ├── models/
│   │   │   ├── fabric_item.dart    # Fabric data model (Hive-backed)
│   │   │   └── product_category.dart # Product category definitions
│   │   ├── providers/
│   │   │   ├── vastra_provider.dart        # Core app state controller
│   │   │   └── fabric_catalog_provider.dart # Fabric catalog manager
│   │   ├── screens/
│   │   │   ├── splash_screen.dart          # Animated splash screen
│   │   │   ├── onboarding_screen.dart      # First-launch onboarding
│   │   │   ├── home_screen.dart            # Room image upload
│   │   │   ├── processing_screen.dart      # Interactive segmentation
│   │   │   ├── fabric_catalog_screen.dart  # Fabric selection gallery
│   │   │   ├── result_screen.dart          # Final render + adjustments
│   │   │   └── admin_panel_screen.dart     # Admin/debug panel
│   │   ├── services/
│   │   │   └── api_service.dart    # HTTP client for backend communication
│   │   ├── widgets/
│   │   │   ├── animated_glow_button.dart   # Pulsing CTA button
│   │   │   ├── before_after_slider.dart    # Before/after comparison
│   │   │   ├── particle_background.dart    # Ambient particle effects
│   │   │   └── product_card.dart           # Category selection cards
│   │   └── main.dart               # App entry point
│   ├── assets/fabrics/             # Client-side fabric thumbnails
│   └── pubspec.yaml                # Flutter dependencies
│
├── render.yaml                     # Render.com deployment manifest
├── .env.example                    # Environment variable template
└── .gitignore                      # Git ignore rules
```

---

## 🚀 Getting Started

### Prerequisites

- **Python 3.10+** with `pip`
- **Flutter SDK 3.x+** ([install guide](https://docs.flutter.dev/get-started/install))
- **Git**
- (Optional) **Docker** for containerized backend deployment

### 1. Clone the Repository

```bash
git clone https://github.com/AdithyaPathakoti/HomeDec.git
cd HomeDec
```

### 2. Backend Setup

```bash
cd backend

# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate        # On Windows: venv\Scripts\activate

# Install dependencies
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
pip install segment-anything-2

# (Optional) Set up environment variables
cp ../.env.example .env
# Edit .env with your Hugging Face token for diffusion refinement

# Start the development server
python main.py
```

The API server will be available at `http://localhost:8000`. Verify with:

```bash
curl http://localhost:8000/health
```

### 3. Frontend Setup

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run on your preferred platform
flutter run                     # Default connected device
flutter run -d chrome           # Web browser
flutter run -d windows          # Windows desktop
```

> **Note:** Update the backend URL in `lib/core/constants.dart` to match your server address (e.g., your machine's local IP for physical devices).

### 4. Docker Deployment (Optional)

```bash
cd backend
docker build -t homedec-backend .
docker run -p 8000:8000 homedec-backend
```

---

## 🔌 API Reference

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Liveness check — returns device, version, and active session count |
| `POST` | `/api/upload` | Upload a room image → runs SAM2 encoder → returns `session_id` |
| `POST` | `/api/interact` | Send point prompts → runs SAM2 decoder → returns PNG overlay |
| `GET` | `/api/session/{id}/mask` | Retrieve the current binary segmentation mask |
| `POST` | `/api/session/mask` | Update mask via manual brush edits → returns new overlay |
| `POST` | `/api/render` | Final render with fabric texture, scale, rotation, and offsets → returns photorealistic PNG |

<details>
<summary><b>Example: Full Workflow via cURL</b></summary>

```bash
# Step 1: Upload a room image
curl -X POST http://localhost:8000/api/upload \
  -F "room_image=@bedroom.jpg" \
  | jq .

# Response: { "session_id": "a1b2c3d4e5f6", "image_width": 1280, ... }

# Step 2: Interactive segmentation (tap on bedsheet)
curl -X POST http://localhost:8000/api/interact \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "a1b2c3d4e5f6",
    "product_category": "bedsheets",
    "points": [{"x": 0.5, "y": 0.6, "label": 1}]
  }' --output overlay.png

# Step 3: Render with a fabric pattern
curl -X POST http://localhost:8000/api/render \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "a1b2c3d4e5f6",
    "fabric_texture_id": "floral",
    "product_category": "bedsheets",
    "tile_scale": 1.2,
    "rotation": -15.0
  }' --output result.png
```

</details>

---

## 🌐 Deployment

The project includes a production-ready configuration for [Render](https://render.com):

- **`render.yaml`** — Infrastructure-as-code manifest for one-click deployment
- **`Dockerfile`** — Multi-stage build with pre-cached model weights to eliminate cold-start latency

```bash
# Deploy to Render
# 1. Push to GitHub
# 2. Connect repository on render.com
# 3. Render auto-detects render.yaml and deploys
```

---

## 🧮 AI Models Used

| Model | Source | Purpose | Size |
|---|---|---|---|
| **SAM 2 Hiera-Tiny** | Meta Research | Interactive object segmentation | ~38 MB |
| **MiDaS Small** | Intel ISL | Monocular depth estimation | ~25 MB |

Both models are automatically downloaded and cached on first server startup. GPU acceleration (CUDA/MPS) is auto-detected when available; CPU fallback is fully supported.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---
