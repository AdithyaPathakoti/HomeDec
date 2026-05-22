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

                // ── Divider line ─────────────────────────────────────────────
                Positioned(
                  left: w * _position - 1,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: h,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.purpleNeon.withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Handle ───────────────────────────────────────────────────
                Positioned(
                  left: w * _position - 22,
                  top: h / 2 - 22,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.purpleAccent.withOpacity(0.6),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      color: Colors.black,
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

  Widget _buildLabel(String text, bool isPurple) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isPurple
            ? VastraColors.purpleAccent.withOpacity(0.85)
            : Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPurple
              ? VastraColors.purpleNeon.withOpacity(0.5)
              : Colors.white.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
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
