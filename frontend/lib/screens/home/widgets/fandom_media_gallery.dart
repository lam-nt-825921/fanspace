import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Horizontal media gallery displaying Fandom illustrations and videos with lightbox preview.
class FandomMediaGallery extends StatelessWidget {
  final List<String> illustrationUrls;

  const FandomMediaGallery({
    super.key,
    required this.illustrationUrls,
  });

  static bool isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.contains('/video/upload/');
  }

  static Future<void> openMediaUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static void showImageLightbox(BuildContext context, String imageUrl) {
    final palette = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  color: palette.surface,
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Không thể tải ảnh.',
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (illustrationUrls.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 20,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              'Bộ sưu tập & Đa phương tiện',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${illustrationUrls.length} tệp',
                style: TextStyle(
                  fontSize: 11,
                  color: palette.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: illustrationUrls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final url = illustrationUrls[index];
              final isVideo = isVideoUrl(url);
              final String displayUrl =
                  isVideo && url.contains('/video/upload/')
                      ? url
                          .replaceFirst('/video/upload/', '/video/upload/so_1/')
                          .replaceAll(RegExp(r'\.(mp4|webm|mov)$'), '.jpg')
                      : url;

              return InkWell(
                onTap: () {
                  if (isVideo) {
                    openMediaUrl(url);
                  } else {
                    showImageLightbox(context, url);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        displayUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: palette.surfaceLight,
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.broken_image,
                            color: palette.textSecondary,
                            size: 32,
                          ),
                        ),
                      ),
                      if (isVideo) ...[
                        Container(color: Colors.black38),
                        const Center(
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}
