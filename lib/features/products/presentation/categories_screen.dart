import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/app_providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  IconData _getIconForCategory(String name) {
    switch (name.toLowerCase()) {
      case 'fruits':
      case 'fresh fruits':
        return Icons.apple;
      case 'vegetables':
      case 'organic vegetables':
        return Icons.eco;
      case 'spices':
      case 'spices & herbs':
        return Icons.grain;
      case 'flowers':
      case 'flowers & decor':
        return Icons.local_florist;
      case 'exotic fruits':
        return Icons.auto_awesome;
      case 'dry fruits & nuts':
        return Icons.spa;
      case 'dairy & eggs':
        return Icons.egg_alt;
      case 'combo packs':
        return Icons.card_giftcard;
      case 'all':
        return Icons.apps;
      default:
        return Icons.category_outlined;
    }
  }

  Color _getColorForCategory(String name) {
    switch (name.toLowerCase()) {
      case 'fruits':
      case 'fresh fruits':
        return const Color(0xFFFFEBEE);
      case 'vegetables':
      case 'organic vegetables':
        return const Color(0xFFE8F5E9);
      case 'spices':
      case 'spices & herbs':
        return const Color(0xFFEFEBE9);
      case 'flowers':
      case 'flowers & decor':
        return const Color(0xFFF3E5F5);
      case 'exotic fruits':
        return const Color(0xFFFFF3E0);
      case 'dry fruits & nuts':
        return const Color(0xFFFFF8E1);
      case 'dairy & eggs':
        return const Color(0xFFE1F5FE);
      case 'combo packs':
        return const Color(0xFFF1F8E9);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCat = ref.watch(selectedCategoryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
              child: categoriesAsync.when(
                data: (categories) {
                  // Ensure 'All' is at the top if not present from API
                  final list = categories.contains('All') ? categories : ['All', ...categories];
                  
                  if (list.length <= 1) {
                    return const Center(
                      child: Text('No categories found.', style: TextStyle(color: AppColors.textSecondary)),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.88,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final catName = list[index];
                      final isSelected = selectedCat == catName;

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
                                decoration: BoxDecoration(
                                  color: _getColorForCategory(catName),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getIconForCategory(catName),
                                  color: AppColors.primaryGreen,
                                  size: 26,
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
                error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.error))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
