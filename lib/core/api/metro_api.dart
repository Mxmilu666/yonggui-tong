import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_exception.dart';

class MetroApi {
  MetroApi({Dio? dio, Future<void> Function(Duration)? delay})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: 'https://metroinfo.ditiego.net',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10))),
        _delay = delay ?? Future<void>.delayed;

  final Dio _dio;
  final Future<void> Function(Duration) _delay;

  Future<Object?> stationList() => _get('/Api/Stations/StationList');
  Future<Object?> dictionary() => _get('/Api/Stations/Dict');
  // The repository validates this ID against Dict before invoking the client.
  Future<Object?> schedule(int stationId) => _get('/Api/Stations/ScheduleTime/$stationId');

  Future<Object?> _get(String path) async {
    Object? failure;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await _delay(Duration(seconds: 1 << (attempt - 1)));
      final token = CancelToken();
      try {
        final response = await _dio.get<Object?>(path, cancelToken: token)
          .timeout(const Duration(seconds: 10), onTimeout: () {
            token.cancel('请求超时');
            throw TimeoutException('请求超时');
          });
        final body = response.data is String ? jsonDecode(response.data as String) : response.data;
        if (body is! Map || body['Code'] != 200) {
          throw ApiException(body is Map && '${body['Message'] ?? ''}'.isNotEmpty
              ? '${body['Message']}' : '服务返回异常，请稍后重试');
        }
        return body['Data'];
      } catch (error) { failure = error; }
    }
    if (failure is ApiException) throw failure;
    if (failure is TimeoutException || failure is DioException &&
        [DioExceptionType.connectionTimeout, DioExceptionType.receiveTimeout,
         DioExceptionType.sendTimeout].contains(failure.type)) {
      throw const ApiException('请求超时，请检查网络后重试');
    }
    if (failure is DioException && failure.response?.statusCode != null) {
      throw ApiException('服务暂时不可用（HTTP ${failure.response!.statusCode}），请稍后重试');
    }
    throw const ApiException('无法连接宁波地铁服务，请检查网络后重试');
  }
}
