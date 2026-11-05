import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/fandom_provider.dart';

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

  Future<void> _handleCreateFandom() async {
    if (_formKey.currentState!.validate()) {
      final fandomProvider = Provider.of<FandomProvider>(context, listen: false);
      final success = await fandomProvider.createFandom(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim().toLowerCase(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        admissionMode: _admissionMode,
        isPublic: _isPublic,
        rulesTos: _rulesController.text.trim().isNotEmpty ? _rulesController.text.trim() : null,
      );

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tạo không gian Fandom thành công! Bạn là Chủ Fandom (Owner).'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
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
    final fandomProvider = context.watch<FandomProvider>();

    final categories = AppConstants.defaultCategories
        .where((c) => c != 'Tất cả')
        .toList();

    final quotaUsed = fandomProvider.myFandoms?.quotaUsed ?? 0;
    final maxQuota = fandomProvider.myFandoms?.maxQuota ?? 5;
    final isQuotaReached = quotaUsed >= maxQuota;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khởi tạo Fandom mới'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Không gian Fandom Biệt lập',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Bạn sẽ toàn quyền quản lý, tạo vai trò, thiết lập gói hội viên và các kênh trò chuyện thời gian thực.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Quota Indicator Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isQuotaReached
                          ? AppTheme.error.withOpacity(0.12)
                          : AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isQuotaReached
                            ? AppTheme.error.withOpacity(0.4)
                            : AppTheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isQuotaReached ? Icons.warning_amber_rounded : Icons.pie_chart_outline,
                          size: 20,
                          color: isQuotaReached ? AppTheme.error : AppTheme.primary,
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
                              color: isQuotaReached ? AppTheme.error : AppTheme.textPrimary,
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
                    decoration: const InputDecoration(
                      labelText: 'Tên Fandom (Ví dụ: BLACKPINK Việt Nam)',
                      prefixIcon: Icon(Icons.groups_outlined, color: AppTheme.textSecondary),
                    ),
                    onChanged: (v) {
                      if (_slugController.text.isEmpty || _slugController.text == _generateSlugString(v.substring(0, v.length > 1 ? v.length - 1 : 0))) {
                        _generateSlug(v);
                      }
                    },
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Tên Fandom tối thiểu 2 ký tự' : null,
                  ),
                  const SizedBox(height: 16),

                  // Fandom Slug
                  TextFormField(
                    controller: _slugController,
                    decoration: const InputDecoration(
                      labelText: 'Đường dẫn định danh (Slug độc nhất)',
                      prefixText: '@',
                      prefixIcon: Icon(Icons.link, color: AppTheme.textSecondary),
                      helperText: 'Ví dụ: blackpink-vn -> fanspace.app/fandom/blackpink-vn',
                    ),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Slug tối thiểu 2 ký tự' : null,
                  ),
                  const SizedBox(height: 16),

                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Chủ đề / Phân loại',
                      prefixIcon: Icon(Icons.category_outlined, color: AppTheme.textSecondary),
                    ),
                    dropdownColor: AppTheme.surface,
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                    decoration: const InputDecoration(
                      labelText: 'Chế độ gia nhập',
                      prefixIcon: Icon(Icons.door_front_door_outlined, color: AppTheme.textSecondary),
                    ),
                    dropdownColor: AppTheme.surface,
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
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.surfaceLight),
                    ),
                    child: SwitchListTile(
                      value: _isPublic,
                      onChanged: (val) => setState(() => _isPublic = val),
                      title: const Text(
                        'Công khai trên Danh mục Khám phá',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _isPublic
                            ? 'Mọi người có thể tìm thấy và xem trước không gian Fandom của bạn.'
                            : 'Fandom sẽ ở chế độ Riêng tư (chỉ vào qua mã mời hoặc link chia sẻ).',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      activeColor: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
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
                        color: AppTheme.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.error.withOpacity(0.5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.block, color: AppTheme.error, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Bạn đã đạt giới hạn tối đa 5 Fandom sở hữu. Hãy xóa bớt Fandom không còn dùng để tạo không gian mới.',
                              style: TextStyle(color: AppTheme.error, fontSize: 13, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  ElevatedButton(
                    onPressed: (fandomProvider.isLoading || isQuotaReached)
                        ? null
                        : _handleCreateFandom,
                    child: fandomProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            isQuotaReached
                                ? 'ĐÃ ĐẠT GIỚI HẠN 5 FANDOM'
                                : 'KHỞI TẠO KHÔNG GIAN FANDOM',
                          ),
                  ),
                ],
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
