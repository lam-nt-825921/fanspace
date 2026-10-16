import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    final token = await _apiClient.getAccessToken();
    if (token != null && token.isNotEmpty) {
      await fetchMe();
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/register', data: {
        'email': email,
        'username': username,
        'password': password,
        'display_name': displayName,
      });

      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = e.response?.data?['detail'] ?? 'Đăng ký thất bại, vui lòng thử lại.';
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/login', data: {
        'email': email,
        'password': password,
      });

      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = e.response?.data?['detail'] ?? 'Đăng nhập không thành công.';
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> devLogin({String username = 'k6_fan_vip'}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/dev-login', data: {
        'username': username,
      });

      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = e.response?.data?['detail'] ?? 'Dev login thất bại.';
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<void> fetchMe() async {
    try {
      final response = await _apiClient.dio.get('/api/v1/users/me');
      _currentUser = UserModel.fromJson(response.data);
      notifyListeners();
    } catch (_) {
      _currentUser = null;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _apiClient.clearTokens();
    _currentUser = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
