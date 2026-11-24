import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/atlas_models.dart';
import '../domain/atlas_providers.dart';

class AtlasThumb extends ConsumerWidget {
  const AtlasThumb({super.key, required this.atlasId, this.size = 72});
  final String atlasId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (atlasId.isEmpty) return SizedBox(width: size, height: size);
    final url = atlasAssetUrl('thumb', atlasId);
    return FutureBuilder<Uint8List?>(
      future: ref.read(atlasMediaCacheProvider).get(Uri.parse(url)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: bytes == null
                ? ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  )
                : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        );
      },
    );
  }
}
