import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../core/client_detector/client_detector.dart';
import '../models/user_model.dart';
import '../models/session_model.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Lockout countdown timer
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  int get lockoutSeconds => _lockoutSeconds;
  bool get isLockedOut => _lockoutSeconds > 0;

  AuthProvider() {
    _apiClient.onSessionExpired = () {
      _currentUser = null;
      _errorMessage = 'Phiên làm việc đã hết hạn hoặc được đăng nhập ở thiết bị khác. Vui lòng đăng nhập lại.';
      notifyListeners();
    };
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  void setErrorMessage(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> initialize() async {
    final token = await _apiClient.getAccessToken();
    if (token != null && token.isNotEmpty) {
      await fetchMe();
    }
  }

  /// Trao đổi One-time OAuth Ticket lấy JWT tokens bảo mật (OWASP / OAuth 2.1)
  Future<bool> exchangeOAuthTicket(String ticket) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/auth/exchange-ticket',
        data: {'ticket': ticket.trim()},
      );
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _successMessage = response.data['message'] ?? 'Đăng nhập Google thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Phiên đăng nhập Google đã hết hạn hoặc không hợp lệ.');
      _setLoading(false);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// 1. Khởi tạo yêu cầu đăng ký tài khoản (lưu tạm Redis 10 phút & gửi OTP về Email)
  Future<bool> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final clientInfo = await ClientDetector.getClientInfo();
      final payload = {
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
        'display_name': displayName.trim(),
        ...clientInfo.toJson(),
      };

      final response = await _apiClient.dio.post('/api/v1/auth/register', data: payload);
      _successMessage = response.data['message'] ?? 'Mã OTP xác thực đã được gửi tới email của bạn.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Đăng ký không thành công.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }


  /// 2. Đăng nhập bằng Email/Password
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    if (isLockedOut) {
      _errorMessage = 'Tài khoản đang bị khóa tạm thời. Thử lại sau $_lockoutSeconds giây.';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final clientInfo = await ClientDetector.getClientInfo();
      final payload = {
        'email': email.trim(),
        'password': password,
        ...clientInfo.toJson(),
      };

      final response = await _apiClient.dio.post('/api/v1/auth/login', data: payload);
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _successMessage = response.data['message'] ?? 'Đăng nhập thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        _startLockoutTimer(900); // 15 minutes lockout
        _errorMessage = 'Đã nhập sai mật khẩu quá 5 lần liên tiếp. Tài khoản tạm khóa trong 15 phút.';
      } else {
        _errorMessage = _extractErrorMessage(e, fallback: 'Email hoặc mật khẩu không chính xác.');
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  /// 3. Đăng nhập hoặc đăng ký qua Google OAuth ID Token
  Future<bool> googleLogin({required String idToken, String? password}) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final clientInfo = await ClientDetector.getClientInfo();
      final payload = {
        'id_token': idToken,
        if (password != null && password.isNotEmpty) 'password': password,
        ...clientInfo.toJson(),
      };

      final response = await _apiClient.dio.post('/api/v1/auth/google', data: payload);
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = UserModel.fromJson(response.data['user']);
      _successMessage = response.data['message'] ?? 'Đăng nhập Google thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Đăng nhập qua Google thất bại.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  /// 3b. Liên kết tài khoản hiện tại với Google OAuth
  Future<bool> linkGoogleAccount({required String idToken}) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/auth/google/link',
        data: {'id_token': idToken},
      );
      _currentUser = UserModel.fromJson(response.data);
      _successMessage = 'Liên kết tài khoản Google thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Liên kết tài khoản Google thất bại.');
      _setLoading(false);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }


  /// 4. Lấy URL ủy quyền Google OAuth2 cho Web/Desktop
  Future<String?> getGoogleAuthUrl() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final response = await _apiClient.dio.get('/api/v1/auth/google/login');
      _setLoading(false);
      return response.data['url'];
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Không thể lấy URL đăng nhập Google.');
      _setLoading(false);
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Không thể lấy URL đăng nhập Google: $e';
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  /// 5. Gửi mã OTP xác thực qua Email
  Future<bool> sendEmailOtp({
    required String email,
    required String purpose, // "VERIFY_EMAIL", "OAUTH_SET_PASSWORD", "RESET_PASSWORD", "DELETE_ACCOUNT"
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/email/send-otp', data: {
        'email': email.trim(),
        'purpose': purpose,
      });

      _successMessage = response.data['message'] ?? 'Mã OTP đã được gửi tới email.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Không thể gửi mã OTP.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  /// 6. Xác thực mã OTP (và chính thức tạo tài khoản + lưu token nếu purpose == VERIFY_EMAIL)
  Future<bool> verifyEmailOtp({
    required String email,
    required String code,
    required String purpose,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/email/verify-otp', data: {
        'email': email.trim(),
        'code': code.trim(),
        'purpose': purpose,
      });

      final data = response.data;
      if (data['tokens'] != null && data['user'] != null) {
        final tokens = data['tokens'];
        await _apiClient.saveTokens(
          accessToken: tokens['access_token'],
          refreshToken: tokens['refresh_token'],
        );
        _currentUser = UserModel.fromJson(data['user']);
      } else if (purpose == 'VERIFY_EMAIL' && _currentUser != null) {
        _currentUser = _currentUser!.copyWith(isEmailVerified: true);
      }

      _successMessage = data['message'] ?? 'Xác thực OTP thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Mã OTP không hợp lệ hoặc đã hết hạn.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }


  /// 7. Thiết lập mật khẩu cho tài khoản Google OAuth
  Future<bool> oauthSetPassword({
    required String newPassword,
    required String otpCode,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post('/api/v1/auth/password/oauth-set', data: {
        'new_password': newPassword,
        'otp_code': otpCode.trim(),
      });

      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(hasPassword: true);
      }

      _successMessage = response.data['message'] ?? 'Thiết lập mật khẩu thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Thiết lập mật khẩu không thành công.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  /// 8. Lấy hồ sơ tài khoản hiện tại
  Future<void> fetchMe() async {
    try {
      final response = await _apiClient.dio.get('/api/v1/users/me');
      _currentUser = UserModel.fromJson(response.data);
      notifyListeners();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _currentUser = null;
        await _apiClient.clearTokens();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Cập nhật hồ sơ cá nhân (Tên hiển thị, avatar, bio)
  Future<bool> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final payload = <String, dynamic>{};
      if (displayName != null) payload['display_name'] = displayName.trim();
      if (avatarUrl != null) payload['avatar_url'] = avatarUrl.trim();
      if (bio != null) payload['bio'] = bio.trim();

      final response = await _apiClient.dio.put('/api/v1/users/me', data: payload);
      _currentUser = UserModel.fromJson(response.data);
      _successMessage = 'Cập nhật hồ sơ thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Cập nhật hồ sơ không thành công.');
      _setLoading(false);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Đổi mật khẩu tài khoản
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _successMessage = null;

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/auth/password/change',
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
      );
      _successMessage = response.data['message'] ?? 'Đổi mật khẩu thành công.';
      _setLoading(false);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Đổi mật khẩu không thành công.');
      _setLoading(false);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// 9. Lấy danh sách các phiên thiết bị đang hoạt động
  Future<List<SessionModel>> listSessions() async {
    try {
      final response = await _apiClient.dio.get('/api/v1/auth/sessions');
      final list = (response.data as List).map((s) => SessionModel.fromJson(s)).toList();
      return list;
    } catch (e) {
      _errorMessage = 'Không thể tải danh sách phiên đăng nhập: $e';
      notifyListeners();
      return [];
    }
  }

  /// 10. Thu hồi một phiên thiết bị cụ thể
  Future<bool> revokeSession(String sessionId) async {
    try {
      await _apiClient.dio.post('/api/v1/auth/sessions/$sessionId/revoke');
      _successMessage = 'Đã thu hồi phiên đăng nhập thành công.';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Lỗi thu hồi phiên: $e';
      notifyListeners();
      return false;
    }
  }

  /// 11. Đăng xuất khỏi tất cả các thiết bị khác
  Future<bool> revokeAllOtherSessions() async {
    try {
      final response = await _apiClient.dio.post('/api/v1/auth/sessions/revoke-all');
      _successMessage = response.data['message'] ?? 'Đã đăng xuất khỏi các thiết bị khác.';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Không thể thu hồi các phiên khác: $e';
      notifyListeners();
      return false;
    }
  }

  /// 12. Yêu cầu xóa mềm tài khoản
  Future<bool> deleteAccount({String? password, String? otpCode}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final payload = <String, dynamic>{};
      if (password != null) payload['password'] = password;
      if (otpCode != null) payload['otp_code'] = otpCode;
      final response = await _apiClient.dio.post('/api/v1/auth/delete-account', data: payload);

      await logout();
      _successMessage = response.data['message'] ?? 'Tài khoản đã được xóa thành công.';
      _setLoading(false);
      return true;
    } on DioException catch (e) {
      _errorMessage = _extractErrorMessage(e, fallback: 'Xóa tài khoản không thành công.');
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi kết nối máy chủ: $e';
      _setLoading(false);
      return false;
    }
  }

  /// 13. Đăng xuất tài khoản
  Future<void> logout() async {
    _currentUser = null;
    await _apiClient.clearTokens();
    _errorMessage = null;
    _successMessage = 'Đã đăng xuất thành công.';
    notifyListeners();
  }

  void _startLockoutTimer(int seconds) {
    _lockoutSeconds = seconds;
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutSeconds > 0) {
        _lockoutSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        notifyListeners();
      }
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _extractErrorMessage(DioException e, {required String fallback}) {
    final data = e.response?.data;
    if (data is Map && data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        return detail.map((d) => d['msg'] ?? d.toString()).join(', ');
      }
    }
    return fallback;
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }
}
