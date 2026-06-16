import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/fabric_item.dart';
import '../providers/vastra_provider.dart';
import '../providers/fabric_catalog_provider.dart';
import 'result_screen.dart';

class FabricCatalogScreen extends StatefulWidget {
  const FabricCatalogScreen({super.key});

  @override
  State<FabricCatalogScreen> createState() => _FabricCatalogScreenState();
}

class _FabricCatalogScreenState extends State<FabricCatalogScreen>
    with SingleTickerProviderStateMixin {
  FabricItem? _selectedFabric;
  final TextEditingController _searchCtrl = TextEditingController();
  late final AnimationController _glowCtrl;
  bool _isPickingCustom = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FabricCatalogProvider>().init();
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Custom fabric upload ───────────────────────────────────────────────────

  Future<void> _pickCustomFabric() async {
    if (_isPickingCustom) return;
    try {
      setState(() => _isPickingCustom = true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        // Create a temporary FabricItem for custom upload
        final customItem = FabricItem(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Custom Fabric',
          categoryKey: FabricCategory.all.name,
          isUserUploaded: true,
          imageBytes: bytes.toList(),
          aiCompatScore: 88,
        );
        setState(() => _selectedFabric = customItem);
        context.read<VastraProvider>().setFabricImage(bytes);
      }
    } finally {
      if (mounted) setState(() => _isPickingCustom = false);
    }
  }

  Future<void> _onVisualize() async {
    if (_selectedFabric == null) return;
    final provider = context.read<VastraProvider>();

    // Show visual loading dialog while rendering
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: VastraColors.surfaceCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: VastraColors.gold),
                  const SizedBox(height: 16),
                  Text(
                    'Rendering fabric projection...',
                    style: TextStyle(color: VastraColors.ivory, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final bytes = _selectedFabric!.imageBytes != null
          ? Uint8List.fromList(_selectedFabric!.imageBytes!)
          : null;
      
      String textureId = _selectedFabric!.id;
      if (_selectedFabric!.assetPath != null) {
        textureId = _selectedFabric!.assetPath!.split('/').last;
      }

      await provider.renderFinal(textureId, customFabricBytes: bytes);
      
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ResultScreen(),
          transitionDuration: VastraConstants.animationSlow,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to render final output: $e'),
          backgroundColor: Colors.red[900],
        ),
      );
    }
  }

  void _onSelectFabric(FabricItem item, Uint8List? imageBytes) {
    setState(() => _selectedFabric = item);
    if (imageBytes != null) {
      context.read<VastraProvider>().setFabricImage(imageBytes);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(
              decoration:
                  const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                _buildHeader(),
                _buildSearchBar(),
                _buildFilterBar(),
                const SizedBox(height: 4),
                Expanded(child: _buildFabricGrid()),
                _buildBottomAction(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: VastraColors.ivory, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          _buildStepIndicator(step: 2, total: 3),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final provider = context.watch<VastraProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VastraConstants.pagePadding, 18, VastraConstants.pagePadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose Your Fabric',
                  style: Theme.of(context).textTheme.headlineLarge,
                )
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2, end: 0, duration: 400.ms),
              ),
              // Upload custom button
              GestureDetector(
                onTap: _pickCustomFabric,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                    border:
                        Border.all(color: VastraColors.gold.withOpacity(0.5)),
                    color: VastraColors.gold.withOpacity(0.08),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isPickingCustom
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: VastraColors.gold,
                              ),
                            )
                          : const Icon(Icons.upload_rounded,
                              size: 14, color: VastraColors.gold),
                      const SizedBox(width: 6),
                      Text('Upload',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: VastraColors.gold, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            provider.selectedProduct != null
                ? 'For your ${provider.selectedProduct!.label.toLowerCase()}'
                : 'Browse the catalog',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VastraColors.gold.withOpacity(0.8),
                ),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VastraConstants.pagePadding, 16, VastraConstants.pagePadding, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
          color: VastraColors.surfaceCard,
          border: Border.all(color: VastraColors.borderLight, width: 0.8),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: VastraColors.ivory),
          decoration: InputDecoration(
            hintText: 'Search fabrics...',
            hintStyle: TextStyle(color: VastraColors.textMuted, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded,
                color: VastraColors.textMuted, size: 18),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: VastraColors.textMuted, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      context.read<FabricCatalogProvider>().clearSearch();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (v) => context.read<FabricCatalogProvider>().setSearch(v),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(
            left: VastraConstants.pagePadding, right: 12, top: 8),
        itemCount: FabricCategory.values.length,
        itemBuilder: (_, i) {
          final cat = FabricCategory.values[i];
          return Consumer<FabricCatalogProvider>(
            builder: (_, catalog, __) {
              final isActive = catalog.activeFilter == cat;
              return GestureDetector(
                onTap: () => catalog.setFilter(cat),
                child: AnimatedContainer(
                  duration: 200.ms,
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VastraConstants.chipBorderRadius),
                    color:
                        isActive ? VastraColors.gold : VastraColors.surfaceCard,
                    border: Border.all(
                      color: isActive
                          ? VastraColors.gold
                          : VastraColors.borderLight,
                    ),
                  ),
                  child: Text(
                    cat.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: isActive
                              ? VastraColors.textOnGold
                              : VastraColors.warmGrayDark,
                          fontSize: 12,
                        ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFabricGrid() {
    return Consumer<FabricCatalogProvider>(
      builder: (_, catalog, __) {
        final items = catalog.filteredFabrics;
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.texture_rounded,
                    size: 48, color: VastraColors.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text('No fabrics found',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: VastraColors.textMuted)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
              VastraConstants.pagePadding, 12, VastraConstants.pagePadding, 12),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final isSelected = _selectedFabric?.id == item.id;
            return _FabricFingerprintCard(
              item: item,
              isSelected: isSelected,
              glowCtrl: _glowCtrl,
              onTap: (bytes) => _onSelectFabric(item, bytes),
              index: i,
            );
          },
        );
      },
    );
  }

  Widget _buildBottomAction() {
    final canVisualize = _selectedFabric != null;
    final provider = context.watch<VastraProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VastraConstants.pagePadding, 8, VastraConstants.pagePadding, 28),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: VastraColors.gold),
                  SizedBox(width: 8),
                  Text(
                    'AI Diffusion Refinement',
                    style: TextStyle(
                      color: VastraColors.ivory,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Switch(
                value: provider.refineWithDiffusion,
                onChanged: (val) => provider.toggleDiffusionRefinement(),
                activeColor: VastraColors.gold,
                activeTrackColor: VastraColors.gold.withOpacity(0.3),
                inactiveThumbColor: VastraColors.warmGray,
                inactiveTrackColor: VastraColors.borderLight,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedFabric != null) ...[
            _buildSelectedFabricChip(),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: canVisualize ? _onVisualize : null,
            child: AnimatedContainer(
              duration: 300.ms,
              width: double.infinity,
              height: 56,
              decoration: canVisualize
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          VastraConstants.buttonBorderRadius),
                      gradient: VastraTheme.goldGradient,
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.gold.withOpacity(0.40),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    )
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          VastraConstants.buttonBorderRadius),
                      color: VastraColors.surface,
                      border: Border.all(color: VastraColors.borderLight),
                    ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: canVisualize
                        ? VastraColors.textOnGold
                        : VastraColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    canVisualize ? 'Visualize Now' : 'Select a Fabric',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: canVisualize
                              ? VastraColors.textOnGold
                              : VastraColors.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFabricChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
        color: VastraColors.gold.withOpacity(0.10),
        border: Border.all(color: VastraColors.gold.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 14, color: VastraColors.gold),
          const SizedBox(width: 8),
          Text(
            '${_selectedFabric!.name} selected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VastraColors.gold,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _selectedFabric = null);
              context.read<VastraProvider>().clearFabricImage();
            },
            child: Icon(Icons.close_rounded,
                size: 14, color: VastraColors.gold.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator({required int step, required int total}) {
    return Row(
      children: List.generate(total, (i) {
        final isCurrent = i == step - 1;
        final isDone = i < step - 1;
        return AnimatedContainer(
          duration: 300.ms,
          margin: const EdgeInsets.only(left: 6),
          width: isCurrent ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isCurrent
                ? VastraColors.gold
                : isDone
                    ? VastraColors.gold.withOpacity(0.4)
                    : VastraColors.ivory.withOpacity(0.12),
          ),
        );
      }),
    );
  }
}

// ── Fabric Fingerprint Card (Signature Feature C2) ────────────────────────────

class _FabricFingerprintCard extends StatelessWidget {
  final FabricItem item;
  final bool isSelected;
  final AnimationController glowCtrl;
  final void Function(Uint8List?) onTap;
  final int index;

  const _FabricFingerprintCard({
    required this.item,
    required this.isSelected,
    required this.glowCtrl,
    required this.onTap,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // For builtin fabrics with asset paths, we pass null bytes
        // (the processing screen will load from assets)
        // For user-uploaded fabrics, we pass their image bytes
        final bytes = item.imageBytes != null
            ? Uint8List.fromList(item.imageBytes!)
            : null;
        onTap(bytes);
      },
      child: AnimatedBuilder(
        animation: glowCtrl,
        builder: (_, child) {
          final glow = glowCtrl.value;
          return AnimatedContainer(
            duration: 250.ms,
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        VastraColors.gold.withOpacity(0.15),
                        VastraColors.terracotta.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: VastraColors.gold.withOpacity(0.7 + glow * 0.15),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            VastraColors.gold.withOpacity(0.25 + glow * 0.08),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
                    color: VastraColors.surfaceCard,
                    border:
                        Border.all(color: VastraColors.borderLight, width: 0.8),
                  ),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fabric image / preview ────────────────────────────────────
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(23)),
              child: SizedBox(
                height: 130,
                width: double.infinity,
                child: Stack(
                  children: [
                    // Fabric image
                    _buildFabricImage(),

                    // Category badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.category.label.toUpperCase(),
                          style: const TextStyle(
                            color: VastraColors.warmGray,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),

                    // Selected checkmark
                    if (isSelected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: VastraColors.gold,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 13, color: VastraColors.textOnGold),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Fabric info ───────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: 12.5,
                            color: isSelected
                                ? VastraColors.ivory
                                : VastraColors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.material,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VastraColors.textMuted,
                            fontSize: 10.5,
                          ),
                    ),
                    const Spacer(),

                    // Color swatch dots + AI compat score
                    Row(
                      children: [
                        // Color dots
                        ...item.colorTags.take(3).map((c) => Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                  width: 0.5,
                                ),
                              ),
                            )),
                        const Spacer(),

                        // AI compat score
                        _AICompatBadge(
                            score: item.aiCompatScore, isSelected: isSelected),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 350.ms)
        .slideY(
            begin: 0.12, end: 0, duration: 350.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildFabricImage() {
    if (item.imageBytes != null) {
      return Image.memory(
        Uint8List.fromList(item.imageBytes!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 130,
      );
    }

    if (item.assetPath != null) {
      return Image.asset(
        item.assetPath!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 130,
        errorBuilder: (_, __, ___) => _buildFabricPlaceholder(),
      );
    }

    return _buildFabricPlaceholder();
  }

  Widget _buildFabricPlaceholder() {
    // Animated procedural fabric pattern using the fabric's color tags
    return CustomPaint(
      painter: _FabricPatternPainter(
        colors: item.colorTags.isNotEmpty
            ? item.colorTags.map((c) => Color(c)).toList()
            : [VastraColors.warmGray, VastraColors.terracotta],
        seed: item.id.hashCode,
      ),
      size: const Size(double.infinity, 130),
    );
  }
}

// ── AI Compat Badge ───────────────────────────────────────────────────────────

class _AICompatBadge extends StatelessWidget {
  final int score;
  final bool isSelected;

  const _AICompatBadge({required this.score, required this.isSelected});

  Color get _badgeColor {
    if (score >= 93) return const Color(0xFF4CAF82);
    if (score >= 85) return VastraColors.gold;
    return VastraColors.terracotta;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _badgeColor.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 8, color: _badgeColor),
          const SizedBox(width: 3),
          Text(
            '$score%',
            style: TextStyle(
              color: _badgeColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Procedural Fabric Pattern Painter ────────────────────────────────────────

class _FabricPatternPainter extends CustomPainter {
  final List<Color> colors;
  final int seed;

  const _FabricPatternPainter({required this.colors, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final bg = colors.first.withOpacity(0.25);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bg);

    // Draw woven grid lines
    final c1 = colors[0 % colors.length];
    final c2 = colors.length > 1 ? colors[1 % colors.length] : c1;

    final paint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const step = 10.0;
    for (double x = 0; x < size.width; x += step) {
      paint.color = (x / step).floor().isEven
          ? c1.withOpacity(0.28)
          : c2.withOpacity(0.20);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      paint.color = (y / step).floor().isEven
          ? c2.withOpacity(0.28)
          : c1.withOpacity(0.20);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Random texture dots
    for (int i = 0; i < 25; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.8 + rng.nextDouble() * 2.5;
      canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()
            ..color = (rng.nextBool() ? c1 : c2).withOpacity(0.3)
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _FabricPatternPainter old) =>
      old.seed != seed || old.colors != colors;
}
