import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Interactive drag-to-compare before/after slider widget.
/// [beforeBytes] is the original room image; [afterBytes] is the AI-generated result.
class BeforeAfterSlider extends StatefulWidget {
  final Uint8List beforeBytes;
  final Uint8List afterBytes;

  const BeforeAfterSlider({
    super.key,
    required this.beforeBytes,
    required this.afterBytes,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _position = 0.5; // 0.0 = full before, 1.0 = full after

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return GestureDetector(
            onHorizontalDragUpdate: (d) {
              setState(() {
                _position = (_position + d.delta.dx / w).clamp(0.04, 0.96);
              });
            },
            child: Stack(
              children: [
                // ── Before (original) – always full width underneath ─────────
                SizedBox(
                  width: w,
                  height: h,
                  child: Image.memory(
                    widget.beforeBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),

                // ── After (AI result) – clipped to show right of divider ─────
                ClipRect(
                  clipper: _RightClipper(_position),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Image.memory(
                      widget.afterBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),

                // ── Divider line — gold glow ─────────────────────────────────
                Positioned(
                  left: w * _position - 1,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          VastraColors.goldLight.withOpacity(0.6),
                          VastraColors.gold,
                          VastraColors.goldLight.withOpacity(0.6),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.gold.withOpacity(0.55),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Handle — gold medallion ──────────────────────────────────
                Positioned(
                  left: w * _position - 24,
                  top: h / 2 - 24,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: VastraTheme.goldGradient,
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.gold.withOpacity(0.55),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      color: VastraColors.textOnGold,
                      size: 22,
                    ),
                  ),
                ),

                // ── BEFORE label ─────────────────────────────────────────────
                Positioned(
                  left: 12,
                  top: 12,
                  child: _buildLabel('BEFORE', false),
                ),

                // ── AFTER label ──────────────────────────────────────────────
                Positioned(
                  right: 12,
                  top: 12,
                  child: _buildLabel('AFTER', true),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabel(String text, bool isAfter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isAfter
            ? VastraColors.gold.withOpacity(0.85)
            : Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAfter
              ? VastraColors.goldLight.withOpacity(0.5)
              : Colors.white.withOpacity(0.12),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isAfter ? VastraColors.textOnGold : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ── Clipper ────────────────────────────────────────────────────────────────────
class _RightClipper extends CustomClipper<Rect> {
  final double position; // 0.0–1.0

  _RightClipper(this.position);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      size.width * position,
      0,
      size.width * (1 - position),
      size.height,
    );
  }

  @override
  bool shouldReclip(_RightClipper old) => old.position != position;
}
