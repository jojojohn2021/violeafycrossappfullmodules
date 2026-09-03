import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';

String _getPlatformAppLogoAsset() {
  if (kIsWeb) {
    return 'assets/web/icon-512.png';
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    return 'assets/android/res/mipmap-hdpi/ic_launcher.png';
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    return 'assets/ios/AppIcon@3x.png';
  }
  return 'assets/logo.png';
}

class LeafyTopAppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const LeafyTopAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(110);

  @override
  ConsumerState<LeafyTopAppBar> createState() => _LeafyTopAppBarState();
}

class _LeafyTopAppBarState extends ConsumerState<LeafyTopAppBar> {
  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  void _listenVoiceSearch() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (errorNotification) {
          if (mounted) setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _showVoiceListeningModal();

        _speech.listen(
          onResult: (result) {
            if (result.recognizedWords.isNotEmpty) {
              ref.read(searchQueryProvider.notifier).state = result.recognizedWords;
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pop();
                context.go('/search');
              }
            }
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice recognition not available on this device.')),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _showVoiceListeningModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: AppColors.primaryGreen, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Listening...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Say "Mangoes", "Palak", "Spices" or any product name',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) {
      if (_isListening) {
        _speech.stop();
        setState(() => _isListening = false);
      }
    });
  }

  void _pickImageSearch() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Searching catalog for matching products from photo...'),
          duration: Duration(seconds: 2),
        ),
      );
      ref.read(searchQueryProvider.notifier).state = 'Fresh';
      context.go('/search');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final totalItems = cartItems.fold(0, (sum, i) => sum + i.quantity);

    final user = ref.watch(authStateProvider).asData?.value;
    final customer = ref.watch(currentUserCustomerProvider).asData?.value;

    String userMobileNumber = 'Guest';
    if (user != null) {
      if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty) {
        userMobileNumber = user.phoneNumber!.trim();
      } else if (customer != null && customer.mobileNumber.trim().isNotEmpty) {
        userMobileNumber = customer.mobileNumber.trim();
      } else if (user.email != null && user.email!.trim().isNotEmpty) {
        userMobileNumber = user.email!.trim();
      }
    }

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Logo & Greeting on Left, Badges & Actions on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Logo & Brand + User Greeting
                GestureDetector(
                  onTap: () => context.go('/'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          _getPlatformAppLogoAsset(),
                          height: 34,
                          width: 34,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/logo.png',
                            height: 34,
                            width: 34,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              height: 34,
                              width: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.eco, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Leafyearth ',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryGreen,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Hello,',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w300,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              userMobileNumber,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Action Buttons: Wishlist, Cart, Orders
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.favorite_border_outlined, color: AppColors.textPrimary, size: 22),
                          onPressed: () => context.push('/wishlist'),
                          tooltip: 'Wishlist',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        IconButton(
                          icon: const Icon(Icons.receipt_long_outlined, color: AppColors.textPrimary, size: 22),
                          onPressed: () => context.push('/orders'),
                          tooltip: 'My Orders',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.shopping_cart_outlined, color: AppColors.textPrimary, size: 22),
                              onPressed: () => context.push('/cart'),
                              tooltip: 'Cart',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                            if (totalItems > 0)
                              Positioned(
                                right: 4,
                                top: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  child: Text(
                                    '$totalItems',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Next Line: Search Bar with Voice and Picture Options
            GestureDetector(
              onTap: () => context.go('/search'),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.secondaryBackground,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                padding: const EdgeInsets.only(left: 12, right: 6),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ref.watch(searchQueryProvider).isEmpty
                            ? 'Search Original, Organic, Authentic...'
                            : ref.watch(searchQueryProvider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ref.watch(searchQueryProvider).isEmpty
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? AppColors.primaryGreen : AppColors.textPrimary,
                        size: 20,
                      ),
                      onPressed: _listenVoiceSearch,
                      tooltip: 'Voice Search',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                      onPressed: _pickImageSearch,
                      tooltip: 'Photo Search',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
