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
      borderRadius: BorderRadius.circular(12),
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
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),

                // ── After (AI result) – clipped to show right of divider ─────
                ClipRect(
                  child: ClipRect(
                    clipper: _RightClipper(_position),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Image.memory(
                        widget.afterBytes,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),

                // ── Divider line ─────────────────────────────────────────────
                Positioned(
                  left: w * _position - 1,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: h,
                    color: VastraColors.ivory,
                  ),
                ),

                // ── Handle — Shadcn medallion ──────────────────────────────────
                Positioned(
                  left: w * _position - 20,
                  top: h / 2 - 20,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: VastraColors.ivory,
                      border: Border.all(color: VastraColors.border, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      color: VastraColors.background,
                      size: 20,
                    ),
                  ),
                ),

                // ── BEFORE label ─────────────────────────────────────────────
                Positioned(
                  left: 12,
                  top: 12,
                  child: _buildLabel('BEFORE'),
                ),

                // ── AFTER label ──────────────────────────────────────────────
                Positioned(
                  right: 12,
                  top: 12,
                  child: _buildLabel('AFTER'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: VastraColors.surfaceElevated.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: VastraColors.border.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: VastraColors.ivory,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          fontFamily: 'Inter',
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
