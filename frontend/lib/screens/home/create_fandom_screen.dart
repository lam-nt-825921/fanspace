import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/fandom_provider.dart';
import '../auth/widgets/theme_toggle_button.dart';

class CreateFandomScreen extends StatefulWidget {
  const CreateFandomScreen({super.key});

  @override
  State<CreateFandomScreen> createState() => _CreateFandomScreenState();
}

class _CreateFandomScreenState extends State<CreateFandomScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _selectedCategory = 'Âm nhạc';
  String _admissionMode = 'OPEN';
  bool _isPublic = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FandomProvider>().fetchMyFandoms();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  void _generateSlug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    _slugController.text = slug;
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _handleCreateFandom() async {
    if (_formKey.currentState!.validate()) {
      final fandomProvider =
          Provider.of<FandomProvider>(context, listen: false);
      final targetSlug = _slugController.text.trim().toLowerCase();
      final success = await fandomProvider.createFandom(
        name: _nameController.text.trim(),
        slug: targetSlug,
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        admissionMode: _admissionMode,
        isPublic: _isPublic,
        rulesTos: _rulesController.text.trim().isNotEmpty
            ? _rulesController.text.trim()
            : null,
      );

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tạo không gian Fandom thành công! Bạn là Chủ Fandom (Owner).',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
        if (context.canPop()) {
          Navigator.pop(context);
        } else {
          context.go('/fandoms/$targetSlug/space');
        }
      } else if (fandomProvider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fandomProvider.errorMessage!),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fandomProvider = context.watch<FandomProvider>();

    final categories = AppConstants.defaultCategories
        .where((c) => c != 'Tất cả')
        .toList();

    final quotaUsed = fandomProvider.myFandoms?.quotaUsed ?? 0;
    final maxQuota = fandomProvider.myFandoms?.maxQuota ?? 5;
    final isQuotaReached = quotaUsed >= maxQuota;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _navigateBack,
        ),
        title: const Text('Khởi tạo Fandom mới'),
        actions: [
          TextButton.icon(
            onPressed: _navigateBack,
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Trang chủ'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: ThemeToggleButton(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Không gian Fandom Biệt lập',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bạn sẽ toàn quyền quản lý, tạo vai trò, thiết lập gói hội viên và các kênh trò chuyện thời gian thực.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quota Indicator Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isQuotaReached
                            ? AppTheme.error.withValues(alpha: 0.12)
                            : AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isQuotaReached
                              ? AppTheme.error.withValues(alpha: 0.4)
                              : AppTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isQuotaReached
                                ? Icons.warning_amber_rounded
                                : Icons.pie_chart_outline,
                            size: 20,
                            color: isQuotaReached
                                ? AppTheme.error
                                : AppTheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isQuotaReached
                                  ? 'Hạn ngạch Fandom: $quotaUsed/$maxQuota (Đã đạt giới hạn tối đa)'
                                  : 'Hạn ngạch Fandom: $quotaUsed/$maxQuota không gian đã tạo',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isQuotaReached
                                    ? AppTheme.error
                                    : palette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Fandom Name
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Tên Fandom (Ví dụ: BLACKPINK Việt Nam)',
                        prefixIcon: Icon(
                          Icons.groups_outlined,
                          color: palette.textSecondary,
                        ),
                      ),
                      onChanged: (v) {
                        if (_slugController.text.isEmpty ||
                            _slugController.text ==
                                _generateSlugString(
                                  v.substring(
                                    0,
                                    v.length > 1 ? v.length - 1 : 0,
                                  ),
                                )) {
                          _generateSlug(v);
                        }
                      },
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Tên Fandom tối thiểu 2 ký tự'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Fandom Slug
                    TextFormField(
                      controller: _slugController,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Đường dẫn định danh (Slug độc nhất)',
                        prefixText: '@',
                        prefixIcon: Icon(
                          Icons.link,
                          color: palette.textSecondary,
                        ),
                        helperText:
                            'Ví dụ: blackpink-vn -> /fandoms/blackpink-vn',
                      ),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Slug tối thiểu 2 ký tự'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Chủ đề / Phân loại',
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          color: palette.textSecondary,
                        ),
                      ),
                      dropdownColor: palette.surface,
                      items: categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedCategory = v);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Admission Mode
                    DropdownButtonFormField<String>(
                      initialValue: _admissionMode,
                      isExpanded: true,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Chế độ gia nhập',
                        prefixIcon: Icon(
                          Icons.door_front_door_outlined,
                          color: palette.textSecondary,
                        ),
                      ),
                      dropdownColor: palette.surface,
                      items: const [
                        DropdownMenuItem(
                          value: 'OPEN',
                          child: Text('Tự do (Open) - Vào ngay'),
                        ),
                        DropdownMenuItem(
                          value: 'APPROVAL',
                          child: Text('Xét duyệt (Approval) - Cần duyệt'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _admissionMode = v);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Public / Private Switch
                    Material(
                      color: palette.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: palette.border),
                      ),
                      child: SwitchListTile(
                        value: _isPublic,
                        onChanged: (val) => setState(() => _isPublic = val),
                        title: Text(
                          'Công khai trên Danh mục Khám phá',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          _isPublic
                              ? 'Mọi người có thể tìm thấy và xem trước không gian Fandom của bạn.'
                              : 'Fandom sẽ ở chế độ Riêng tư (chỉ vào qua mã mời hoặc link chia sẻ).',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Mô tả giới thiệu Fandom',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Rules
                    TextFormField(
                      controller: _rulesController,
                      maxLines: 2,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Nội quy & Điều khoản (Tùy chọn)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (isQuotaReached) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.error.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.block, color: AppTheme.error, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bạn đã đạt giới hạn tối đa 5 Fandom sở hữu. Hãy xóa bớt Fandom không còn dùng để tạo không gian mới.',
                                style: TextStyle(
                                  color: AppTheme.error,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _navigateBack,
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                (fandomProvider.isLoading || isQuotaReached)
                                    ? null
                                    : _handleCreateFandom,
                            child: fandomProvider.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    isQuotaReached
                                        ? 'ĐÃ ĐẠT GIỚI HẠN 5 FANDOM'
                                        : 'KHỞI TẠO KHÔNG GIAN FANDOM',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _generateSlugString(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }
}
