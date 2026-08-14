import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class MusicApiService {
  final Dio _dio;

  static const int _maxRetries = 2;

  MusicApiService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
          },
        )) {
    _setupBadCertificate();
  }

  MusicApiService._shared(Dio dio) : _dio = dio;

  static MusicApiService? _instance;
  static MusicApiService get shared {
    if (_instance == null) {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        },
      ));
      _instance = MusicApiService._shared(dio);
      _instance!._setupBadCertificate();
    }
    return _instance!;
  }

  Future<Response> _retry(
    Future<Response> Function() request, {
    int retries = _maxRetries,
  }) async {
    for (var i = 0; i <= retries; i++) {
      try {
        return await request();
      } catch (e) {
        if (i == retries) rethrow;
        await Future.delayed(Duration(seconds: 1 << i));
      }
    }
    throw Exception('unreachable');
  }

  void _setupBadCertificate() {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..badCertificateCallback = (_, _, _) => true,
    );
  }

  Future<Response> get(String url, {Map<String, dynamic>? headers}) async {
    return _retry(() => _dio.get(url, options: Options(headers: headers)));
  }

  Future<String?> getPlainText(
    String url, {
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _retry(
        () => _dio.get<String>(
          url,
          options: Options(headers: headers, responseType: ResponseType.plain),
        ),
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> getBytes(
    String url, {
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _retry(
        () => _dio.get<List<int>>(
          url,
          options: Options(headers: headers, responseType: ResponseType.bytes),
        ),
      );
      final data = response.data;
      if (data == null) return null;
      return Uint8List.fromList(data);
    } catch (e) {
      return null;
    }
  }

  Future<Response> post(
    String url, {
    Map<String, dynamic>? headers,
    dynamic data,
    Map<String, dynamic>? form,
  }) async {
    final options = Options(headers: headers);
    if (form != null) {
      options.contentType = Headers.formUrlEncodedContentType;
      return _retry(() => _dio.post(url, data: form, options: options));
    }
    return _retry(() => _dio.post(url, data: data, options: options));
  }

  void dispose() {
    if (identical(this, _instance)) return;
    _dio.close();
  }
}
