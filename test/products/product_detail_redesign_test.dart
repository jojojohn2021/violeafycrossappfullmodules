import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/features/products/presentation/product_detail_screen.dart';
import 'package:leafy_webapp/models/models.dart';
import 'package:leafy_webapp/providers/app_providers.dart';
import 'package:leafy_webapp/repositories/shopping_repository.dart';
import 'package:leafy_webapp/shared/widgets/product_card.dart';

ProductPerformance _makeProduct({
  String id = 'p_mango',
  String? productStoryUrl,
  bool culinarydetails = false,
  dynamic keyFeatures = '100% pure, No preservatives, , Sun dried',
  dynamic dietaryAttributes = 'Vegetarian, Vegan, Gluten-Free',
  dynamic nutritionalBenefits = 'Rich in polyphenols, Essential oils',
  dynamic culinaryUses = 'Curries, Herbal teas',
  dynamic productHighlights = 'Trusted Indian growers, No artificial colors, Moisture-resistant pack, Everyday culinary use',
  String? storageInstructions = 'Store in a cool, dry place.',
  String? allergenInformation = 'Contains tree nuts',
  String? certifications,
}) {
  return ProductPerformance.fromJson({
    'id': id,
    'name': 'Mango Dry Fruits - Sugar Coated',
    'sku': 'MANGO-250',
    'packingSize': '250 gm',
    'unit': 'PAC',
    'onlinePrice': 599,
    'shopPrice': 625,
    'mrp': 625,
    'offerPrice': 599,
    'brand': 'Bhadram',
    'brandOwner': 'Vio Nature Science',
    'categories': ['Dry Fruits - Sugar Coated', 'Dry Fruits'],
    'description': 'Carefully selected and hygienically packed.',
    'specifications': 'Mango Dried',
    'ingredients': 'Mango',
    'notes': 'Dehydrated fruit snack.',
    'stockAvailability': 'In Stock',
    'productStoryUrl': productStoryUrl,
    'culinarydetails': culinarydetails,
    'keyFeatures': keyFeatures,
    'dietaryAttributes': dietaryAttributes,
    'nutritionalBenefits': nutritionalBenefits,
    'culinaryUses': culinaryUses,
    'productHighlights': productHighlights,
    'storageInstructions': storageInstructions,
    'allergenInformation': allergenInformation,
    'certifications': certifications,
  });
}

void main() {
  group('ProductPerformance field parsing & Product Story visibility rules', () {
    test('parseBulletList splits comma-separated strings and trims/omits empty entries', () {
      expect(
        ProductPerformance.parseBulletList(' 100% pure , , No fillers,  Sun dried , '),
        ['100% pure', 'No fillers', 'Sun dried'],
      );
      expect(
        ProductPerformance.parseBulletList([' Item A ', '', '   ', 'Item B']),
        ['Item A', 'Item B'],
      );
      expect(ProductPerformance.parseBulletList(null), isEmpty);
    });

    test('hasProductStory is true only for meaningful non-empty values', () {
      expect(_makeProduct(productStoryUrl: null).hasProductStory, isFalse);
      expect(_makeProduct(productStoryUrl: '').hasProductStory, isFalse);
      expect(_makeProduct(productStoryUrl: '   ').hasProductStory, isFalse);
      expect(_makeProduct(productStoryUrl: 'null').hasProductStory, isFalse);
      expect(
        _makeProduct(productStoryUrl: 'https://example.com/story.mp4').hasProductStory,
        isTrue,
      );
    });
  });

  group('ProductCard (Home) Product Story visibility', () {
    testWidgets('hides Product Story when backing field is empty/null and shows when populated', (tester) async {
      final withoutStory = _makeProduct(id: 'no_story', productStoryUrl: '   ');
      final withStory = _makeProduct(id: 'with_story', productStoryUrl: 'https://example.com/story.mp4');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 300, height: 360, child: ProductCard(product: withoutStory)),
                  SizedBox(width: 300, height: 360, child: ProductCard(product: withStory)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('product_card_story_no_story')), findsNothing);
      expect(find.byKey(const ValueKey('product_card_story_with_story')), findsOneWidget);
    });
  });

  group('ProductDetailScreen layout, sections, highlights & conditional culinaryUses', () {
    testWidgets('renders highlights, metadata order, sections, hides Ideal for making when culinarydetails=false, and hides Product Story when empty',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final product = _makeProduct(
        id: 'p_detail_1',
        productStoryUrl: '',
        culinarydetails: false,
        certifications: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            productsProvider.overrideWith((ref) async => [product]),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(productId: 'p_detail_1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Product Story hidden when empty
      expect(find.byKey(const ValueKey('product_detail_story_p_detail_1')), findsNothing);

      // PRODUCT HIGHLIGHTS rendered below ADD TO CART
      expect(find.byKey(const ValueKey('product_highlights_card')), findsOneWidget);
      expect(find.text('PRODUCT HIGHLIGHTS'), findsOneWidget);
      expect(find.text('Trusted Indian growers'), findsOneWidget);

      // Metadata labels in reference order
      expect(find.text('Brand'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Pack Size'), findsOneWidget);
      expect(find.text('Unit'), findsOneWidget);
      expect(find.text('Marketed By'), findsOneWidget);

      // Specified sections rendered
      expect(find.text('KEY FEATURES'), findsOneWidget);
      expect(find.text('100% pure'), findsOneWidget);
      expect(find.text('Dietary'), findsOneWidget);
      expect(find.text('NUTRITION'), findsOneWidget);
      expect(find.text('DESCRIPTION'), findsOneWidget);
      expect(find.text('SPECIFICATIONS'), findsOneWidget);
      expect(find.text('INGREDIENTS'), findsOneWidget);
      expect(find.text('NOTES'), findsOneWidget);
      expect(find.text('Storage Conditions'), findsOneWidget);
      expect(find.text('Allergen Information'), findsOneWidget);

      // Ideal for making hidden when culinarydetails is false; Certifications hidden when null
      expect(find.text('Ideal for making'), findsNothing);
      expect(find.text('Certifications'), findsNothing);
    });

    testWidgets('shows Ideal for making when culinarydetails=true and shows Product Story when populated',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final product = _makeProduct(
        id: 'p_detail_2',
        productStoryUrl: 'https://example.com/mango-story.mp4',
        culinarydetails: true,
        certifications: 'FSSAI Certified',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            productsProvider.overrideWith((ref) async => [product]),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(productId: 'p_detail_2'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('product_detail_story_p_detail_2')), findsOneWidget);
      expect(find.text('Ideal for making'), findsOneWidget);
      expect(find.text('Certifications'), findsOneWidget);
    });
  });
}
