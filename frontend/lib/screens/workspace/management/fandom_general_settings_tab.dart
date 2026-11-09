/// General settings, profile appearance, and Danger Zone tab inside FandomManagementDialog (FR-07).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import 'widgets/fandom_branding_editor.dart';
import 'widgets/fandom_gallery_editor.dart';

class FandomGeneralSettingsTab extends StatefulWidget {
  final FandomDetailModel fandom;
  final ValueChanged<FandomDetailModel> onFandomUpdated;
  final VoidCallback? onDeleteRequested;

  const FandomGeneralSettingsTab({
    super.key,
    required this.fandom,
    required this.onFandomUpdated,
    this.onDeleteRequested,
  });

  @override
  State<FandomGeneralSettingsTab> createState() =>
      _FandomGeneralSettingsTabState();
}

class _FandomGeneralSettingsTabState extends State<FandomGeneralSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _rulesController;

  late String _selectedCategory;
  late String _admissionMode;
  late bool _isPublic;
  String? _avatarUrl;
  String? _bannerUrl;
  late List<String> _illustrationUrls;

  bool _isSaving = false;
  bool _isUpdatingVisibility = false;

  @override
  void initState() {
    super.initState();
    final f = widget.fandom;
    _nameController = TextEditingController(text: f.name);
    _descriptionController = TextEditingController(text: f.description ?? '');
    _rulesController = TextEditingController(text: f.rulesTos ?? '');
    _selectedCategory = f.category;
    _admissionMode = f.admissionMode;
    _isPublic = f.isPublic;
    _avatarUrl = f.avatarUrl;
    _bannerUrl = f.bannerUrl;
    _illustrationUrls = List<String>.from(f.illustrationUrls);
  }

  @override
  void didUpdateWidget(covariant FandomGeneralSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fandom.id != widget.fandom.id) {
      final f = widget.fandom;
      _nameController.text = f.name;
      _descriptionController.text = f.description ?? '';
      _rulesController.text = f.rulesTos ?? '';
      _selectedCategory = f.category;
      _admissionMode = f.admissionMode;
      _isPublic = f.isPublic;
      _avatarUrl = f.avatarUrl;
      _bannerUrl = f.bannerUrl;
      _illustrationUrls = List<String>.from(f.illustrationUrls);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final provider = context.read<FandomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final res = await provider.updateFandomProfile(
      widget.fandom.id,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _selectedCategory,
      avatarUrl: _avatarUrl,
      bannerUrl: _bannerUrl,
      illustrationUrls: _illustrationUrls,
      admissionMode: _admissionMode,
      rulesTos: _rulesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true && res['fandom'] is FandomDetailModel) {
      final updated = res['fandom'] as FandomDetailModel;
      widget.onFandomUpdated(updated);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? 'Đã lưu thay đổi hồ sơ Fandom.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res['error']?.toString() ?? 'Không thể cập nhật hồ sơ Fandom.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleToggleVisibility(bool val) async {
    setState(() => _isUpdatingVisibility = true);
    final provider = context.read<FandomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final res = await provider.updateFandomVisibility(
      widget.fandom.id,
      val,
    );

    if (!mounted) return;
    setState(() => _isUpdatingVisibility = false);

    if (res['success'] == true) {
      setState(() => _isPublic = val);
      final updated = widget.fandom.copyWith(isPublic: val);
      widget.onFandomUpdated(updated);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? 'Đã cập nhật trạng thái hiển thị.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res['error']?.toString() ?? 'Không thể cập nhật trạng thái hiển thị.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final categories = AppConstants.defaultCategories
        .where((c) => c != 'Tất cả')
        .toList();

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Branding: Avatar and Banner
            FandomBrandingEditor(
              fandomId: widget.fandom.id,
              fandomName: widget.fandom.name,
              initialAvatarUrl: _avatarUrl,
              initialBannerUrl: _bannerUrl,
              onAvatarChanged: (url) => setState(() => _avatarUrl = url),
              onBannerChanged: (url) => setState(() => _bannerUrl = url),
            ),
            const SizedBox(height: 20),

            // 2. Fandom Name
            Text(
              'Tên Fandom',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('field_fandom_name'),
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Nhập tên cộng đồng Fandom',
                prefixIcon: Icon(Icons.groups_outlined, size: 20),
              ),
              validator: (val) {
                if (val == null || val.trim().length < 2) {
                  return 'Tên Fandom tối thiểu 2 ký tự.';
                }
                if (val.trim().length > 100) {
                  return 'Tên Fandom tối đa 100 ký tự.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 3. Category
            Text(
              'Chủ đề Fandom',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: const Key('dropdown_fandom_category'),
              initialValue: categories.contains(_selectedCategory)
                  ? _selectedCategory
                  : categories.first,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.category_outlined, size: 20),
              ),
              items: categories
                  .map(
                    (cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedCategory = val);
                }
              },
            ),
            const SizedBox(height: 16),

            // 4. Description
            Text(
              'Bài giới thiệu chi tiết',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('field_fandom_description'),
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Giới thiệu về thần tượng, mục tiêu và văn hóa của cộng đồng',
                alignLabelWithHint: true,
              ),
              validator: (val) {
                if (val != null && val.length > 5000) {
                  return 'Mô tả tối đa 5.000 ký tự.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // 5. Admission Mode
            Text(
              'Chính sách xét duyệt thành viên',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const Key('segmented_admission_mode'),
              segments: const [
                ButtonSegment(
                  value: 'OPEN',
                  label: Text('Gia nhập tự do'),
                  icon: Icon(Icons.lock_open_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'APPROVAL',
                  label: Text('Phê duyệt xét tuyển'),
                  icon: Icon(Icons.how_to_reg_outlined, size: 16),
                ),
              ],
              selected: {_admissionMode},
              onSelectionChanged: (newSelection) {
                setState(() => _admissionMode = newSelection.first);
              },
            ),
            const SizedBox(height: 6),
            Text(
              _admissionMode == 'OPEN'
                  ? 'Bất kỳ ai cũng có thể gia nhập và trò chuyện ngay lập tức.'
                  : 'Người dùng cần gửi đơn xin gia nhập và chờ bạn xét duyệt trước khi vào.',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),

            // 6. Rules & TOS
            Text(
              'Nội quy & Điều khoản Fandom',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('field_fandom_rules'),
              controller: _rulesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Quy tắc ứng xử, văn hóa giao tiếp trong không gian Fandom',
                alignLabelWithHint: true,
              ),
              validator: (val) {
                if (val != null && val.length > 10000) {
                  return 'Nội quy tối đa 10.000 ký tự.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // 7. Illustration Gallery Editor
            FandomGalleryEditor(
              fandomId: widget.fandom.id,
              initialUrls: _illustrationUrls,
              onChanged: (urls) => setState(() => _illustrationUrls = urls),
            ),
            const SizedBox(height: 24),

            // 8. Save Profile Button
            ElevatedButton.icon(
              key: const Key('btn_save_fandom_profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isSaving ? null : _handleSaveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(
                _isSaving ? 'Đang lưu...' : 'Lưu thay đổi hồ sơ',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 28),

            Divider(color: palette.border),
            const SizedBox(height: 16),

            // 9. Visibility Toggle
            Text(
              'Chế độ hiển thị không gian',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: palette.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: palette.border),
              ),
              child: SwitchListTile(
                key: const Key('switch_fandom_visibility'),
                value: _isPublic,
                activeThumbColor: AppTheme.primary,
                title: Text(
                  _isPublic ? 'Chế độ Công khai' : 'Chế độ Riêng tư',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _isPublic
                      ? 'Fandom xuất hiện trên Danh mục Khám phá công khai.'
                      : 'Ẩn khỏi Danh mục Khám phá, chỉ truy cập qua liên kết hoặc mã mời.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                onChanged: _isUpdatingVisibility
                    ? null
                    : _handleToggleVisibility,
              ),
            ),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  GoRouter.maybeOf(context)?.go('/fandoms/${widget.fandom.slug}');
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Xem Trang giới thiệu Fandom'),
              ),
            ),
            const SizedBox(height: 24),

            Divider(color: palette.border),
            const SizedBox(height: 16),

            // 10. Danger Zone (Delete Fandom)
            const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.error,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Khu vực nguy hiểm',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Xóa hoàn toàn không gian Fandom này cùng toàn bộ kênh thảo luận, tin nhắn chat và vai trò thành viên. Hành động này không thể hoàn tác.',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('btn_trigger_delete_fandom'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('XÓA VĨNH VIỄN FANDOM NÀY'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDeleteRequested?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
