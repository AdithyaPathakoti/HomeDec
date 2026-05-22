import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/product_category.dart';
import '../providers/vastra_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/animated_glow_button.dart';
import 'fabric_upload_screen.dart';

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
        pageBuilder: (_, __, ___) => const FabricUploadScreen(),
        transitionDuration: VastraConstants.animationSlow,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.08),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
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
          // Background gradient
          Container(
            decoration: const BoxDecoration(gradient: VastraTheme.deepGradient),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── App bar ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      // Step indicator
                      _buildStepIndicator(step: 1, total: 3),
                    ],
                  ),
                ),

                // ── Header ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding, 20, VastraConstants.pagePadding, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What would you\nlike to redesign?',
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(height: 1.25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select a furniture type and we\'ll automatically\ndetect it in your room.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Product grid ─────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: VastraConstants.pagePadding),
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: ProductCategoryData.all.length,
                      itemBuilder: (context, index) {
                        final data = ProductCategoryData.all[index];
                        return ProductCard(
                          data: data,
                          isSelected: _selected?.category == data.category,
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
                      VastraConstants.pagePadding,
                      16,
                      VastraConstants.pagePadding,
                      28),
                  child: AnimatedGlowButton(
                    label: _selected == null
                        ? 'Select a Category'
                        : 'Continue with ${_selected!.label}',
                    icon: Icons.arrow_forward_rounded,
                    onTap: _selected != null ? _onContinue : null,
                    isPrimary: true,
                    isEnabled: _selected != null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator({required int step, required int total}) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i < step;
        final isCurrent = i == step - 1;
        return Container(
          margin: const EdgeInsets.only(left: 6),
          width: isCurrent ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive
                ? VastraColors.purpleNeon
                : Colors.white.withOpacity(0.15),
          ),
        );
      }),
    );
  }
}
