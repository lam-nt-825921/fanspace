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
                  const SizedBox(height: 24),

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
                    decoration: const InputDecoration(
                      labelText: 'Chế độ gia nhập',
                      prefixIcon: Icon(Icons.door_front_door_outlined, color: AppTheme.textSecondary),
                    ),
                    dropdownColor: AppTheme.surface,
                    items: const [
                      DropdownMenuItem(
                        value: 'OPEN',
                        child: Text('Tự do (Open) - Bất kỳ ai cũng có thể vào ngay'),
                      ),
                      DropdownMenuItem(
                        value: 'APPROVAL',
                        child: Text('Xét duyệt (Approval) - Cần Owner/Mod duyệt đơn'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _admissionMode = v);
                    },
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
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: fandomProvider.isLoading ? null : _handleCreateFandom,
                    child: fandomProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('KHỞI TẠO KHÔNG GIAN FANDOM'),
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
