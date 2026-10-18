import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  /// Callback triggered when authentication completely fails (e.g. refresh token expired or revoked)
  void Function()? onSessionExpired;

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'access_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final requestPath = error.requestOptions.path;

          // If 401 occurs and not already attempting refresh/login
          if (error.response?.statusCode == 401 &&
              !requestPath.contains('/auth/login') &&
              !requestPath.contains('/auth/refresh') &&
              !requestPath.contains('/auth/register') &&
              !_isRefreshing) {
            _isRefreshing = true;

            try {
              final refreshToken = await _storage.read(key: 'refresh_token');
              if (refreshToken != null && refreshToken.isNotEmpty) {
                // Call refresh endpoint directly using a clean Dio instance
                final refreshDio = Dio(BaseOptions(baseUrl: AppConstants.baseUrl));
                final res = await refreshDio.post(
                  '/api/v1/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                if (res.statusCode == 200) {
                  final newAccessToken = res.data['access_token'];
                  final newRefreshToken = res.data['refresh_token'];
                  await saveTokens(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken,
                  );

                  _isRefreshing = false;

                  // Retry the original failed request with the fresh token
                  final retryOptions = error.requestOptions;
                  retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  final retryResponse = await dio.fetch(retryOptions);
                  return handler.resolve(retryResponse);
                }
              }
            } catch (_) {
              // Refresh failed
            } finally {
              _isRefreshing = false;
            }

            // Both token and refresh token are invalid
            await clearTokens();
            onSessionExpired?.call();
          }

          return handler.next(error);
        },
      ),
    );
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: 'refresh_token');
  }
}
