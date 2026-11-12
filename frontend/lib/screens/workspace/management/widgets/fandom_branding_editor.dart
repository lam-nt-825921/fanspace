/// Branding editor widget for selecting and uploading Fandom Avatar and Banner.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/fandom_provider.dart';

class FandomBrandingEditor extends StatefulWidget {
  final String fandomId;
  final String fandomName;
  final String? initialAvatarUrl;
  final String? initialBannerUrl;
  final ValueChanged<String?> onAvatarChanged;
  final ValueChanged<String?> onBannerChanged;

  const FandomBrandingEditor({
    super.key,
    required this.fandomId,
    required this.fandomName,
    this.initialAvatarUrl,
    this.initialBannerUrl,
    required this.onAvatarChanged,
    required this.onBannerChanged,
  });

  @override
  State<FandomBrandingEditor> createState() => _FandomBrandingEditorState();
}

class _FandomBrandingEditorState extends State<FandomBrandingEditor> {
  String? _avatarUrl;
  String? _bannerUrl;
  bool _isUploadingAvatar = false;
  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.initialAvatarUrl;
    _bannerUrl = widget.initialBannerUrl;
  }

  Future<void> _pickAndUploadImage({required bool isAvatar}) async {
    final provider = context.read<FandomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Không thể đọc dữ liệu hình ảnh đã chọn.'),
          ),
        );
        return;
      }

      final maxBytes = isAvatar ? 2 * 1024 * 1024 : 5 * 1024 * 1024;
      final maxLabel = isAvatar ? '2 MB' : '5 MB';
      if (bytes.length > maxBytes) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isAvatar
                  ? 'Ảnh đại diện tối đa $maxLabel.'
                  : 'Ảnh bìa tối đa $maxLabel.',
            ),
          ),
        );
        return;
      }

      setState(() {
        if (isAvatar) {
          _isUploadingAvatar = true;
        } else {
          _isUploadingBanner = true;
        }
      });

      final uploadedUrl = await provider.uploadFandomMedia(
        bytes: bytes,
        filename: file.name,
        target: isAvatar ? 'FANDOM_AVATAR' : 'FANDOM_BANNER',
        fandomId: widget.fandomId,
      );

      if (!mounted) return;
      setState(() {
        if (isAvatar) {
          _isUploadingAvatar = false;
          if (uploadedUrl != null) {
            _avatarUrl = uploadedUrl;
            widget.onAvatarChanged(uploadedUrl);
          }
        } else {
          _isUploadingBanner = false;
          if (uploadedUrl != null) {
            _bannerUrl = uploadedUrl;
            widget.onBannerChanged(uploadedUrl);
          }
        }
      });

      if (uploadedUrl != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isAvatar
                  ? 'Đã tải lên ảnh đại diện mới.'
                  : 'Đã tải lên ảnh bìa mới.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Không thể tải tệp lên máy chủ. Vui lòng thử lại.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingAvatar = false;
        _isUploadingBanner = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tải ảnh: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hình ảnh nhận diện Fandom',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Banner Area
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                  image: _bannerUrl != null && _bannerUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_bannerUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _bannerUrl == null || _bannerUrl!.isEmpty
                    ? Center(
                        child: Text(
                          'Chưa thiết lập ảnh bìa',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : null,
              ),

              // Banner Edit Button
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  key: const Key('btn_change_fandom_banner'),
                  onTap: _isUploadingBanner
                      ? null
                      : () => _pickAndUploadImage(isAvatar: false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isUploadingBanner)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          const Icon(
                            Icons.camera_alt_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _bannerUrl != null ? 'Đổi ảnh bìa' : 'Thêm ảnh bìa',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Avatar Area (Overlapping bottom left)
              Positioned(
                bottom: 6,
                left: 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: AppTheme.primary,
                        backgroundImage:
                            _avatarUrl != null && _avatarUrl!.isNotEmpty
                                ? NetworkImage(_avatarUrl!)
                                : null,
                        child: _avatarUrl == null || _avatarUrl!.isEmpty
                            ? Text(
                                widget.fandomName.isNotEmpty
                                    ? widget.fandomName[0].toUpperCase()
                                    : 'F',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: InkWell(
                        key: const Key('btn_change_fandom_avatar'),
                        onTap: _isUploadingAvatar
                            ? null
                            : () => _pickAndUploadImage(isAvatar: true),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.surface,
                              width: 2,
                            ),
                          ),
                          child: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  size: 13,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Khuyến nghị ảnh bìa tỷ lệ 16:9 dung lượng tối đa 5 MB • Ảnh đại diện tỷ lệ 1:1 tối đa 2 MB',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
