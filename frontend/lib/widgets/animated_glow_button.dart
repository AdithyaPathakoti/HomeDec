import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/constants.dart';

/// A premium button with scale-on-press feedback, a persistent gold glow pulse,
/// and both a filled (primary) and outlined (secondary) variant.
class AnimatedGlowButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isEnabled;
  final bool isLoading;
  final double? width;

  const AnimatedGlowButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.isPrimary = true,
    this.isEnabled = true,
    this.isLoading = false,
    this.width,
  });

  @override
  State<AnimatedGlowButton> createState() => _AnimatedGlowButtonState();
}

class _AnimatedGlowButtonState extends State<AnimatedGlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  bool get _isActive => widget.isEnabled && !widget.isLoading;

  void _onTapDown(TapDownDetails _) {
    if (_isActive) setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (_isActive) setState(() => _pressed = false);
  }

  void _onTapCancel() {
    if (_isActive) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _isActive ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, child) {
            final glow = _isActive && widget.isPrimary
                ? 0.25 + _glowAnim.value * 0.15
                : 0.0;
            return Container(
              width: widget.width ?? double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                boxShadow: widget.isPrimary && _isActive
                    ? [
                        BoxShadow(
                          color: VastraColors.gold.withOpacity(glow),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: VastraColors.goldDark.withOpacity(glow * 0.4),
                          blurRadius: 44,
                          spreadRadius: 3,
                        ),
                      ]
                    : [],
              ),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
              gradient: widget.isPrimary && _isActive
                  ? VastraTheme.goldGradient
                  : null,
              color: !(widget.isPrimary && _isActive)
                  ? VastraColors.surface
                  : null,
              border: Border.all(
                color: widget.isPrimary
                    ? (_isActive
                        ? VastraColors.gold.withOpacity(0.6)
                        : VastraColors.borderLight)
                    : VastraColors.borderLight,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize:
                  widget.width != null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (widget.isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VastraColors.textOnGold,
                    ),
                  )
                else ...[
                  Icon(
                    widget.icon,
                    color: widget.isPrimary && _isActive
                        ? VastraColors.textOnGold
                        : VastraColors.warmGray,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.isPrimary && _isActive
                          ? VastraColors.textOnGold
                          : VastraColors.warmGray,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
