import 'package:flutter/material.dart';

enum ProductCategory {
  bedsheets,
  curtains,
  sofaCovers,
  pillows,
  carpets,
}

class ProductCategoryData {
  final ProductCategory category;
  final String label;
  final String description;
  final IconData icon;

  /// Value sent to the backend as the `product_category` form field.
  final String apiKey;

  const ProductCategoryData({
    required this.category,
    required this.label,
    required this.description,
    required this.icon,
    required this.apiKey,
  });

  static const List<ProductCategoryData> all = [
    ProductCategoryData(
      category: ProductCategory.bedsheets,
      label: 'Bedsheets',
      description: 'Transform bed linen & covers',
      icon: Icons.bed_rounded,
      apiKey: 'bedsheets',
    ),
    ProductCategoryData(
      category: ProductCategory.curtains,
      label: 'Curtains',
      description: 'Redesign window drapery',
      icon: Icons.curtains_rounded,
      apiKey: 'curtains',
    ),
    ProductCategoryData(
      category: ProductCategory.sofaCovers,
      label: 'Sofa Covers',
      description: 'Reimagine sofa upholstery',
      icon: Icons.chair_rounded,
      apiKey: 'sofa_covers',
    ),
    ProductCategoryData(
      category: ProductCategory.pillows,
      label: 'Pillows',
      description: 'Refresh pillow fabrics',
      icon: Icons.king_bed_outlined,
      apiKey: 'pillows',
    ),
    ProductCategoryData(
      category: ProductCategory.carpets,
      label: 'Carpets',
      description: 'Revamp floor coverings',
      icon: Icons.texture_rounded,
      apiKey: 'carpets',
    ),
  ];
}
