import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_AuthInterceptor());
  }

  // ---- Auth ----
  Future<Map<String, dynamic>> register(String email, String password, {String? nickname}) async {
    final r = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (nickname != null) 'nickname': nickname,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final r = await _dio.get('/auth/me');
    return r.data;
  }

  // ---- Wordbooks ----
  Future<List<dynamic>> getWordbooks() async {
    final r = await _dio.get('/wordbooks');
    return r.data;
  }

  Future<List<dynamic>> getWordbookWords(String wordbookId, {int page = 1, int pageSize = 50}) async {
    final r = await _dio.get('/wordbooks/$wordbookId/words', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> selectWordbook(String wordbookId, {int dailyNewWords = 20}) async {
    final r = await _dio.post('/wordbooks/$wordbookId/select', queryParameters: {
      'daily_new_words': dailyNewWords,
    });
    return r.data;
  }

  // ---- Study ----
  Future<Map<String, dynamic>> getTodayTask(String wordbookId) async {
    final r = await _dio.get('/study/today', queryParameters: {
      'wordbook_id': wordbookId,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> submitReview({
    required String wordId,
    required int rating,
    required String wordbookId,
    required DateTime reviewedAt,
    String? deviceId,
  }) async {
    final r = await _dio.post('/study/review',
      queryParameters: {'wordbook_id': wordbookId},
      data: {
        'word_id': wordId,
        'rating': rating,
        'reviewed_at': reviewedAt.toUtc().toIso8601String(),
        if (deviceId != null) 'device_id': deviceId,
      },
    );
    return r.data;
  }

  Future<Map<String, dynamic>> getProgress(String wordbookId) async {
    final r = await _dio.get('/study/progress', queryParameters: {
      'wordbook_id': wordbookId,
    });
    return r.data;
  }

  // ---- Words ----
  Future<List<dynamic>> searchWords(String query) async {
    final r = await _dio.get('/words/search', queryParameters: {'q': query});
    return r.data;
  }

  /// 导入单词到词书（文本格式，每行一个单词）
  Future<Map<String, dynamic>> importWordsToWordbook({
    required String wordbookId,
    required String textContent,
  }) async {
    // 构造 multipart 文件上传
    final formData = FormData.fromMap({
      'file': MultipartFile.fromString(
        textContent,
        filename: 'import.txt',
      ),
    });
    final r = await _dio.post(
      '/wordbooks/$wordbookId/import',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return Map<String, dynamic>.from(r.data);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
    }
    handler.next(err);
  }
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
