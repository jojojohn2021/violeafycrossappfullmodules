import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';

class LeafyTopAppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const LeafyTopAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(66);

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

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 6),
      child: SafeArea(
        child: Row(
          children: [
            // Left: Logo & Brand
            GestureDetector(
              onTap: () => context.go('/'),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/Logo.png',
                      height: 36,
                      width: 36,
                      errorBuilder: (_, __, ___) => Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.eco, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Leafy',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Center: Search Bar (Height 48, Pill Rounded)
            Expanded(
              child: GestureDetector(
                onTap: () => context.go('/search'),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ref.watch(searchQueryProvider).isEmpty
                              ? 'Search Fruits, Vegetables, Spices...'
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
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Right Action Buttons: Voice, Image, Cart, Notifications
            IconButton(
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? AppColors.primaryGreen : AppColors.textPrimary, size: 22),
              onPressed: _listenVoiceSearch,
              tooltip: 'Voice Search',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: AppColors.textPrimary, size: 22),
              onPressed: _pickImageSearch,
              tooltip: 'Photo Search',
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
    );
  }
}
