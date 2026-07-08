import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/fabric_item.dart';
import '../core/constants.dart';

class FabricCatalogProvider extends ChangeNotifier {
  Box<FabricItem>? _box;
  FabricCategory _activeFilter = FabricCategory.all;
  String _searchQuery = '';

  // ── Getters ────────────────────────────────────────────────────────────────

  FabricCategory get activeFilter => _activeFilter;
  String get searchQuery => _searchQuery;

  /// All published fabrics (builtins + user-uploaded) after filter & search
  List<FabricItem> get filteredFabrics {
    final all = _allPublished;
    return all.where((f) {
      final matchesFilter = _activeFilter == FabricCategory.all ||
          f.categoryKey == _activeFilter.name;
      final matchesSearch = _searchQuery.isEmpty ||
          f.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          f.material.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesFilter && matchesSearch;
    }).toList();
  }

  /// All user-uploaded fabrics (for admin panel)
  List<FabricItem> get userFabrics {
    if (_box == null) return [];
    return _box!.values.toList();
  }

  List<FabricItem> get _allPublished {
    final builtins = BuiltinFabrics.all.where((f) => f.isPublished).toList();
    final userItems = _box?.values.where((f) => f.isPublished).toList() ?? [];
    return [...builtins, ...userItems];
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FabricItemAdapter());
    }
    _box = await Hive.openBox<FabricItem>(VastraConstants.fabricBoxName);
    notifyListeners();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  void setFilter(FabricCategory filter) {
    _activeFilter = filter;
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  // ── Admin CRUD ─────────────────────────────────────────────────────────────

  Future<void> addFabric({
    required String name,
    required FabricCategory category,
    required String material,
    String sku = '',
    String? origin,
    String? weaveType,
    List<int>? colorTags,
    Uint8List? imageBytes,
    int aiCompatScore = 85,
  }) async {
    if (_box == null) await init();
    final item = FabricItem(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      categoryKey: category.name,
      material: material,
      sku: sku,
      isPublished: true,
      isUserUploaded: true,
      imageBytes: imageBytes?.toList(),
      colorTags: colorTags ?? [],
      aiCompatScore: aiCompatScore,
      origin: origin,
      weaveType: weaveType,
    );
    await _box!.add(item);
    notifyListeners();
  }

  Future<void> updateFabric(FabricItem item, {
    String? name,
    FabricCategory? category,
    String? material,
    String? sku,
    String? origin,
    String? weaveType,
    int? aiCompatScore,
  }) async {
    item.name = name ?? item.name;
    item.categoryKey = category?.name ?? item.categoryKey;
    item.material = material ?? item.material;
    item.sku = sku ?? item.sku;
    item.origin = origin ?? item.origin;
    item.weaveType = weaveType ?? item.weaveType;
    item.aiCompatScore = aiCompatScore ?? item.aiCompatScore;
    await item.save();
    notifyListeners();
  }

  Future<void> togglePublish(FabricItem item) async {
    item.isPublished = !item.isPublished;
    await item.save();
    notifyListeners();
  }

  Future<void> deleteFabric(FabricItem item) async {
    await item.delete();
    notifyListeners();
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  Map<String, int> get categoryBreakdown {
    final result = <String, int>{};
    for (final f in _allPublished) {
      result[f.categoryKey] = (result[f.categoryKey] ?? 0) + 1;
    }
    return result;
  }

  int get totalPublished => _allPublished.length;
  int get totalUserUploaded => _box?.values.where((f) => f.isPublished).length ?? 0;
}
