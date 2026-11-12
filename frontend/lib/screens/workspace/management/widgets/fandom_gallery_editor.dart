/// Gallery editor widget for managing illustration images and short video (FR-07).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/fandom_provider.dart';

class FandomGalleryEditor extends StatefulWidget {
  final String fandomId;
  final List<String> initialUrls;
  final ValueChanged<List<String>> onChanged;

  const FandomGalleryEditor({
    super.key,
    required this.fandomId,
    required this.initialUrls,
    required this.onChanged,
  });

  @override
  State<FandomGalleryEditor> createState() => _FandomGalleryEditorState();
}

class _FandomGalleryEditorState extends State<FandomGalleryEditor> {
  late List<String> _urls;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _urls = List<String>.from(widget.initialUrls);
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.contains('/video/upload/');
  }

  int get _videoCount => _urls.where(_isVideoUrl).length;

  Future<void> _pickAndUploadMedia() async {
    if (_urls.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bộ sưu tập đã đạt tối đa 5 tệp minh họa.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<FandomProvider>();

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'webm'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Không thể đọc dữ liệu tệp được chọn.')),
        );
        return;
      }

      final ext = file.extension?.toLowerCase() ?? '';
      final isVideo = ext == 'mp4' || ext == 'webm';

      if (isVideo && _videoCount >= 1) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Bộ sưu tập chỉ được chứa tối đa 1 video ngắn.',
            ),
          ),
        );
        return;
      }

      final maxBytes = isVideo ? 15 * 1024 * 1024 : 5 * 1024 * 1024;
      final maxLabel = isVideo ? '15 MB' : '5 MB';
      if (bytes.length > maxBytes) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isVideo
                  ? 'Video ngắn tối đa $maxLabel.'
                  : 'Hình ảnh tối đa $maxLabel.',
            ),
          ),
        );
        return;
      }

      setState(() => _isUploading = true);

      final uploadedUrl = await provider.uploadFandomMedia(
        bytes: bytes,
        filename: file.name,
        target: 'FANDOM_ILLUSTRATION',
        fandomId: widget.fandomId,
      );

      if (!mounted) return;
      setState(() => _isUploading = false);

      if (uploadedUrl != null) {
        setState(() {
          _urls.add(uploadedUrl);
        });
        widget.onChanged(_urls);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isVideo
                  ? 'Đã thêm video ngắn vào bộ sưu tập.'
                  : 'Đã thêm hình ảnh vào bộ sưu tập.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Không thể tải tệp lên. Vui lòng thử lại.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Lỗi tải tệp: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _removeMediaAt(int index) {
    setState(() {
      _urls.removeAt(index);
    });
    widget.onChanged(_urls);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Bộ sưu tập ảnh & video minh họa',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_urls.length} / 5',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tối đa 5 tệp hình ảnh hoặc video ngắn minh họa • Tối đa 1 video ngắn dưới 60 giây',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < _urls.length; i++)
              _buildThumbnailCard(context, palette, _urls[i], i),
            if (_urls.length < 5)
              _buildAddMediaButton(context, palette),
          ],
        ),
      ],
    );
  }

  Widget _buildThumbnailCard(
    BuildContext context,
    AppPalette palette,
    String url,
    int index,
  ) {
    final isVideo = _isVideoUrl(url);

    return Container(
      width: 100,
      height: 80,
      decoration: BoxDecoration(
        color: palette.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: isVideo
                ? Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 32,
                      ),
                    ),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: palette.textMuted,
                        size: 24,
                      ),
                    ),
                  ),
          ),
          if (isVideo)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'VIDEO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 3,
            right: 3,
            child: InkWell(
              key: Key('btn_remove_media_$index'),
              onTap: () => _removeMediaAt(index),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMediaButton(BuildContext context, AppPalette palette) {
    return InkWell(
      key: const Key('btn_add_fandom_media'),
      onTap: _isUploading ? null : _pickAndUploadMedia,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 100,
        height: 80,
        decoration: BoxDecoration(
          color: palette.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: palette.border,
            style: BorderStyle.solid,
          ),
        ),
        child: _isUploading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 24,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Thêm tệp',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
