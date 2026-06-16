import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/product_category.dart';
import '../services/api_service.dart';

enum ProcessingStatus { idle, processing, done, error }

class VastraProvider extends ChangeNotifier {
  // ── State variables ────────────────────────────────────────────────────────
  Uint8List? _roomImageBytes;
  File? _roomImageFile;
  double _roomImageAspectRatio = 1.0;

  ProductCategoryData? _selectedProduct;
  Uint8List? _fabricImageBytes;

  ProcessingStatus _status = ProcessingStatus.idle;
  String _statusMessage = '';
  String? _errorMessage;

  String? _currentSessionId;
  final List<Map<String, dynamic>> _interactivePoints = [];
  bool _isPositiveSelectionMode = true;
  Uint8List? _maskPreviewOverlay;
  Uint8List? _finalRenderedResult;
  bool _isProcessing = false;

  bool _isBrushMode = false;
  bool _isBrushAdd = true;
  double _brushSize = 25.0;
  Uint8List? _localMaskBytes;
  bool _refineWithDiffusion = false;

  double _tileScale = 1.0;
  double _rotation = 0.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  String? _lastFabricTextureId;
  Uint8List? _lastCustomFabricBytes;

  // ── Getters ────────────────────────────────────────────────────────────────
  Uint8List? get roomImageBytes => _roomImageBytes;
  File? get roomImageFile => _roomImageFile;
  double get roomImageAspectRatio => _roomImageAspectRatio;

  ProductCategoryData? get selectedProduct => _selectedProduct;
  Uint8List? get fabricImageBytes => _fabricImageBytes;

  ProcessingStatus get status => _status;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  String? get currentSessionId => _currentSessionId;
  List<Map<String, dynamic>> get interactivePoints => _interactivePoints;
  bool get isPositiveSelectionMode => _isPositiveSelectionMode;
  Uint8List? get maskPreviewOverlay => _maskPreviewOverlay;
  Uint8List? get finalRenderedResult => _finalRenderedResult;
  Uint8List? get resultImageBytes =>
      _finalRenderedResult; // map to avoid breaking screens

  bool get isBrushMode => _isBrushMode;
  bool get isBrushAdd => _isBrushAdd;
  double get brushSize => _brushSize;
  Uint8List? get localMaskBytes => _localMaskBytes;
  bool get refineWithDiffusion => _refineWithDiffusion;

  double get tileScale => _tileScale;
  double get rotation => _rotation;
  double get offsetX => _offsetX;
  double get offsetY => _offsetY;
  String? get lastFabricTextureId => _lastFabricTextureId;
  Uint8List? get lastCustomFabricBytes => _lastCustomFabricBytes;

  bool get isProcessing =>
      _isProcessing || _status == ProcessingStatus.processing;
  bool get canGenerate =>
      _roomImageBytes != null &&
      _selectedProduct != null &&
      _fabricImageBytes != null;

  // ── Setters ────────────────────────────────────────────────────────────────

  /// Sets the uploaded room image, saves it to a temporary file if no File object
  /// is passed, and decodes the aspect ratio in the background.
  void setRoomImage(Uint8List bytes, {File? file}) {
    _roomImageBytes = bytes;
    if (file != null) {
      _roomImageFile = file;
    } else {
      try {
        final tempDir = Directory.systemTemp;
        final tempFile = File(
            '${tempDir.path}/room_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
        tempFile.writeAsBytesSync(bytes);
        _roomImageFile = tempFile;
      } catch (e) {
        if (kDebugMode) print('Failed to write temp room image file: $e');
      }
    }

    // Decode image aspect ratio in the background
    ui.decodeImageFromList(bytes, (ui.Image img) {
      _roomImageAspectRatio = img.width / img.height;
      notifyListeners();
    });

    _finalRenderedResult = null;
    _currentSessionId = null;
    _interactivePoints.clear();
    _maskPreviewOverlay = null;
    _status = ProcessingStatus.idle;
    _errorMessage = null;
    _statusMessage = '';
    notifyListeners();
  }

  void setSelectedProduct(ProductCategoryData product) {
    _selectedProduct = product;
    notifyListeners();
  }

  void setFabricImage(Uint8List bytes) {
    _fabricImageBytes = bytes;
    notifyListeners();
  }

  void clearFabricImage() {
    _fabricImageBytes = null;
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isPositiveSelectionMode = !_isPositiveSelectionMode;
    notifyListeners();
  }

  // ── Decoupled Session Lifecycle Operations ─────────────────────────────────

  /// Resets points, session ID, and preview image tokens
  void clearSession() {
    _interactivePoints.clear();
    _currentSessionId = null;
    _maskPreviewOverlay = null;
    _finalRenderedResult = null;
    _status = ProcessingStatus.idle;
    _errorMessage = null;
    _statusMessage = '';
    _isProcessing = false;
    _isBrushMode = false;
    _localMaskBytes = null;
    _refineWithDiffusion = false;
    _lastFabricTextureId = null;
    _lastCustomFabricBytes = null;
    resetPlacement();
    notifyListeners();
  }

  /// Uploads room image to /api/upload to initialize session_id
  Future<void> uploadSessionImage() async {
    if (_roomImageBytes == null) throw Exception('No room image available.');
    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Uploading and encoding room image...';
    _errorMessage = null;
    notifyListeners();

    try {
      final sessionId = await ApiService.instance.uploadRoomImage(
        _roomImageBytes!,
        'room_image.jpg',
      );
      _currentSessionId = sessionId;
      _status = ProcessingStatus.idle;
      _statusMessage = 'Room uploaded.';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Upload failed.';
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Adds a normalized tap to the points list and calls /api/interact
  /// Submits the current list of interaction points to the backend API.
  Future<void> _updateInteractiveTaps() async {
    if (_currentSessionId == null) return;

    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Segmenting interactive prompt...';
    _errorMessage = null;
    notifyListeners();

    try {
      final category = _selectedProduct?.apiKey ?? 'bedsheets';
      final overlayBytes = await ApiService.instance.sendInteractiveTap(
        sessionId: _currentSessionId!,
        productCategory: category,
        points: _interactivePoints,
      );
      _maskPreviewOverlay = overlayBytes;
      _status = ProcessingStatus.done;
      _statusMessage = 'Interactive update complete.';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Interaction failed.';
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Adds a normalized tap to the points list and calls /api/interact
  Future<void> addInteractiveTap(double x, double y) async {
    if (_currentSessionId == null) {
      await uploadSessionImage();
    }

    final label = _isPositiveSelectionMode ? 1 : 0;
    _interactivePoints.add({'x': x, 'y': y, 'label': label});
    await _updateInteractiveTaps();
  }

  /// Removes a tap at a specific index and calls /api/interact to update mask
  Future<void> removeInteractiveTapAt(int index) async {
    if (index < 0 || index >= _interactivePoints.length) return;
    _interactivePoints.removeAt(index);
    if (_interactivePoints.isEmpty) {
      _maskPreviewOverlay = null;
      _errorMessage = null;
      _statusMessage = 'Cleared points.';
      notifyListeners();
    } else {
      await _updateInteractiveTaps();
    }
  }

  /// Removes the last placed tap and calls /api/interact to update mask
  Future<void> undoLastTap() async {
    if (_interactivePoints.isEmpty) return;
    _interactivePoints.removeLast();
    if (_interactivePoints.isEmpty) {
      _maskPreviewOverlay = null;
      _errorMessage = null;
      _statusMessage = 'Cleared points.';
      notifyListeners();
    } else {
      await _updateInteractiveTaps();
    }
  }

  void setBrushAdd(bool val) {
    _isBrushAdd = val;
    notifyListeners();
  }

  void setBrushSize(double val) {
    _brushSize = val;
    notifyListeners();
  }

  void toggleDiffusionRefinement() {
    _refineWithDiffusion = !_refineWithDiffusion;
    notifyListeners();
  }

  void setTileScale(double val) {
    _tileScale = val;
    notifyListeners();
  }

  void setRotation(double val) {
    _rotation = val;
    notifyListeners();
  }

  void setOffsetX(double val) {
    _offsetX = val;
    notifyListeners();
  }

  void setOffsetY(double val) {
    _offsetY = val;
    notifyListeners();
  }

  void resetPlacement() {
    _tileScale = 1.0;
    _rotation = 0.0;
    _offsetX = 0.0;
    _offsetY = 0.0;
  }

  Future<void> toggleBrushMode() async {
    _isBrushMode = !_isBrushMode;
    if (_isBrushMode && _currentSessionId != null) {
      await fetchMask();
    }
    notifyListeners();
  }

  /// Downloads the current binary mask from the backend.
  Future<void> fetchMask() async {
    if (_currentSessionId == null) return;
    try {
      final bytes = await ApiService.instance.fetchMask(_currentSessionId!);
      _localMaskBytes = bytes;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error fetching mask: $e');
    }
  }

  /// Renders user drawing/paint strokes on the local binary mask.
  Future<void> applyPaintStrokes(List<Offset> points, bool isAdd, double brushSize, double canvasWidth, double canvasHeight) async {
    if (_localMaskBytes == null) return;
    
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(_localMaskBytes!);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final maskImage = frame.image;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..color = isAdd ? const Color(0xFFFFFFFF) : const Color(0xFF000000)
        ..strokeWidth = brushSize * (maskImage.width / canvasWidth) // Scale stroke size to native resolution
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
        
      // Draw original mask image at its native size
      canvas.drawImage(maskImage, Offset.zero, Paint());
      
      // Scale coordinates from canvas space to native image space
      final double scaleX = maskImage.width / canvasWidth;
      final double scaleY = maskImage.height / canvasHeight;
      
      if (points.length > 1) {
        final path = Path();
        path.moveTo(points.first.dx * scaleX, points.first.dy * scaleY);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx * scaleX, points[i].dy * scaleY);
        }
        canvas.drawPath(path, paint);
      } else if (points.length == 1) {
        canvas.drawCircle(
          Offset(points.first.dx * scaleX, points.first.dy * scaleY),
          (brushSize * scaleX) / 2,
          Paint()..color = paint.color,
        );
      }
      
      final picture = recorder.endRecording();
      final outputImg = await picture.toImage(maskImage.width, maskImage.height);
      final byteData = await outputImg.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        _localMaskBytes = byteData.buffer.asUint8List();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('Error applying paint strokes: $e');
    }
  }

  /// Sends the modified local binary mask to the backend to sync and get new preview overlay.
  Future<void> uploadLocalMask() async {
    if (_currentSessionId == null || _localMaskBytes == null) return;
    
    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Updating mask corrections...';
    notifyListeners();
    
    try {
      final base64Mask = base64.encode(_localMaskBytes!);
      final overlayBytes = await ApiService.instance.updateSessionMask(
        sessionId: _currentSessionId!,
        base64Mask: base64Mask,
      );
      _maskPreviewOverlay = overlayBytes;
      _status = ProcessingStatus.done;
      _statusMessage = 'Corrections updated.';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Correction update failed.';
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Clears interaction points and the live overlay preview
  void resetTaps() {
    _interactivePoints.clear();
    _maskPreviewOverlay = null;
    _errorMessage = null;
    _statusMessage = 'Cleared points.';
    notifyListeners();
  }

  /// Calls /api/render to project the fabric texture onto the segmented mask
  Future<void> renderFinal(String fabricTextureId,
      {Uint8List? customFabricBytes}) async {
    if (_currentSessionId == null)
      throw Exception('No active session. Please segment the room first.');
    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Rendering fabric texture projection...';
    _errorMessage = null;
    _finalRenderedResult = null;
    notifyListeners();

    try {
      _lastFabricTextureId = fabricTextureId;
      _lastCustomFabricBytes = customFabricBytes;

      final category = _selectedProduct?.apiKey ?? 'bedsheets';
      String? base64Fabric;
      if (customFabricBytes != null) {
        base64Fabric = base64.encode(customFabricBytes);
      }
      final result = await ApiService.instance.renderFinalFabric(
        sessionId: _currentSessionId!,
        fabricTextureId: fabricTextureId,
        productCategory: category,
        fabricImageBase64: base64Fabric,
        refineWithDiffusion: _refineWithDiffusion,
        tileScale: _tileScale,
        rotation: _rotation,
        offsetX: _offsetX,
        offsetY: _offsetY,
      );
      _finalRenderedResult = result;
      _status = ProcessingStatus.done;
      _statusMessage = 'Rendering complete.';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Rendering failed.';
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // ── Actions (Backward Compatibility & Fallbacks) ───────────────────────────

  /// Mock generate method representing a single-step run (uploads and renders).
  /// Included to prevent crashes or compile errors if called from older code.
  Future<void> generate() async {
    if (_roomImageBytes == null) return;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Processing image...';
    _errorMessage = null;
    _finalRenderedResult = null;
    notifyListeners();

    try {
      // Step 1: Upload
      await uploadSessionImage();

      // Step 2: Simulate interactive tap in center of constraints to segment
      await addInteractiveTap(0.5, 0.5);

      // Step 3: Render using selected fabric
      if (_fabricImageBytes != null) {
        await renderFinal('custom_fabric',
            customFabricBytes: _fabricImageBytes);
      } else {
        await renderFinal('bedsheet_pattern_1');
      }

      _status = ProcessingStatus.done;
      _statusMessage = 'Done.';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Processing failed.';
    }
    notifyListeners();
  }

  /// Resets the entire flow back to the initial state.
  void reset() {
    _roomImageBytes = null;
    _roomImageFile = null;
    _selectedProduct = null;
    _fabricImageBytes = null;
    clearSession();
  }

  /// Clears only the result and fabric so the user can try a different fabric
  /// without re-uploading the room image or re-selecting the product.
  void resetForNewFabric() {
    _fabricImageBytes = null;
    _finalRenderedResult = null;
    _errorMessage = null;
    _status = ProcessingStatus.idle;
    _statusMessage = '';
    _lastFabricTextureId = null;
    _lastCustomFabricBytes = null;
    resetPlacement();
    notifyListeners();
  }
}
