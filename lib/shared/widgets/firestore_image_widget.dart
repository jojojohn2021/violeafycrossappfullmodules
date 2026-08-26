import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';

class FirestoreImageWidget extends ConsumerWidget {
  final String collection;
  final String? docIdOrRef;
  final String? directImageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallbackWidget;

  const FirestoreImageWidget({
    super.key,
    required this.collection,
    this.docIdOrRef,
    this.directImageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If a direct valid HTTP image URL exists on the model, use it directly
    if (directImageUrl != null && directImageUrl!.startsWith('http')) {
      return Image.network(
        directImageUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            fallbackWidget ?? _buildDefaultFallback(),
      );
    }

    final idToFetch = docIdOrRef?.trim() ?? '';
    if (idToFetch.isEmpty) {
      return fallbackWidget ?? _buildDefaultFallback();
    }

    final asyncImage = ref.watch(
      firestoreImageProvider((collection: collection, docIdOrRef: idToFetch)),
    );

    return asyncImage.when(
      data: (url) {
        if (url != null && url.isNotEmpty) {
          if (url.startsWith('http')) {
            return Image.network(
              url,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (context, error, stackTrace) =>
                  fallbackWidget ?? _buildDefaultFallback(),
            );
          }
        }
        return fallbackWidget ?? _buildDefaultFallback();
      },
      loading: () => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => fallbackWidget ?? _buildDefaultFallback(),
    );
  }

  Widget _buildDefaultFallback() {
    return Icon(
      Icons.image_not_supported_outlined,
      size: (width != null && height != null) ? (width! * 0.4) : 24,
      color: Colors.grey,
    );
  }
}
