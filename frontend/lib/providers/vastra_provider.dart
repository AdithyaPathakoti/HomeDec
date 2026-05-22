import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/product_category.dart';
import '../services/api_service.dart';

enum ProcessingStatus { idle, processing, done, error }

class VastraProvider extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  Uint8List? _roomImageBytes;
  ProductCategoryData? _selectedProduct;
  Uint8List? _fabricImageBytes;
  ProcessingStatus _status = ProcessingStatus.idle;
  String _statusMessage = '';
  Uint8List? _resultImageBytes;
  String? _errorMessage;

  // ── Getters ────────────────────────────────────────────────────────────────
  Uint8List? get roomImageBytes => _roomImageBytes;
  ProductCategoryData? get selectedProduct => _selectedProduct;
  Uint8List? get fabricImageBytes => _fabricImageBytes;
  ProcessingStatus get status => _status;
  String get statusMessage => _statusMessage;
  Uint8List? get resultImageBytes => _resultImageBytes;
  String? get errorMessage => _errorMessage;

  bool get isProcessing => _status == ProcessingStatus.processing;
  bool get canGenerate =>
      _roomImageBytes != null &&
      _selectedProduct != null &&
      _fabricImageBytes != null;

  // ── Setters ────────────────────────────────────────────────────────────────
  void setRoomImage(Uint8List bytes) {
    _roomImageBytes = bytes;
    // Clear any previous result when a new room is selected
    _resultImageBytes = null;
    _status = ProcessingStatus.idle;
    _errorMessage = null;
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

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Calls the backend API to generate the redesigned room image.
  Future<void> generate() async {
    if (!canGenerate) return;

    _status = ProcessingStatus.processing;
    _statusMessage = 'Initializing AI pipeline...';
    _errorMessage = null;
    _resultImageBytes = null;
    notifyListeners();

    try {
      final resultBytes = await ApiService.instance.generateFabric(
        roomImageBytes: _roomImageBytes!,
        productCategory: _selectedProduct!.apiKey,
        fabricImageBytes: _fabricImageBytes!,
      );

      _resultImageBytes = resultBytes;
      _status = ProcessingStatus.done;
      _statusMessage = 'Generation complete!';
    } catch (e) {
      _errorMessage = e.toString();
      _status = ProcessingStatus.error;
      _statusMessage = 'Generation failed.';
    }

    notifyListeners();
  }

  /// Resets the entire flow back to the initial state.
  void reset() {
    _roomImageBytes = null;
    _selectedProduct = null;
    _fabricImageBytes = null;
    _resultImageBytes = null;
    _errorMessage = null;
    _status = ProcessingStatus.idle;
    _statusMessage = '';
    notifyListeners();
  }

  /// Clears only the result and fabric so the user can try a different fabric
  /// without re-uploading the room image or re-selecting the product.
  void resetForNewFabric() {
    _fabricImageBytes = null;
    _resultImageBytes = null;
    _errorMessage = null;
    _status = ProcessingStatus.idle;
    _statusMessage = '';
    notifyListeners();
  }
}
