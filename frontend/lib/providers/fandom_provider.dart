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
  String _sortBy = 'popular';
  bool _isLoading = false;
  String? _errorMessage;

  List<FandomSummaryModel> get fandoms => _fandoms;
  List<String> get categories => _categories;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  String get sortBy => _sortBy;
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

  Future<void> fetchPublicFandoms({int limit = 20, int offset = 0}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Map<String, dynamic> queryParams = {
        'sort_by': _sortBy,
        'limit': limit,
        'offset': offset,
      };
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

  void setSortBy(String sortBy) {
    if (_sortBy != sortBy) {
      _sortBy = sortBy;
      notifyListeners();
      fetchPublicFandoms();
    }
  }

  Future<bool> createFandom({
    required String name,
    required String slug,
    String? description,
    required String category,
    String? avatarUrl,
    String? bannerUrl,
    List<String> illustrationUrls = const [],
    String admissionMode = 'OPEN',
    bool isPublic = true,
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
        'illustration_urls': illustrationUrls,
        'admission_mode': admissionMode,
        'is_public': isPublic,
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

  MyFandomsDataModel? _myFandoms;
  MyFandomsDataModel? get myFandoms => _myFandoms;

  Future<MyFandomsDataModel?> fetchMyFandoms() async {
    try {
      final response = await _apiClient.dio.get('/api/v1/fandoms/me/memberships');
      if (response.data is Map<String, dynamic>) {
        _myFandoms = MyFandomsDataModel.fromJson(response.data);
        notifyListeners();
        return _myFandoms;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> joinFandom(String identifier, {Map<String, dynamic>? answersPayload}) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/join',
        data: answersPayload,
      );
      final data = response.data;
      await fetchMyFandoms();
      return {
        'success': true,
        'status': data['status'],
        'message': data['message'] ?? 'Thao tác thành công.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể tham gia Fandom.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> leaveFandom(String identifier) async {
    try {
      final response = await _apiClient.dio.post('/api/v1/fandoms/$identifier/leave');
      final data = response.data;
      await fetchMyFandoms();
      return {
        'success': true,
        'message': data['message'] ?? 'Đã rời khỏi Fandom thành công.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể rời Fandom.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> cancelJoinRequest(String identifier) async {
    try {
      final response = await _apiClient.dio.delete('/api/v1/fandoms/$identifier/join-requests/me');
      final data = response.data;
      await fetchMyFandoms();
      return {
        'success': true,
        'message': data['message'] ?? 'Đã hủy yêu cầu tham gia thành công.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể hủy yêu cầu.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> joinByInvite(String code) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/invites/join',
        data: {'code': code.trim().toUpperCase()},
      );
      final data = response.data;
      await fetchMyFandoms();
      return {
        'success': true,
        'slug': data['slug'],
        'message': data['message'] ?? 'Gia nhập Fandom thành công qua mã mời!',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Mã mời không hợp lệ.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }
}
