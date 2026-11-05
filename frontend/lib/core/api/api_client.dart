import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Completer<String?>? _refreshCompleter;

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

          if (error.response?.statusCode == 401 &&
              !requestPath.contains('/auth/login') &&
              !requestPath.contains('/auth/refresh') &&
              !requestPath.contains('/auth/register')) {
            // If another request is already refreshing tokens, wait for it to finish.
            if (_refreshCompleter != null) {
              final freshToken = await _refreshCompleter!.future;
              if (freshToken != null && freshToken.isNotEmpty) {
                try {
                  final retryOptions = error.requestOptions;
                  retryOptions.headers['Authorization'] = 'Bearer $freshToken';
                  final retryResponse = await dio.fetch(retryOptions);
                  return handler.resolve(retryResponse);
                } on DioException catch (retryErr) {
                  return handler.next(retryErr);
                }
              }
              return handler.next(error);
            }

            _refreshCompleter = Completer<String?>();
            String? newAccessToken;
            bool shouldExpireSession = false;

            try {
              final refreshToken = await _storage.read(key: 'refresh_token');
              if (refreshToken == null || refreshToken.isEmpty) {
                shouldExpireSession = true;
              } else {
                final refreshDio =
                    Dio(BaseOptions(baseUrl: AppConstants.baseUrl));
                final res = await refreshDio.post(
                  '/api/v1/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                if (res.statusCode == 200 && res.data is Map) {
                  newAccessToken = res.data['access_token']?.toString();
                  final newRefreshToken = res.data['refresh_token']?.toString();
                  if (newAccessToken != null &&
                      newAccessToken.isNotEmpty &&
                      newRefreshToken != null &&
                      newRefreshToken.isNotEmpty) {
                    await saveTokens(
                      accessToken: newAccessToken,
                      refreshToken: newRefreshToken,
                    );
                  }
                } else {
                  shouldExpireSession = true;
                }
              }
            } on DioException catch (refreshErr) {
              final code = refreshErr.response?.statusCode;
              if (code == 401 || code == 400 || code == 403) {
                shouldExpireSession = true;
              }
            } catch (_) {
              // Ignore transient non-auth errors during refresh
            } finally {
              final completer = _refreshCompleter;
              _refreshCompleter = null;
              if (completer != null && !completer.isCompleted) {
                completer.complete(newAccessToken);
              }
            }

            if (newAccessToken != null && newAccessToken.isNotEmpty) {
              try {
                final retryOptions = error.requestOptions;
                retryOptions.headers['Authorization'] =
                    'Bearer $newAccessToken';
                final retryResponse = await dio.fetch(retryOptions);
                return handler.resolve(retryResponse);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              }
            }

            if (shouldExpireSession) {
              await clearTokens();
              onSessionExpired?.call();
            }
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
