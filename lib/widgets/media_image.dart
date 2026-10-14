import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/media_ref.dart';

/// On web, image_picker returns a blob URL instead of a file path, and
/// `dart:io` files cannot be read, so local images go through the network
/// loader there.
ImageProvider localImageProvider(String path) =>
    kIsWeb ? NetworkImage(path) : FileImage(File(path));

/// Image for a picked photo, or `null` for demo samples, which are drawn as
/// the fallback instead.
ImageProvider? mediaImageProvider(MediaRef? media) {
  final path = media?.path;
  return path == null ? null : localImageProvider(path);
}

class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.media,
    this.fit = BoxFit.cover,
    this.fallback,
    this.semanticLabel,
  });

  final MediaRef media;
  final BoxFit fit;
  final Widget? fallback;

  /// Describes the image for screen readers; `null` marks it decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = mediaImageProvider(media);
    final placeholder = Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: fallback ?? const Icon(Icons.image_outlined),
    );
    if (image == null) return placeholder;
    return Image(
      image: image,
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, _, _) =>
          fallback ?? const Icon(Icons.broken_image_outlined),
    );
  }
}
