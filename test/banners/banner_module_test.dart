import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/features/banners/banner_module.dart';

Map<String, dynamic> _verifiedSampleBannerJson() => {
      'pageType': 'home',
      'pageId': null,
      'placement': 'hero',
      'sortOrder': 1,
      'isActive': true,
      'startsAt': null,
      'endsAt': null,
      'carouselEnabled': true,
      'autoplay': true,
      'loop': true,
      'mediaType': 'video',
      'desktop': {
        'url': 'https://storage.googleapis.com/demo/top_desktop.mp4',
        'storagePath': 'banners/home/global/top_desktop.mp4',
        'fileName': 'top_desktop.mp4',
        'mimeType': 'video/mp4',
        'width': 1920,
        'height': 720,
        'sizeBytes': 4150858,
        'durationSec': 6.1,
      },
      'mobile': {
        'url': 'https://storage.googleapis.com/demo/top_mobile.mp4',
        'storagePath': 'banners/home/global/top_mobile.mp4',
        'fileName': 'top_mobile.mp4',
        'mimeType': 'video/mp4',
        'width': 1080,
        'height': 1350,
        'sizeBytes': 3269496,
        'durationSec': 3.8,
      },
      'desktopPoster': {
        'url': 'https://storage.googleapis.com/demo/top_desktop_poster.jpg',
        'width': 3392,
        'height': 1248,
      },
      'mobilePoster': {
        'url': 'https://storage.googleapis.com/demo/top_mobile_poster.jpg',
        'width': 1856,
        'height': 2304,
      },
      'slides': [
        {
          'id': 'slide_b',
          'mediaType': 'image',
          'desktop': {
            'url': 'https://storage.googleapis.com/demo/slide2_desktop.jpg',
            'mimeType': 'image/jpeg',
          },
          'mobile': null,
          'desktopPoster': null,
          'mobilePoster': null,
          'slideDurationSec': 5,
          'sortOrder': 2,
          'title': 'Organic Spices',
          'subtitle': 'Fresh from Kerala',
          'cta': {'label': 'Explore', 'route': '/categories'},
        },
        {
          'id': 'slide_a',
          'mediaType': 'video',
          'desktop': {
            'url': 'https://storage.googleapis.com/demo/slide1_desktop.mp4',
            'mimeType': 'video/mp4',
            'width': 1920,
            'height': 720,
            'durationSec': 6.1,
          },
          'mobile': {
            'url': 'https://storage.googleapis.com/demo/slide1_desktop.mp4',
            'mimeType': 'video/mp4',
            'width': 1920,
            'height': 720,
            'durationSec': 6.1,
          },
          'desktopPoster': null,
          'mobilePoster': null,
          'slideDurationSec': 6,
          'sortOrder': 1,
          'title': 'Seasonal Harvest',
          'subtitle': 'Limited stock',
          'cta': {'label': 'Shop Now', 'route': '/products'},
        },
      ],
      'cta': {'label': 'Shop Now', 'route': '/products'},
      'placementSpec': {
        'desktopAspectRatio': '8:3',
        'mobileAspectRatio': '4:5',
        'slideDurationSec': 6,
        'maxImageSizeMb': 10,
        'maxVideoSizeMb': 15,
      },
      'createdBy': 'admin_uid',
      'updatedBy': 'admin_uid',
    };

void main() {
  group('BannerPageType & BannerPlacement enums', () {
    test('serializes exact lowercase wire values and exposes home/hero defaults', () {
      expect(BannerPageType.defaultValue, BannerPageType.home);
      expect(BannerPlacement.defaultValue, BannerPlacement.hero);

      expect(BannerPageType.home.wireValue, 'home');
      expect(BannerPageType.category.wireValue, 'category');
      expect(BannerPageType.product.wireValue, 'product');
      expect(BannerPageType.other.wireValue, 'other');

      expect(BannerPlacement.hero.wireValue, 'hero');
      expect(BannerPlacement.secondary.wireValue, 'secondary');
      expect(BannerPlacement.strip.wireValue, 'strip');
      expect(BannerPlacement.spotlight.wireValue, 'spotlight');
      expect(BannerPlacement.footerPromo.wireValue, 'footer_promo');
    });

    test('returns null for missing or unknown pageType/placement so banners never leak to wrong page', () {
      expect(BannerPageType.tryParse(null), isNull);
      expect(BannerPageType.tryParse(''), isNull);
      expect(BannerPageType.tryParse('checkout_unknown'), isNull);

      expect(BannerPlacement.tryParse(null), isNull);
      expect(BannerPlacement.tryParse('popup'), isNull);

      final malformed = DynamicBanner.fromMap('bad_doc', {
        'pageType': 'unknown_page',
        'placement': 'hero',
        'isActive': true,
      });
      expect(
        malformed.matchesPageScope(
          targetPageType: BannerPageType.home,
          targetPlacement: BannerPlacement.hero,
        ),
        isFalse,
      );
    });
  });

  group('DynamicBanner parsing, slide ordering & media/poster selection', () {
    test('parses verified sample document, sorts slides ascending, and does not duplicate top-level media', () {
      final banner = DynamicBanner.fromMap('doc_dynamic_123', _verifiedSampleBannerJson());

      expect(banner.id, 'doc_dynamic_123');
      expect(banner.pageType, BannerPageType.home);
      expect(banner.pageId, isNull);
      expect(banner.placement, BannerPlacement.hero);
      expect(banner.placementSpec.desktopAspectRatio, '8:3');
      expect(banner.placementSpec.mobileAspectRatio, '4:5');
      expect(banner.placementSpec.slideDurationSec, 6);

      final slides = banner.resolvedSlides;
      expect(slides.length, 2);
      expect(slides[0].id, 'slide_a');
      expect(slides[1].id, 'slide_b');

      // Slide with absent mobile falls back to desktop variant
      expect(
        slides[1].selectMedia(isDesktop: false)?.url,
        'https://storage.googleapis.com/demo/slide2_desktop.jpg',
      );

      // Slide with null posters returns null unless top-level fallback is explicitly permitted
      expect(
        slides[0].selectPoster(
          isDesktop: true,
          topLevelDesktopPoster: banner.desktopPoster,
          topLevelMobilePoster: banner.mobilePoster,
          allowTopLevelPosterFallback: false,
        ),
        isNull,
      );
      expect(
        slides[0].selectPoster(
          isDesktop: true,
          topLevelDesktopPoster: banner.desktopPoster,
          topLevelMobilePoster: banner.mobilePoster,
          allowTopLevelPosterFallback: true,
        )?.url,
        'https://storage.googleapis.com/demo/top_desktop_poster.jpg',
      );
    });

    test('renders top-level media as a single slide when carouselEnabled is false or slides is empty', () {
      final json = _verifiedSampleBannerJson()
        ..['carouselEnabled'] = false;
      final banner = DynamicBanner.fromMap('single_doc', json);

      final slides = banner.resolvedSlides;
      expect(slides.length, 1);
      expect(slides.first.id, 'single_doc');
      expect(
        slides.first.selectMedia(isDesktop: true)?.url,
        'https://storage.googleapis.com/demo/top_desktop.mp4',
      );
      expect(
        slides.first.selectMedia(isDesktop: false)?.url,
        'https://storage.googleapis.com/demo/top_mobile.mp4',
      );
    });
  });

  group('Schedule, page scope & sorting (BannerRepository.filterAndSortBanners)', () {
    test('filters isActive, start/end schedule, pageId + global scope, and sorts by sortOrder ascending', () {
      final now = DateTime.utc(2026, 11, 19, 12, 0);

      final globalCat = DynamicBanner.fromMap('cat_global', {
        'pageType': 'category',
        'pageId': null,
        'placement': 'hero',
        'sortOrder': 2,
        'isActive': true,
        'desktop': {'url': 'https://example.com/global.jpg'},
      });

      final specificCat = DynamicBanner.fromMap('cat_spices', {
        'pageType': 'category',
        'pageId': 'Spices',
        'placement': 'hero',
        'sortOrder': 1,
        'isActive': true,
        'startsAt': DateTime.utc(2026, 11, 1).toIso8601String(),
        'endsAt': DateTime.utc(2026, 12, 1).toIso8601String(),
        'desktop': {'url': 'https://example.com/spices.jpg'},
      });

      final expiredCat = DynamicBanner.fromMap('cat_expired', {
        'pageType': 'category',
        'pageId': 'Spices',
        'placement': 'hero',
        'sortOrder': 0,
        'isActive': true,
        'endsAt': DateTime.utc(2026, 11, 18).toIso8601String(),
        'desktop': {'url': 'https://example.com/expired.jpg'},
      });

      final futureCat = DynamicBanner.fromMap('cat_future', {
        'pageType': 'category',
        'pageId': 'Spices',
        'placement': 'hero',
        'sortOrder': 0,
        'isActive': true,
        'startsAt': DateTime.utc(2026, 11, 25).toIso8601String(),
        'desktop': {'url': 'https://example.com/future.jpg'},
      });

      final otherCat = DynamicBanner.fromMap('cat_oils', {
        'pageType': 'category',
        'pageId': 'Oils',
        'placement': 'hero',
        'sortOrder': 0,
        'isActive': true,
        'desktop': {'url': 'https://example.com/oils.jpg'},
      });

      final matched = BannerRepository.filterAndSortBanners(
        banners: [globalCat, specificCat, expiredCat, futureCat, otherCat],
        pageType: BannerPageType.category,
        placement: BannerPlacement.hero,
        pageId: 'Spices',
        now: now,
      );

      expect(matched.map((b) => b.id).toList(), ['cat_spices', 'cat_global']);
    });
  });

  group('BannerRouteValidator', () {
    test('validates supported routes, maps /products safely, and rejects unsupported/unsafe routes', () {
      expect(BannerRouteValidator.resolveSupportedRoute('/products'), '/categories');
      expect(BannerRouteValidator.resolveSupportedRoute('/categories'), '/categories');
      expect(BannerRouteValidator.resolveSupportedRoute('/product-detail/prod_123'), '/product-detail/prod_123');
      expect(BannerRouteValidator.resolveSupportedRoute('/preorders'), '/preorders');
      expect(BannerRouteValidator.resolveSupportedRoute('/unknown-route'), isNull);
      expect(BannerRouteValidator.resolveSupportedRoute('https://evil.example.com'), isNull);
      expect(BannerRouteValidator.resolveSupportedRoute('//evil.example.com'), isNull);
    });
  });

  group('BannerCarousel & DynamicBannerSlot widget tests', () {
    testWidgets('single-slide banner renders without carousel slide indicators', (tester) async {
      final banner = DynamicBanner.fromMap('single_img', {
        'pageType': 'home',
        'placement': 'hero',
        'isActive': true,
        'carouselEnabled': false,
        'autoplay': false,
        'mediaType': 'image',
        'desktop': {'url': 'https://example.com/banner1.jpg'},
        'title': 'Single Hero Banner',
        'cta': {'label': 'Shop Now', 'route': '/products'},
      });

      String? navigatedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BannerCarousel(
              banner: banner,
              onNavigate: (route) => navigatedTo = route,
            ),
          ),
        ),
      );

      expect(find.text('Single Hero Banner'), findsOneWidget);
      expect(find.text('Shop Now'), findsOneWidget);
      expect(find.byKey(const ValueKey('banner_slide_indicators')), findsNothing);

      await tester.tap(find.text('Shop Now'));
      expect(navigatedTo, '/categories');
    });

    testWidgets('multi-slide banner renders indicators and supports manual swipe', (tester) async {
      final banner = DynamicBanner.fromMap('multi_img', {
        'pageType': 'home',
        'placement': 'hero',
        'isActive': true,
        'carouselEnabled': true,
        'autoplay': false,
        'loop': true,
        'slides': [
          {
            'id': 's1',
            'mediaType': 'image',
            'sortOrder': 1,
            'desktop': {'url': 'https://example.com/s1.jpg'},
            'title': 'Slide One',
          },
          {
            'id': 's2',
            'mediaType': 'image',
            'sortOrder': 2,
            'desktop': {'url': 'https://example.com/s2.jpg'},
            'title': 'Slide Two',
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BannerCarousel(banner: banner),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('banner_slide_indicators')), findsOneWidget);
      expect(find.text('Slide One'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Slide Two'), findsOneWidget);
    });

    testWidgets('DynamicBannerSlot renders matching banners from provider and collapses when empty', (tester) async {
      final banner = DynamicBanner.fromMap('slot_doc', {
        'pageType': 'product',
        'pageId': 'prod_99',
        'placement': 'strip',
        'isActive': true,
        'carouselEnabled': false,
        'autoplay': false,
        'mediaType': 'image',
        'desktop': {'url': 'https://example.com/strip.jpg'},
        'title': 'Product Promo Strip',
      });

      const matchingQuery = BannerQuery(
        pageType: BannerPageType.product,
        placement: BannerPlacement.strip,
        pageId: 'prod_99',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dynamicBannersProvider(matchingQuery).overrideWith((ref) => Stream.value([banner])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DynamicBannerSlot(
                pageType: BannerPageType.product,
                placement: BannerPlacement.strip,
                pageId: 'prod_99',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Product Promo Strip'), findsOneWidget);
    });
  });
}
