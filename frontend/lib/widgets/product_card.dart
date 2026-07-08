import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import '../models/product_category.dart';

/// Animated product selection card with idle floating, gold glow on selection,
/// and staggered entrance animation via flutter_animate.
class ProductCard extends StatefulWidget {
  final ProductCategoryData data;
  final bool isSelected;
  final VoidCallback onTap;

  /// Zero-based index used to compute staggered entrance delay.
  final int index;

  const ProductCard({
    super.key,
    required this.data,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2000 + widget.index * 250),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatAnim,
      builder: (_, child) {
        return Transform.translate(
          offset: Offset(0, widget.isSelected ? 0 : _floatAnim.value),
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : (widget.isSelected ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            decoration: widget.isSelected
                ? VastraTheme.goldDecoration(borderRadius: 24)
                : VastraTheme.glassDecoration(borderRadius: 24),
            child: _buildContent(),
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: widget.index * 90))
        .fadeIn(duration: const Duration(milliseconds: 400))
        .slideY(
          begin: 0.35,
          end: 0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isSelected
                  ? VastraColors.gold.withValues(alpha: 0.18)
                  : VastraColors.ivory.withValues(alpha: 0.05),
              border: Border.all(
                color: widget.isSelected
                    ? VastraColors.gold.withValues(alpha: 0.7)
                    : VastraColors.ivory.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
            child: Icon(
              widget.data.icon,
              color: widget.isSelected ? VastraColors.gold : VastraColors.textSecondary,
              size: 26,
            ),
          ),

          const SizedBox(height: 14),

          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: widget.isSelected ? VastraColors.ivory : VastraColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
            child: Text(widget.data.label, textAlign: TextAlign.center),
          ),

          const SizedBox(height: 5),

          Text(
            widget.data.description,
            style: const TextStyle(
              color: VastraColors.textMuted,
              fontSize: 10.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (widget.isSelected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: VastraColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: VastraColors.gold.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: const Text(
                'SELECTED',
                style: TextStyle(
                  color: VastraColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
