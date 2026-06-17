import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/fabric_item.dart';
import '../providers/fabric_catalog_provider.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FabricCatalogProvider>().init();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildAnalyticsBanner(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _CatalogTab(),
                  _AddFabricTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tabCtrl.animateTo(1),
        backgroundColor: VastraColors.ivory,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: VastraColors.border),
        ),
        icon: const Icon(Icons.add_rounded, color: VastraColors.background),
        label: const Text(
          'Add Fabric',
          style: TextStyle(
            color: VastraColors.background,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: VastraColors.ivory, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Panel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Fabric Catalog Management',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: VastraColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: VastraColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VastraColors.border, width: 1.0),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                size: 18, color: VastraColors.ivory),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsBanner() {
    return Consumer<FabricCatalogProvider>(
      builder: (_, catalog, __) => Padding(
        padding: const EdgeInsets.fromLTRB(VastraConstants.pagePadding, 16, VastraConstants.pagePadding, 0),
        child: Row(
          children: [
            _StatChip(
              label: 'Total Published',
              value: '${catalog.totalPublished}',
              icon: Icons.texture_rounded,
            ),
            const SizedBox(width: 10),
            _StatChip(
              label: 'User Uploaded',
              value: '${catalog.totalUserUploaded}',
              icon: Icons.upload_rounded,
            ),
            const SizedBox(width: 10),
            _StatChip(
              label: 'Categories',
              value: '${catalog.categoryBreakdown.keys.length}',
              icon: Icons.category_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VastraConstants.pagePadding, 16, VastraConstants.pagePadding, 0),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: VastraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VastraColors.border),
        ),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: VastraColors.ivory,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: VastraColors.background,
          unselectedLabelColor: VastraColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter'),
          tabs: const [
            Tab(text: 'Fabric Catalog'),
            Tab(text: 'Add New Fabric'),
          ],
        ),
      ),
    );
  }
}

// ── Catalog Tab ───────────────────────────────────────────────────────────────

class _CatalogTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<FabricCatalogProvider>(
      builder: (_, catalog, __) {
        final items = catalog.userFabrics;
        final builtins = BuiltinFabrics.all;

        return ListView(
          padding: const EdgeInsets.fromLTRB(
              VastraConstants.pagePadding, 16, VastraConstants.pagePadding, 80),
          children: [
            _SectionHeader(
                title: 'Built-in Fabrics',
                subtitle: '${builtins.length} bundled fabrics'),
            const SizedBox(height: 10),
            ...builtins.map((f) => _FabricAdminTile(
                  item: f,
                  isBuiltin: true,
                  onToggle: null,
                  onDelete: null,
                )),

            if (items.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionHeader(
                  title: 'Your Uploaded Fabrics',
                  subtitle: '${items.length} fabrics'),
              const SizedBox(height: 10),
              ...items.map((f) => _FabricAdminTile(
                    item: f,
                    isBuiltin: false,
                    onToggle: () => catalog.togglePublish(f),
                    onDelete: () => _confirmDelete(context, catalog, f),
                  )),
            ] else ...[
              const SizedBox(height: 20),
              _EmptyUploads(),
            ],
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, FabricCatalogProvider catalog, FabricItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VastraColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete "${item.name}"?',
            style: const TextStyle(color: VastraColors.ivory, fontSize: 15, fontFamily: 'Inter', fontWeight: FontWeight.bold)),
        content: Text(
          'This fabric will be permanently removed from your catalog.',
          style: TextStyle(color: VastraColors.textSecondary, fontSize: 13, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: VastraColors.textSecondary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await catalog.deleteFabric(item);
    }
  }
}

// ── Add Fabric Tab ────────────────────────────────────────────────────────────

class _AddFabricTab extends StatefulWidget {
  @override
  State<_AddFabricTab> createState() => _AddFabricTabState();
}

class _AddFabricTabState extends State<_AddFabricTab> {
  final _nameCtrl = TextEditingController();
  final _materialCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  FabricCategory _selectedCategory = FabricCategory.cotton;
  Uint8List? _imageBytes;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _materialCtrl.dispose();
    _skuCtrl.dispose();
    _originCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty || _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a name and image')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await context.read<FabricCatalogProvider>().addFabric(
            name: _nameCtrl.text.trim(),
            category: _selectedCategory,
            material: _materialCtrl.text.trim(),
            sku: _skuCtrl.text.trim(),
            origin: _originCtrl.text.trim().isEmpty ? null : _originCtrl.text.trim(),
            imageBytes: _imageBytes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fabric added to catalog ✓'),
        ),
      );
      // Reset form
      _nameCtrl.clear();
      _materialCtrl.clear();
      _skuCtrl.clear();
      _originCtrl.clear();
      setState(() {
        _imageBytes = null;
        _selectedCategory = FabricCategory.cotton;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(VastraConstants.pagePadding, 20, VastraConstants.pagePadding, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(label: 'Fabric Image *'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: VastraColors.surfaceElevated,
                border: Border.all(
                  color: _imageBytes != null ? VastraColors.ivory : VastraColors.border,
                  width: 1.0,
                ),
              ),
              child: _imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_imageBytes!, fit: BoxFit.cover),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _imageBytes = null),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: VastraColors.ivory,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: VastraColors.background,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Inter')),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded,
                            size: 32, color: VastraColors.textSecondary),
                        const SizedBox(height: 8),
                        Text('Tap to upload fabric image',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: VastraColors.textSecondary,
                                )),
                        const SizedBox(height: 4),
                        Text('JPG, PNG — max 1024×1024',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 20),

          const _SectionLabel(label: 'Fabric Name *'),
          const SizedBox(height: 8),
          _TextField(controller: _nameCtrl, hint: 'e.g. Rose Garden Floral'),

          const SizedBox(height: 16),

          const _SectionLabel(label: 'Category'),
          const SizedBox(height: 8),
          _CategoryDropdown(
            value: _selectedCategory,
            onChanged: (v) => setState(() => _selectedCategory = v!),
          ),

          const SizedBox(height: 16),

          const _SectionLabel(label: 'Material'),
          const SizedBox(height: 8),
          _TextField(controller: _materialCtrl, hint: 'e.g. Cotton, Velvet, Silk'),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(label: 'Origin'),
                    const SizedBox(height: 8),
                    _TextField(controller: _originCtrl, hint: 'e.g. India'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(label: 'SKU'),
                    const SizedBox(height: 8),
                    _TextField(controller: _skuCtrl, hint: 'VAS-FL-001'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          GestureDetector(
            onTap: _isSaving ? null : _save,
            child: Container(
              height: 52,
              decoration: VastraTheme.goldDecoration(borderRadius: 12),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: VastraColors.background),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              color: VastraColors.background, size: 18),
                          SizedBox(width: 6),
                          Text('Add to Catalog',
                              style: TextStyle(
                                    color: VastraColors.background,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                  )),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: VastraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VastraColors.border, width: 1.0),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: VastraColors.ivory),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(color: VastraColors.ivory, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
            Text(label,
                style: const TextStyle(color: VastraColors.textSecondary, fontSize: 9.5, fontFamily: 'Inter'),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: VastraColors.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: VastraColors.border),
          ),
          child: Text(subtitle,
              style: const TextStyle(
                  color: VastraColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter')),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: VastraColors.textSecondary,
            ));
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _TextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VastraColors.border, width: 1.0),
      ),
      child: TextField(
        controller: controller,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: VastraColors.ivory),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: VastraColors.textMuted, fontSize: 13, fontFamily: 'Inter'),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final FabricCategory value;
  final ValueChanged<FabricCategory?> onChanged;

  const _CategoryDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VastraColors.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: DropdownButton<FabricCategory>(
        value: value,
        isExpanded: true,
        dropdownColor: VastraColors.surfaceElevated,
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: VastraColors.textSecondary),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: VastraColors.ivory),
        items: FabricCategory.values
            .where((c) => c != FabricCategory.all)
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c.label),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _FabricAdminTile extends StatelessWidget {
  final FabricItem item;
  final bool isBuiltin;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  const _FabricAdminTile({
    required this.item,
    required this.isBuiltin,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VastraColors.border, width: 1.0),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: item.assetPath != null
                  ? Image.asset(item.assetPath!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            color: VastraColors.border,
                            child: const Icon(Icons.texture_rounded,
                                size: 18, color: VastraColors.textMuted),
                          ))
                  : item.imageBytes != null
                      ? Image.memory(
                          Uint8List.fromList(item.imageBytes!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: VastraColors.border,
                          child: const Icon(Icons.texture_rounded,
                              size: 18, color: VastraColors.textMuted),
                        ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                    '${item.category.label} · ${item.material}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: VastraColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (isBuiltin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: VastraColors.surfaceElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: VastraColors.border),
              ),
              child: const Text('Built-in',
                  style: TextStyle(
                      color: VastraColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w500, fontFamily: 'Inter')),
            )
          else ...[
            Switch(
              value: item.isPublished,
              onChanged: (_) => onToggle?.call(),
              activeColor: VastraColors.ivory,
              activeTrackColor: VastraColors.border,
              inactiveThumbColor: VastraColors.textSecondary,
              inactiveTrackColor: VastraColors.background,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: Colors.redAccent),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyUploads extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VastraColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VastraColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 32, color: VastraColors.textMuted),
          const SizedBox(height: 12),
          Text('No fabrics uploaded yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: VastraColors.textMuted)),
          const SizedBox(height: 6),
          Text('Use the "Add New Fabric" tab to upload your fabric images',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: VastraColors.textMuted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
