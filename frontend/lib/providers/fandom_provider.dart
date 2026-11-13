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
      // Refresh lists after creation
      await fetchPublicFandoms();
      await fetchMyFandoms();
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

  Future<Map<String, dynamic>> updateFandomVisibility(
    String identifier,
    bool isPublic,
  ) async {
    try {
      final response = await _apiClient.dio.patch(
        '/api/v1/fandoms/$identifier/visibility',
        data: {'is_public': isPublic},
      );
      final data = response.data;
      await fetchPublicFandoms();
      await fetchMyFandoms();
      return {
        'success': true,
        'is_public': data['is_public'] ?? isPublic,
        'message': isPublic
            ? 'Đã chuyển Fandom sang chế độ Công khai.'
            : 'Đã chuyển Fandom sang chế độ Riêng tư.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể cập nhật trạng thái hiển thị.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateFandomProfile(
    String identifier, {
    String? name,
    String? description,
    String? category,
    String? avatarUrl,
    String? bannerUrl,
    List<String>? illustrationUrls,
    String? admissionMode,
    String? rulesTos,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name.trim();
      if (description != null) payload['description'] = description.trim();
      if (category != null) payload['category'] = category.trim();
      if (avatarUrl != null) payload['avatar_url'] = avatarUrl.trim();
      if (bannerUrl != null) payload['banner_url'] = bannerUrl.trim();
      if (illustrationUrls != null) payload['illustration_urls'] = illustrationUrls;
      if (admissionMode != null) payload['admission_mode'] = admissionMode;
      if (rulesTos != null) payload['rules_tos'] = rulesTos.trim();

      final response = await _apiClient.dio.patch(
        '/api/v1/fandoms/$identifier/profile',
        data: payload,
      );

      final updated = FandomDetailModel.fromJson(response.data as Map<String, dynamic>);
      await fetchPublicFandoms();
      await fetchMyFandoms();
      return {
        'success': true,
        'fandom': updated,
        'message': 'Đã cập nhật hồ sơ Fandom thành công.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể cập nhật hồ sơ Fandom.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<String?> uploadFandomMedia({
    required List<int> bytes,
    required String filename,
    required String target,
    String? fandomId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'target': target,
        'entity_id': ?fandomId,
      });

      final response = await _apiClient.dio.post(
        '/api/v1/media/upload',
        data: formData,
      );

      if (response.data != null && response.data['url'] != null) {
        return response.data['url'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> deleteFandom(
    String identifier,
    String password,
  ) async {
    try {
      final response = await _apiClient.dio.delete(
        '/api/v1/fandoms/$identifier',
        data: {'password': password},
      );
      final data = response.data;
      await fetchPublicFandoms();
      await fetchMyFandoms();
      return {
        'success': true,
        'message': data['message'] ?? 'Fandom đã được xóa thành công.',
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể xóa Fandom.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  // ---------------------------------------------------------------------------
  // Role Management
  // ---------------------------------------------------------------------------

  Future<List<RoleModel>> fetchRoles(String identifier) async {
    try {
      final response = await _apiClient.dio.get('/api/v1/fandoms/$identifier/roles');
      final List data = response.data;
      return data.map((json) => RoleModel.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createRole(
    String identifier, {
    required String name,
    String colorHex = '#808080',
    int priority = 0,
    int permissionsBitmask = 0,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/roles',
        data: {
          'name': name,
          'color_hex': colorHex,
          'priority': priority,
          'permissions_bitmask': permissionsBitmask,
        },
      );
      return {'success': true, 'role': RoleModel.fromJson(response.data)};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể tạo vai trò mới.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateRole(
    String identifier,
    String roleId, {
    String? name,
    String? colorHex,
    int? priority,
    int? permissionsBitmask,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (colorHex != null) body['color_hex'] = colorHex;
      if (priority != null) body['priority'] = priority;
      if (permissionsBitmask != null) body['permissions_bitmask'] = permissionsBitmask;

      final response = await _apiClient.dio.put(
        '/api/v1/fandoms/$identifier/roles/$roleId',
        data: body,
      );
      return {'success': true, 'role': RoleModel.fromJson(response.data)};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể cập nhật vai trò.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteRole(String identifier, String roleId) async {
    try {
      final response = await _apiClient.dio.delete('/api/v1/fandoms/$identifier/roles/$roleId');
      return {'success': true, 'message': response.data?['message'] ?? 'Đã xóa vai trò thành công.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể xóa vai trò.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> assignPresetMod(
    String identifier, {
    required String userId,
    required String presetType,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/roles/assign-preset-mod',
        data: {
          'user_id': userId,
          'preset_type': presetType,
        },
      );
      return {'success': true, 'role': RoleModel.fromJson(response.data)};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể gán vai trò Mod.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  // ---------------------------------------------------------------------------
  // Member Management & Moderation
  // ---------------------------------------------------------------------------

  Future<List<FandomMemberModel>> fetchMembers(
    String identifier, {
    String? search,
    String statusFilter = 'ACTIVE',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final Map<String, dynamic> query = {
        'status_filter': statusFilter,
        'limit': limit,
        'offset': offset,
      };
      if (search != null && search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/members',
        queryParameters: query,
      );
      final List data = response.data;
      return data.map((json) => FandomMemberModel.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> assignMemberRoles(
    String identifier,
    String userId,
    List<String> roleIds,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/members/$userId/roles',
        data: {'role_ids': roleIds},
      );
      return {'success': true, 'member': FandomMemberModel.fromJson(response.data)};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể cập nhật vai trò cho thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> kickMember(
    String identifier,
    String userId, {
    String? reason,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/members/$userId/kick',
        data: {'reason': reason},
      );
      return {'success': true, 'message': response.data?['message'] ?? 'Đã trục xuất thành viên.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể trục xuất thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> banMember(
    String identifier,
    String userId, {
    String? reason,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/members/$userId/ban',
        data: {'reason': reason},
      );
      return {'success': true, 'message': response.data?['message'] ?? 'Đã cấm vĩnh viễn thành viên.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể cấm thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> unbanMember(String identifier, String userId) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/members/$userId/unban',
      );
      return {'success': true, 'message': response.data?['message'] ?? 'Đã gỡ cấm cho thành viên.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể gỡ cấm cho thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> muteMember(
    String identifier,
    String userId, {
    int durationHours = 24,
    String? reason,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/members/$userId/mute',
        data: {'duration_hours': durationHours, 'reason': reason},
      );
      return {'success': true, 'message': response.data?['message'] ?? 'Đã tắt tiếng thành viên.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể tắt tiếng thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> unmuteMember(String identifier, String userId) async {
    try {
      final response = await _apiClient.dio.delete(
        '/api/v1/fandoms/$identifier/members/$userId/mute',
      );
      return {'success': true, 'message': response.data?['message'] ?? 'Đã bỏ tắt tiếng thành viên.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể bỏ tắt tiếng thành viên.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  // ---------------------------------------------------------------------------
  // Invite Management
  // ---------------------------------------------------------------------------

  Future<List<FandomInviteModel>> fetchInvites(String identifier) async {
    try {
      final response = await _apiClient.dio.get('/api/v1/fandoms/$identifier/invites');
      final List data = response.data;
      return data.map((json) => FandomInviteModel.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createInvite(
    String identifier, {
    int? maxUses,
    int? expiresInHours,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/invites',
        data: {
          'max_uses': maxUses,
          'expires_in_hours': expiresInHours,
        },
      );
      return {'success': true, 'invite': FandomInviteModel.fromJson(response.data)};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể tạo mã mời.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> revokeInvite(String identifier, String code) async {
    try {
      final response = await _apiClient.dio.delete('/api/v1/fandoms/$identifier/invites/$code');
      return {'success': true, 'message': response.data?['message'] ?? 'Đã thu hồi mã mời.'};
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể thu hồi mã mời.';
      return {'success': false, 'error': detail};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  // ---------------------------------------------------------------------------
  // Monetization, Membership Tiers & SePay 3-Way Reconciliation (FR-09)
  // ---------------------------------------------------------------------------

  Future<FandomBankAccountModel?> fetchBankAccount(String identifier) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/bank-account',
      );
      if (response.data is Map<String, dynamic>) {
        return FandomBankAccountModel.fromJson(response.data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> upsertBankAccount(
    String identifier, {
    required String bankCode,
    required String accountNumber,
    required String accountName,
    bool isActive = true,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/api/v1/fandoms/$identifier/bank-account',
        data: {
          'bank_code': bankCode.trim(),
          'account_number': accountNumber.trim(),
          'account_name': accountName.trim().toUpperCase(),
          'is_active': isActive,
        },
      );
      return {
        'success': true,
        'bank_account': FandomBankAccountModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể lưu tài khoản ngân hàng.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<FandomMembershipsDataModel> fetchMemberships(String identifier) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/memberships',
      );
      if (response.data is Map<String, dynamic>) {
        return FandomMembershipsDataModel.fromJson(response.data);
      }
    } catch (_) {}
    return FandomMembershipsDataModel(fandomId: identifier);
  }

  Future<Map<String, dynamic>> createMembershipTier(
    String identifier, {
    required String name,
    int tierLevel = 1,
    String colorHex = '#FFD700',
    int priority = 50,
    int permissionsBitmask = 0,
    required int priceFiatVnd,
    int durationDays = 30,
    String? iconUrl,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/memberships',
        data: {
          'name': name.trim(),
          'tier_level': tierLevel,
          'color_hex': colorHex,
          'priority': priority,
          'permissions_bitmask': permissionsBitmask,
          'price_fiat_vnd': priceFiatVnd,
          'duration_days': durationDays,
          if (iconUrl != null && iconUrl.trim().isNotEmpty)
            'icon_url': iconUrl.trim(),
        },
      );
      return {
        'success': true,
        'tier': MembershipTierModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể tạo gói Hội viên.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateMembershipTier(
    String identifier,
    String roleId, {
    String? name,
    int? tierLevel,
    String? colorHex,
    int? priority,
    int? permissionsBitmask,
    int? priceFiatVnd,
    int? durationDays,
    String? iconUrl,
  }) async {
    try {
      final Map<String, dynamic> payload = {};
      if (name != null) payload['name'] = name.trim();
      if (tierLevel != null) payload['tier_level'] = tierLevel;
      if (colorHex != null) payload['color_hex'] = colorHex;
      if (priority != null) payload['priority'] = priority;
      if (permissionsBitmask != null) {
        payload['permissions_bitmask'] = permissionsBitmask;
      }
      if (priceFiatVnd != null) payload['price_fiat_vnd'] = priceFiatVnd;
      if (durationDays != null) payload['duration_days'] = durationDays;
      if (iconUrl != null) payload['icon_url'] = iconUrl.trim();

      final response = await _apiClient.dio.put(
        '/api/v1/fandoms/$identifier/memberships/$roleId',
        data: payload,
      );
      return {
        'success': true,
        'tier': MembershipTierModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể cập nhật gói Hội viên.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteMembershipTier(
    String identifier,
    String roleId,
  ) async {
    try {
      final response = await _apiClient.dio.delete(
        '/api/v1/fandoms/$identifier/memberships/$roleId',
      );
      return {
        'success': true,
        'message': response.data?['message'] ?? 'Đã xóa gói Hội viên.',
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể xóa gói Hội viên.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createPaymentOrder(
    String identifier,
    String roleId,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/orders',
        data: {'role_id': roleId},
      );
      return {
        'success': true,
        'order': PaymentOrderModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể khởi tạo đơn thanh toán.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<PaymentOrderModel?> fetchPaymentOrder(String orderCode) async {
    try {
      final response = await _apiClient.dio.get('/api/v1/orders/$orderCode');
      if (response.data is Map<String, dynamic>) {
        return PaymentOrderModel.fromJson(response.data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> cancelPaymentOrder(String orderCode) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/orders/$orderCode/cancel',
      );
      return {
        'success': true,
        'order': PaymentOrderModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? 'Không thể hủy đơn hàng.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> simulateSepayWebhook({
    required String orderCode,
    int? transferAmount,
    String? customContent,
    String gateway = 'MBBank',
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/billing/sepay-simulate',
        data: {
          'order_code': orderCode,
          'transfer_amount': ?transferAmount,
          'custom_content': ?customContent,
          'gateway': gateway,
        },
      );
      return {
        'success': true,
        'data': response.data,
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể giả lập Webhook SePay.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<FandomLedgerModel?> fetchFandomLedger(
    String identifier, {
    String? statusFilter,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/transactions',
        queryParameters: statusFilter != null && statusFilter.isNotEmpty
            ? {'status_filter': statusFilter}
            : null,
      );
      if (response.data is Map<String, dynamic>) {
        return FandomLedgerModel.fromJson(response.data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> resolveTransactionManually(
    String identifier,
    String transactionId, {
    required String orderCode,
    String? note,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/transactions/$transactionId/resolve',
        data: {
          'order_code': orderCode.trim().toUpperCase(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      return {
        'success': true,
        'transaction': PaymentTransactionModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể đối soát thủ công giao dịch.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<FandomLeaderboardModel?> fetchFandomLeaderboard(
    String identifier, {
    int limit = 50,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/leaderboard',
        queryParameters: {'limit': limit},
      );
      if (response.data is Map<String, dynamic>) {
        return FandomLeaderboardModel.fromJson(response.data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<FandomEmojiListModel?> fetchFandomEmojis(String identifier) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/v1/fandoms/$identifier/emojis',
      );
      if (response.data is Map<String, dynamic>) {
        return FandomEmojiListModel.fromJson(response.data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> uploadFandomEmojiImage(
    String fandomId, {
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'target': 'FANDOM_EMOJI',
        'entity_id': fandomId,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _apiClient.dio.post(
        '/api/v1/media/upload',
        data: formData,
      );
      final url = response.data['url']?.toString();
      if (url != null && url.isNotEmpty) {
        return {'success': true, 'url': url};
      }
      return {'success': false, 'error': 'Không nhận được URL ảnh sau khi tải lên.'};
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể tải ảnh Emoji/Sticker lên.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createFandomEmoji(
    String identifier, {
    required String code,
    required String name,
    String assetType = 'EMOJI',
    required String imageUrl,
    int minTierLevel = 1,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/v1/fandoms/$identifier/emojis',
        data: {
          'code': code.trim(),
          'name': name.trim(),
          'asset_type': assetType.toUpperCase(),
          'image_url': imageUrl.trim(),
          'min_tier_level': minTierLevel,
        },
      );
      return {
        'success': true,
        'emoji': FandomEmojiModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể tạo Emoji/Sticker độc quyền.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateFandomEmoji(
    String identifier,
    String emojiId, {
    String? code,
    String? name,
    String? assetType,
    String? imageUrl,
    int? minTierLevel,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/api/v1/fandoms/$identifier/emojis/$emojiId',
        data: {
          if (code != null) 'code': code.trim(),
          if (name != null) 'name': name.trim(),
          if (assetType != null) 'asset_type': assetType.toUpperCase(),
          if (imageUrl != null) 'image_url': imageUrl.trim(),
          if (minTierLevel != null) 'min_tier_level': minTierLevel,
        },
      );
      return {
        'success': true,
        'emoji': FandomEmojiModel.fromJson(response.data),
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể cập nhật Emoji/Sticker.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFandomEmoji(
    String identifier,
    String emojiId,
  ) async {
    try {
      final response = await _apiClient.dio.delete(
        '/api/v1/fandoms/$identifier/emojis/$emojiId',
      );
      return {
        'success': true,
        'message': response.data?['message'] ?? 'Đã xóa Emoji/Sticker.',
      };
    } on DioException catch (e) {
      final detail =
          e.response?.data?['detail'] ?? 'Không thể xóa Emoji/Sticker.';
      return {'success': false, 'error': detail.toString()};
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }
}




