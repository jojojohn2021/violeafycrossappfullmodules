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
          key: const ValueKey('ayurvedic_card_scope'),
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

    testWidgets('Home ProductCard restricts unique specs to uniqueSpec1 and uniqueSpec2 only', (tester) async {
      final product = ProductPerformance.fromJson({
        'id': 'p_specs',
        'name': 'Mango Dry Fruits',
        'sku': 'MANGO-250',
        'packingSize': '250 gm',
        'unit': 'PAC',
        'onlinePrice': 599,
        'shopPrice': 625,
        'uniqueSpec1': 'Sun Dried',
        'uniqueSpec2': 'Low Sugar',
        'uniqueSpec3': 'Sourced from trusted growers',
        'uniqueSpec4': 'Small Batch',
      });

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('home_specs_scope'),
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 360,
                child: ProductCard(product: product, restrictToPrimarySpecs: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sun Dried'), findsOneWidget);
      expect(find.text('Low Sugar'), findsOneWidget);
      expect(find.text('Sourced from trusted growers'), findsNothing);
      expect(find.text('Small Batch'), findsNothing);
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

    testWidgets('shows language-specific names only when ayurvedicproduct is true on ProductDetailScreen and ProductCard',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ayurvedic = ProductPerformance.fromJson({
        'id': 'p_kadukka',
        'name': 'Kadukka',
        'sku': 'KAD-100',
        'packingSize': '100 g',
        'unit': 'PAC',
        'onlinePrice': 349,
        'shopPrice': 399,
        'brand': 'Bhadram',
        'ayurvedicproduct': true,
        'sanskritName': 'Haritaki',
        'malayalamName': 'Kadukka (മലയാളം)',
        'hindiName': 'Harad (हिन्दी)',
        'kannadaName': 'Alalekayi (ಕನ್ನಡ)',
        'tamilName': 'Kadukkai (தமிழ்)',
        'teluguName': 'Karakkaya (తెలుగు)',
        'ayurvedicClassification': 'Dravyaguna Vijnana – Traditional Herb',
        'ayurvedicDescription': 'Traditionally valued for balanced digestion.',
        'dravyaguna': {
          'rasa': ['Katu (Pungent)', 'Tikta (Bitter)'],
          'guna': ['Laghu (Light)', 'Ruksha (Dry)'],
          'virya': 'Ushna (Warming)',
          'vipaka': 'Katu (Pungent)',
          'prabhava': 'Classical rejuvenative action',
        },
        'doshaEffect': {
          'vata': 'Balances Vata in moderation',
          'pitta': 'Use in moderation for Pitta',
          'kapha': 'Pacifies Kapha',
        },
        'ayurvedicMedicinalUses': [
          'Supports healthy digestion',
          'Seasonal respiratory comfort',
          'Promotes gut regularity',
          'Supports natural vitality',
        ],
        'ayurvedicUsageMethods': [
          'Warm herbal decoction',
          'Fine churna with warm water',
          'Daily culinary tempering',
        ],
        'ayurvedicDosage': '1–3 g daily as directed by a Vaidya.',
        'ayurvedicFormulations': ['Classical Churna', 'Kwatha'],
        'ayurvedicPrecautions': ['Consult a healthcare practitioner during pregnancy.'],
      });

      final nonAyurvedic = ProductPerformance.fromJson({
        'id': 'p_regular',
        'name': 'Regular Spice',
        'sku': 'REG-100',
        'packingSize': '100 g',
        'unit': 'PAC',
        'onlinePrice': 199,
        'shopPrice': 220,
        'ayurvedicproduct': false,
        'sanskritName': 'Should Not Show',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            productsProvider.overrideWith((ref) async => [ayurvedic, nonAyurvedic]),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(productId: 'p_kadukka'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('ayurvedic_names_p_kadukka')), findsOneWidget);
      expect(find.text('Haritaki'), findsOneWidget);
      expect(find.text('Kadukka (മലയാളം)'), findsOneWidget);
      expect(find.text('Harad (हिन्दी)'), findsOneWidget);
      expect(find.text('Alalekayi (ಕನ್ನಡ)'), findsOneWidget);
      expect(find.text('Kadukkai (தமிழ்)'), findsOneWidget);
      expect(find.text('Karakkaya (తెలుగు)'), findsOneWidget);

      // Ayurveda Insights tab appears next to Product Details when ayurvedicproduct == true
      expect(find.text('Ayurveda Insights'), findsOneWidget);
      await tester.tap(find.text('Ayurveda Insights'));
      await tester.pump();

      expect(find.byKey(const ValueKey('ayurveda_insights_content_p_kadukka')), findsOneWidget);
      expect(find.text('Ayurvedic Classification'), findsOneWidget);
      expect(find.text('Dravyaguna Vijnana – Traditional Herb'), findsOneWidget);
      expect(find.text('Classical Description'), findsOneWidget);
      expect(find.text('Rasa'), findsOneWidget);
      expect(find.text('Katu (Pungent), Tikta (Bitter)'), findsOneWidget);
      expect(find.text('Guna'), findsOneWidget);
      expect(find.text('Virya (Potency)'), findsOneWidget);
      expect(find.text('Vipaka (Post-Digestive)'), findsOneWidget);
      expect(find.text('Prabhava (Special Action)'), findsOneWidget);
      expect(find.text('Dosha Effect — Vata'), findsOneWidget);
      expect(find.text('Dosha Effect — Pitta'), findsOneWidget);
      expect(find.text('Dosha Effect — Kapha'), findsOneWidget);
      expect(find.text('Medicinal Uses'), findsOneWidget);
      expect(find.text('Supports healthy digestion'), findsOneWidget);
      expect(find.text('Usage Methods'), findsOneWidget);
      expect(find.text('Typical Dosage Note'), findsOneWidget);
      expect(find.text('Classical Formulations'), findsOneWidget);
      expect(find.text('Classical Churna, Kwatha'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ayurveda_insights_content_p_kadukka')),
          matching: find.text('Precautions'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ayurvedic_card_scope'),
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 300, height: 380, child: ProductCard(product: ayurvedic)),
                  SizedBox(width: 300, height: 380, child: ProductCard(product: nonAyurvedic)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('product_card_ayurvedic_names_p_kadukka')), findsOneWidget);
      expect(find.byKey(const ValueKey('product_card_ayurvedic_names_p_regular')), findsNothing);
      expect(find.text('Should Not Show'), findsNothing);
    });

    test('parseHealthBenefits extracts only claim values from map entries and supports plain strings', () {
      final fromMaps = ProductPerformance.parseHealthBenefits([
        {
          'claim': 'Rich in antioxidants: Ginger Golden Sticks naturally contains polyphenols.',
          'review_status': 'approved',
        },
        {
          'review_status': 'approved',
          'claim': 'Supports immunity: Provides natural phytonutrients.',
        },
        {
          'review_status': 'approved',
          'claim': '   ',
        },
      ]);
      expect(fromMaps, [
        'Rich in antioxidants: Ginger Golden Sticks naturally contains polyphenols.',
        'Supports immunity: Provides natural phytonutrients.',
      ]);

      expect(
        ProductPerformance.parseHealthBenefits(['Plain benefit A', 'Plain benefit B']),
        ['Plain benefit A', 'Plain benefit B'],
      );
    });

    test('parseNutritionalInformation handles Map, List<Map>, and formatted String inputs', () {
      final fromMap = ProductPerformance.parseNutritionalInformation({
        'servingSize': '100 g',
        'energy': '320 kcal',
        'dietary_fiber': '10 g',
      });
      expect(fromMap.length, 3);
      expect(fromMap[0].nutrient, 'Serving Size');
      expect(fromMap[0].value, '100 g');
      expect(fromMap[2].nutrient, 'Dietary Fiber');

      final fromList = ProductPerformance.parseNutritionalInformation([
        {'nutrient': 'Protein', 'value': '6.5 g', 'dailyValue': '13%'},
        {'name': 'Iron', 'amount': '2.4', 'unit': 'mg'},
      ]);
      expect(fromList.length, 2);
      expect(fromList[0].dailyValue, '13%');
      expect(fromList[1].value, '2.4 mg');

      final fromString = ProductPerformance.parseNutritionalInformation(
        'Energy: 320 kcal\nCarbohydrates: 72 g',
      );
      expect(fromString.length, 2);
      expect(fromString[0].nutrient, 'Energy');
      expect(fromString[0].value, '320 kcal');
    });

    test('parseNutritionalFacts parses tab-delimited Nutritional Facts with serving meta, indentation, and footnotes', () {
      const rawFacts =
          'Nutritional Facts\n'
          'Serving Size: 20g | Serving per pack: Approx 10\n'
          'Nutrient\tper 100 g\tper serving\t%RDA (per serve)\n'
          'Energy (kcal)\t324.00\t64.80\t-\n'
          'Total Fat (g)\t0.50\t0.10\t0.13\n'
          '  Saturated fat (g)\t0.10\t0.02\t0.10\n'
          '    Added Sugar (g)\t44.00\t8.80\t17.60\n'
          '\n'
          '*The % of RDA (Recommended Dietary Allowance) calculated on the basis of 2000 Kcal energy';

      final facts = ProductPerformance.parseNutritionalFacts(rawFacts);
      expect(facts, isNotNull);
      expect(facts!.title, 'Nutritional Facts');
      expect(facts.servingSize, '20g');
      expect(facts.servingPerPack, 'Approx 10');
      expect(facts.headers, ['Nutrient', 'per 100 g', 'per serving', '%RDA (per serve)']);
      expect(facts.rows.length, 4);
      expect(facts.rows[0].nutrient, 'Energy (kcal)');
      expect(facts.rows[0].values, ['324.00', '64.80', '-']);
      expect(facts.rows[0].indentLevel, 0);
      expect(facts.rows[2].indentLevel, 1);
      expect(facts.rows[3].indentLevel, 2);
      expect(facts.footNotes.first, startsWith('*The % of RDA'));
    });

    testWidgets('shows Health Benefits, Nutritional Information table, and Precautions tabs for all products (including non-Ayurvedic)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final regularProduct = ProductPerformance.fromJson({
        'id': 'p_tabs_all',
        'name': 'Organic Turmeric',
        'sku': 'TUR-100',
        'packingSize': '100 g',
        'unit': 'PAC',
        'onlinePrice': 249,
        'shopPrice': 299,
        'brand': 'Bhadram',
        'ayurvedicproduct': false,
        'healthBenefits': [
          'Rich in natural curcumin antioxidants',
          'Supports daily immunity and wellness',
        ],
        'nutritionalInformation': [
          {'nutrient': 'Energy', 'value': '354 kcal', 'dailyValue': '18%'},
          {'nutrient': 'Protein', 'value': '7.8 g', 'dailyValue': '16%'},
          {'nutrient': 'Dietary Fiber', 'value': '21 g', 'dailyValue': '75%'},
        ],
        'generalPrecautions': [
          'Store away from direct sunlight',
          'Consult a physician if on blood-thinning medication',
        ],
      });

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('all_products_tabs_scope'),
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            productsProvider.overrideWith((ref) async => [regularProduct]),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(productId: 'p_tabs_all'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ayurveda Insights hidden for non-Ayurvedic product, but the 3 general tabs are visible
      final tabBar = find.byKey(const ValueKey('product_details_tab_bar'));
      expect(find.descendant(of: tabBar, matching: find.text('Product Details')), findsOneWidget);
      expect(find.descendant(of: tabBar, matching: find.text('Ayurveda Insights')), findsNothing);
      expect(find.descendant(of: tabBar, matching: find.text('Health Benefits')), findsOneWidget);
      expect(find.descendant(of: tabBar, matching: find.text('Nutritional Information')), findsOneWidget);
      expect(find.descendant(of: tabBar, matching: find.text('Precautions')), findsOneWidget);

      // Tap Health Benefits tab
      await tester.tap(find.descendant(of: tabBar, matching: find.text('Health Benefits')));
      await tester.pump();
      expect(find.byKey(const ValueKey('health_benefits_content_p_tabs_all')), findsOneWidget);
      expect(find.text('Rich in natural curcumin antioxidants'), findsOneWidget);

      // Tap Nutritional Information tab -> structured Table
      await tester.tap(find.descendant(of: tabBar, matching: find.text('Nutritional Information')));
      await tester.pump();
      expect(find.byKey(const ValueKey('nutritional_info_table_p_tabs_all')), findsOneWidget);
      expect(find.text('Nutrient'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);
      expect(find.text('% Daily Value'), findsOneWidget);
      expect(find.text('354 kcal'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);

      // Tap Precautions tab
      await tester.tap(find.descendant(of: tabBar, matching: find.text('Precautions')));
      await tester.pump();
      expect(find.byKey(const ValueKey('general_precautions_content_p_tabs_all')), findsOneWidget);
      expect(find.text('Consult a physician if on blood-thinning medication'), findsOneWidget);
    });
  });
}
