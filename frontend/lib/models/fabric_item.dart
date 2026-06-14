import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'fabric_item.g.dart';

// ── Fabric Category Enum ───────────────────────────────────────────────────────
enum FabricCategory {
  all,
  floral,
  velvet,
  cotton,
  silk,
  geometric,
  luxury,
  traditional,
  striped,
  textured,
  printed,
  minimalist,
}

extension FabricCategoryX on FabricCategory {
  String get label {
    switch (this) {
      case FabricCategory.all:
        return 'All';
      case FabricCategory.floral:
        return 'Floral';
      case FabricCategory.velvet:
        return 'Velvet';
      case FabricCategory.cotton:
        return 'Cotton';
      case FabricCategory.silk:
        return 'Silk';
      case FabricCategory.geometric:
        return 'Geometric';
      case FabricCategory.luxury:
        return 'Luxury';
      case FabricCategory.traditional:
        return 'Traditional';
      case FabricCategory.striped:
        return 'Striped';
      case FabricCategory.textured:
        return 'Textured';
      case FabricCategory.printed:
        return 'Printed';
      case FabricCategory.minimalist:
        return 'Minimalist';
    }
  }
}

// ── Fabric Item Model ─────────────────────────────────────────────────────────

@HiveType(typeId: 0)
class FabricItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String categoryKey; // FabricCategory.name string

  @HiveField(3)
  String material;

  @HiveField(4)
  String sku;

  @HiveField(5)
  bool isPublished;

  @HiveField(6)
  bool isUserUploaded;

  @HiveField(7)
  String? assetPath; // For bundled fabrics: 'assets/fabrics/velvet_blue.jpg'

  @HiveField(8)
  List<int>? imageBytes; // For user-uploaded fabrics stored locally

  @HiveField(9)
  List<int> colorTags; // Packed ARGB color integers for swatch dots

  @HiveField(10)
  int aiCompatScore; // 0–100

  @HiveField(11)
  String? origin; // e.g. "India", "Italy"

  @HiveField(12)
  String? weaveType; // e.g. "Plain", "Twill", "Satin"

  FabricItem({
    required this.id,
    required this.name,
    required this.categoryKey,
    this.material = '',
    this.sku = '',
    this.isPublished = true,
    this.isUserUploaded = false,
    this.assetPath,
    this.imageBytes,
    this.colorTags = const [],
    this.aiCompatScore = 85,
    this.origin,
    this.weaveType,
  });

  FabricCategory get category {
    return FabricCategory.values.firstWhere(
      (c) => c.name == categoryKey,
      orElse: () => FabricCategory.all,
    );
  }

  FabricItem copyWith({
    String? name,
    String? categoryKey,
    String? material,
    String? sku,
    bool? isPublished,
    List<int>? colorTags,
    int? aiCompatScore,
    String? origin,
    String? weaveType,
  }) {
    return FabricItem(
      id: id,
      name: name ?? this.name,
      categoryKey: categoryKey ?? this.categoryKey,
      material: material ?? this.material,
      sku: sku ?? this.sku,
      isPublished: isPublished ?? this.isPublished,
      isUserUploaded: isUserUploaded,
      assetPath: assetPath,
      imageBytes: imageBytes,
      colorTags: colorTags ?? this.colorTags,
      aiCompatScore: aiCompatScore ?? this.aiCompatScore,
      origin: origin ?? this.origin,
      weaveType: weaveType ?? this.weaveType,
    );
  }
}

// ── Bundled (Built-in) Fabric Catalog ─────────────────────────────────────────
// These are sample fabrics bundled with the app as asset images.
// They are shown in the catalog but not stored in Hive (they're always available).

class BuiltinFabrics {
  BuiltinFabrics._();

  static final List<FabricItem> all = [
    FabricItem(
      id: 'builtin_001',
      name: 'Rose Garden Floral',
      categoryKey: FabricCategory.floral.name,
      material: 'Cotton',
      sku: 'VAS-FL-001',
      assetPath: 'assets/fabrics/floral.jpg',
      colorTags: [
        Colors.pink.shade300.value,
        Colors.green.shade300.value,
        Colors.white.value
      ],
      aiCompatScore: 94,
      origin: 'India',
      weaveType: 'Plain',
    ),
    FabricItem(
      id: 'builtin_002',
      name: 'Midnight Velvet',
      categoryKey: FabricCategory.velvet.name,
      material: 'Velvet',
      sku: 'VAS-VL-001',
      assetPath: 'assets/fabrics/velvet.jpg',
      colorTags: [const Color(0xFF1A0A2E).value, const Color(0xFF3D1566).value],
      aiCompatScore: 91,
      origin: 'Italy',
      weaveType: 'Pile',
    ),
    FabricItem(
      id: 'builtin_003',
      name: 'Desert Stripe',
      categoryKey: FabricCategory.striped.name,
      material: 'Cotton Linen',
      sku: 'VAS-ST-001',
      assetPath: 'assets/fabrics/velvet.jpg',
      colorTags: [
        const Color(0xFFE8C88A).value,
        const Color(0xFFC4956A).value,
        Colors.white.value
      ],
      aiCompatScore: 88,
      origin: 'Morocco',
      weaveType: 'Twill',
    ),
    FabricItem(
      id: 'builtin_004',
      name: 'Azure Geometric',
      categoryKey: FabricCategory.geometric.name,
      material: 'Polyester',
      sku: 'VAS-GE-001',
      assetPath: 'assets/fabrics/velvet.jpg',
      colorTags: [
        const Color(0xFF1E6FA8).value,
        Colors.white.value,
        const Color(0xFF0D3D5E).value
      ],
      aiCompatScore: 92,
      origin: 'Turkey',
      weaveType: 'Jacquard',
    ),
    FabricItem(
      id: 'builtin_005',
      name: 'Ivory Silk',
      categoryKey: FabricCategory.silk.name,
      material: 'Silk',
      sku: 'VAS-SK-001',
      assetPath: 'assets/fabrics/luxury_white.jpg',
      colorTags: [const Color(0xFFF5F0EB).value, const Color(0xFFE8DDD0).value],
      aiCompatScore: 96,
      origin: 'China',
      weaveType: 'Satin',
    ),
    FabricItem(
      id: 'builtin_006',
      name: 'Terracotta Cotton',
      categoryKey: FabricCategory.cotton.name,
      material: 'Cotton',
      sku: 'VAS-CO-001',
      assetPath: 'assets/fabrics/floral.jpg',
      colorTags: [const Color(0xFFC17A50).value, const Color(0xFFE8A878).value],
      aiCompatScore: 90,
      origin: 'India',
      weaveType: 'Plain',
    ),
    FabricItem(
      id: 'builtin_007',
      name: 'Royal Damask',
      categoryKey: FabricCategory.luxury.name,
      material: 'Silk Blend',
      sku: 'VAS-LX-001',
      assetPath: 'assets/fabrics/luxury_white.jpg',
      colorTags: [const Color(0xFF6B1A1A).value, const Color(0xFFE8C060).value],
      aiCompatScore: 97,
      origin: 'Italy',
      weaveType: 'Damask',
    ),
    FabricItem(
      id: 'builtin_008',
      name: 'Sage Linen',
      categoryKey: FabricCategory.minimalist.name,
      material: 'Linen',
      sku: 'VAS-MN-001',
      assetPath: 'assets/fabrics/luxury_white.jpg',
      colorTags: [const Color(0xFF8FAF8A).value, const Color(0xFFD4E0D0).value],
      aiCompatScore: 89,
      origin: 'Belgium',
      weaveType: 'Plain',
    ),
    FabricItem(
      id: 'builtin_009',
      name: 'Paisley Tradition',
      categoryKey: FabricCategory.traditional.name,
      material: 'Silk Cotton',
      sku: 'VAS-TR-001',
      assetPath: 'assets/fabrics/floral.jpg',
      colorTags: [
        const Color(0xFF8B3A3A).value,
        const Color(0xFFE8A840).value,
        const Color(0xFF2A5A3A).value
      ],
      aiCompatScore: 93,
      origin: 'India',
      weaveType: 'Jacquard',
    ),
    FabricItem(
      id: 'builtin_010',
      name: 'Navy Herringbone',
      categoryKey: FabricCategory.textured.name,
      material: 'Wool Blend',
      sku: 'VAS-TX-001',
      assetPath: 'assets/fabrics/velvet.jpg',
      colorTags: [
        const Color(0xFF1A1A3E).value,
        const Color(0xFF2E3F6E).value,
        const Color(0xFFD4C5B0).value
      ],
      aiCompatScore: 87,
      origin: 'UK',
      weaveType: 'Herringbone',
    ),
    FabricItem(
      id: 'builtin_011',
      name: 'Blush Floral Print',
      categoryKey: FabricCategory.printed.name,
      material: 'Cotton',
      sku: 'VAS-PR-001',
      assetPath: 'assets/fabrics/floral.jpg',
      colorTags: [
        const Color(0xFFF0C0C0).value,
        const Color(0xFFC8A0B0).value,
        Colors.white.value
      ],
      aiCompatScore: 91,
      origin: 'India',
      weaveType: 'Plain',
    ),
    FabricItem(
      id: 'builtin_012',
      name: 'Emerald Velvet',
      categoryKey: FabricCategory.velvet.name,
      material: 'Velvet',
      sku: 'VAS-VL-002',
      assetPath: 'assets/fabrics/velvet.jpg',
      colorTags: [const Color(0xFF0D4A2A).value, const Color(0xFF1A7A48).value],
      aiCompatScore: 95,
      origin: 'Italy',
      weaveType: 'Pile',
    ),
  ];
}
