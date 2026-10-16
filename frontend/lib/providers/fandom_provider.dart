import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../core/constants/app_constants.dart';
import '../models/fandom_model.dart';

class FandomProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  List<FandomSummaryModel> _fandoms = [];
  List<String> _categories = AppConstants.defaultCategories;
  String _selectedCategory = 'Tất cả';
  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;

  List<FandomSummaryModel> get fandoms => _fandoms;
  List<String> get categories => _categories;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchCategories() async {
    try {
      final response = await _apiClient.dio.get('/api/v1/fandoms/public/categories');
      if (response.data is List) {
        _categories = List<String>.from(response.data);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchPublicFandoms() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Map<String, dynamic> queryParams = {};
      if (_selectedCategory != 'Tất cả') {
        queryParams['category'] = _selectedCategory;
      }
      if (_searchQuery.trim().isNotEmpty) {
        queryParams['search'] = _searchQuery.trim();
      }

      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/public',
        queryParameters: queryParams,
      );

      final List data = response.data;
      _fandoms = data.map((json) => FandomSummaryModel.fromJson(json)).toList();
      _isLoading = false;
      notifyListeners();
    } on DioException catch (e) {
      _errorMessage = e.response?.data?['detail'] ?? 'Không thể tải danh sách Fandom.';
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Lỗi kết nối: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
      fetchPublicFandoms();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
    fetchPublicFandoms();
  }

  Future<bool> createFandom({
    required String name,
    required String slug,
    String? description,
    required String category,
    String? avatarUrl,
    String? bannerUrl,
    String admissionMode = 'OPEN',
    String? rulesTos,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiClient.dio.post('/api/v1/fandoms', data: {
        'name': name,
        'slug': slug.toLowerCase().trim(),
        'description': description,
        'category': category,
        'avatar_url': avatarUrl,
        'banner_url': bannerUrl,
        'admission_mode': admissionMode,
        'rules_tos': rulesTos,
      });

      _isLoading = false;
      // Refresh list after creation
      await fetchPublicFandoms();
      return true;
    } on DioException catch (e) {
      _errorMessage = e.response?.data?['detail'] ?? 'Không thể tạo Fandom.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<FandomDetailModel?> getFandomPreview(String slug) async {
    try {
      final response = await _apiClient.dio.get('/api/v1/fandoms/$slug/preview');
      return FandomDetailModel.fromJson(response.data);
    } catch (_) {
      return null;
    }
  }
}
