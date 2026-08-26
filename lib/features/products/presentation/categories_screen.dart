import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/firestore_image_widget.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Color _getColorForCategory(String category) {
    final normalized = category.toLowerCase();

    if (normalized.contains('fruit')) return const Color(0xFFFFF3E0);
    if (normalized.contains('vegetable') || normalized.contains('veg')) return const Color(0xFFE8F5E9);
    if (normalized.contains('dairy') || normalized.contains('milk')) return const Color(0xFFE3F2FD);
    if (normalized.contains('grain') || normalized.contains('rice') || normalized.contains('cereal')) return const Color(0xFFF3E5F5);
    if (normalized.contains('beverage') || normalized.contains('drink')) return const Color(0xFFE0F7FA);
    if (normalized.contains('snack') || normalized.contains('biscuit') || normalized.contains('sweet')) return const Color(0xFFFFE0B2);

    return const Color(0xFFE8F5E9);
  }

  IconData _getIconForCategory(String category) {
    final normalized = category.toLowerCase();

    if (normalized.contains('fruit')) return Icons.apple;
    if (normalized.contains('vegetable') || normalized.contains('veg')) return Icons.eco;
    if (normalized.contains('dairy') || normalized.contains('milk')) return Icons.local_drink;
    if (normalized.contains('grain') || normalized.contains('rice') || normalized.contains('cereal')) return Icons.grain;
    if (normalized.contains('beverage') || normalized.contains('drink')) return Icons.local_cafe;
    if (normalized.contains('snack') || normalized.contains('biscuit') || normalized.contains('sweet')) return Icons.cookie;

    return Icons.category;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCat = ref.watch(selectedCategoryProvider);
    final categoryModelsAsync = ref.watch(categoryModelsProvider);

    return Container(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async {
          ref.invalidate(categoryModelsProvider);
          ref.invalidate(categoriesProvider);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Explore Categories',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ),
            Expanded(
              child: categoryModelsAsync.when(
                data: (categoryModels) {
                  final allCategoryNames = categoryModels.map((m) => m.name).where((n) => n.isNotEmpty).toList();
                  final listNames = allCategoryNames.contains('All')
                      ? allCategoryNames
                      : ['All', ...allCategoryNames];

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.88,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: listNames.length,
                    itemBuilder: (context, index) {
                      final catName = listNames[index];
                      final isSelected = selectedCat == catName;
                      final matchingModel = categoryModels.firstWhere(
                        (m) => m.name.toLowerCase() == catName.toLowerCase(),
                        orElse: () => ProductCategory(id: catName, name: catName),
                      );

                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedCategoryProvider.notifier).state = catName;
                          context.go('/');
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryGreen.withValues(alpha: 0.1) : AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryGreen : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: _getColorForCategory(catName),
                                  shape: BoxShape.circle,
                                ),
                                child: FirestoreImageWidget(
                                  collection: 'product_categories',
                                  docIdOrRef: matchingModel.imageId ?? matchingModel.id,
                                  directImageUrl: matchingModel.imageUrl,
                                  fit: BoxFit.cover,
                                  fallbackWidget: Icon(
                                    _getIconForCategory(catName),
                                    color: AppColors.primaryGreen,
                                    size: 26,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                catName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? AppColors.primaryGreen : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Failed to load categories: $err', style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(categoryModelsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

