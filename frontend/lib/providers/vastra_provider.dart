import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
  Uint8List? get resultImageBytes => _finalRenderedResult; // map to avoid breaking screens

  bool get isProcessing => _isProcessing || _status == ProcessingStatus.processing;
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
        final tempFile = File('${tempDir.path}/room_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
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
    notifyListeners();
  }

  /// Uploads room image to /api/upload to initialize session_id
  Future<void> uploadSessionImage() async {
    if (_roomImageFile == null) throw Exception('No room image available.');
    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Uploading and encoding room image...';
    _errorMessage = null;
    notifyListeners();

    try {
      final sessionId = await ApiService.instance.uploadRoomImage(_roomImageFile!);
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
  Future<void> addInteractiveTap(double x, double y) async {
    if (_currentSessionId == null) {
      await uploadSessionImage();
    }

    final label = _isPositiveSelectionMode ? 1 : 0;
    _interactivePoints.add({'x': x, 'y': y, 'label': label});

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

  /// Clears interaction points and the live overlay preview
  void resetTaps() {
    _interactivePoints.clear();
    _maskPreviewOverlay = null;
    _errorMessage = null;
    _statusMessage = 'Cleared points.';
    notifyListeners();
  }

  /// Calls /api/render to project the fabric texture onto the segmented mask
  Future<void> renderFinal(String fabricTextureId, {Uint8List? customFabricBytes}) async {
    if (_currentSessionId == null) throw Exception('No active session. Please segment the room first.');
    _isProcessing = true;
    _status = ProcessingStatus.processing;
    _statusMessage = 'Rendering fabric texture projection...';
    _errorMessage = null;
    _finalRenderedResult = null;
    notifyListeners();

    try {
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
    if (_roomImageFile == null) return;
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
        await renderFinal('custom_fabric', customFabricBytes: _fabricImageBytes);
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
    notifyListeners();
  }
}
