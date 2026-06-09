import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/product_category.dart';
import '../providers/vastra_provider.dart';
import 'processing_screen.dart';

class ProductSelectionScreen extends StatefulWidget {
  const ProductSelectionScreen({super.key});

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  ProductCategoryData? _selected;

  void _onSelect(ProductCategoryData data) {
    setState(() => _selected = data);
    context.read<VastraProvider>().setSelectedProduct(data);
  }

  void _onContinue() {
    if (_selected == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ProcessingScreen(),
        transitionDuration: VastraConstants.animationSlow,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.06),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── App bar ──────────────────────────────────────────────────
                _buildAppBar(),

                // ── Header ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding, 24, VastraConstants.pagePadding, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What would you\nlike to redesign?',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.25),
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0, duration: 400.ms),
                      const SizedBox(height: 10),
                      Text(
                        'Select a furniture type — AI will automatically detect it in your room.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Category grid ─────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: ProductCategoryData.all.length,
                      itemBuilder: (context, index) {
                        final data = ProductCategoryData.all[index];
                        final isSelected = _selected?.category == data.category;
                        return _CategoryCard(
                          data: data,
                          isSelected: isSelected,
                          onTap: () => _onSelect(data),
                          index: index,
                        );
                      },
                    ),
                  ),
                ),

                // ── Bottom CTA ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding, 16, VastraConstants.pagePadding, 32),
                  child: _CtaButton(
                    label: _selected == null
                        ? 'Select a Category'
                        : 'Continue with ${_selected!.label}',
                    isEnabled: _selected != null,
                    onTap: _selected != null ? _onContinue : null,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          const Spacer(),
          _buildStepIndicator(step: 1, total: 3),
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

// ── Category Card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final ProductCategoryData data;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  const _CategoryCard({
    required this.data,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  // Map each category to a warm background gradient pair
  List<Color> get _cardGradient {
    switch (widget.data.category) {
      case ProductCategory.bedsheets:
        return [const Color(0xFF2A1F14), const Color(0xFF1A1510)];
      case ProductCategory.curtains:
        return [const Color(0xFF1A1E2A), const Color(0xFF131520)];
      case ProductCategory.sofaCovers:
        return [const Color(0xFF251A10), const Color(0xFF1A1208)];
      case ProductCategory.pillows:
        return [const Color(0xFF221A14), const Color(0xFF16120E)];
      case ProductCategory.carpets:
        return [const Color(0xFF1E1A10), const Color(0xFF14120A)];
    }
  }

  Color get _iconColor {
    switch (widget.data.category) {
      case ProductCategory.bedsheets:  return const Color(0xFFE8C090);
      case ProductCategory.curtains:   return const Color(0xFF90B4E8);
      case ProductCategory.sofaCovers: return const Color(0xFFE8A070);
      case ProductCategory.pillows:    return const Color(0xFFD4A8C8);
      case ProductCategory.carpets:    return const Color(0xFFA8C890);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _pressCtrl,
        child: AnimatedContainer(
          duration: 250.ms,
          decoration: widget.isSelected
              ? VastraTheme.goldDecoration(borderRadius: 20, glowIntensity: 0.28)
              : VastraTheme.glassDecoration(
                  borderRadius: 20,
                  gradientColors: _cardGradient,
                ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon container
                AnimatedContainer(
                  duration: 250.ms,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: widget.isSelected
                        ? VastraColors.gold.withOpacity(0.18)
                        : VastraColors.ivory.withOpacity(0.05),
                    border: Border.all(
                      color: widget.isSelected
                          ? VastraColors.gold.withOpacity(0.6)
                          : VastraColors.borderLight,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    widget.data.icon,
                    size: 26,
                    color: widget.isSelected ? VastraColors.gold : _iconColor,
                  ),
                ),

                const Spacer(),

                // Name
                Text(
                  widget.data.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: widget.isSelected
                            ? VastraColors.ivory
                            : VastraColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),

                // Description
                Text(
                  widget.data.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.isSelected
                            ? VastraColors.gold.withOpacity(0.8)
                            : VastraColors.textMuted,
                        fontSize: 11,
                      ),
                  maxLines: 2,
                ),

                // Selected checkmark
                if (widget.isSelected) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: VastraColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: VastraColors.gold.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 10, color: VastraColors.gold),
                            const SizedBox(width: 4),
                            Text(
                              'Selected',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: VastraColors.gold,
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      )
          .animate(delay: Duration(milliseconds: 100 + widget.index * 80))
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.15, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
    );
  }
}

// ── CTA Button ────────────────────────────────────────────────────────────────

class _CtaButton extends StatelessWidget {
  final String label;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _CtaButton({
    required this.label,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: 300.ms,
        width: double.infinity,
        height: 56,
        decoration: isEnabled
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                gradient: VastraTheme.goldGradient,
                boxShadow: [
                  BoxShadow(
                    color: VastraColors.gold.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                color: VastraColors.surface,
                border: Border.all(color: VastraColors.borderLight),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isEnabled ? VastraColors.textOnGold : VastraColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
            ),
            if (isEnabled) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: VastraColors.textOnGold),
            ],
          ],
        ),
      ),
    );
  }
}
