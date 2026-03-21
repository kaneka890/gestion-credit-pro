import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _baseUrl = 'https://web-production-4975b.up.railway.app/api/v1';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_AuthInterceptor(_storage));
    _dio.interceptors.add(_OfflineInterceptor());
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
  }

  // ── Auth ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> inscription(Map<String, dynamic> data) async {
    final resp = await _dio.post('/auth/inscription', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> connexion(String telephone, String password) async {
    final resp = await _dio.post('/auth/connexion', data: {
      'telephone': telephone,
      'password': password,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Clients ─────────────────────────────────────────────────
  Future<List<dynamic>> listerClients() async {
    final resp = await _dio.get('/clients');
    return (resp.data as Map)['clients'] as List;
  }

  Future<Map<String, dynamic>> creerClient(Map<String, dynamic> data) async {
    final resp = await _dio.post('/clients', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> detailClient(String clientId) async {
    final resp = await _dio.get('/clients/$clientId');
    return resp.data as Map<String, dynamic>;
  }

  Future<void> modifierClient(String clientId, Map<String, dynamic> data) async {
    await _dio.put('/clients/$clientId', data: data);
  }

  // ── Contrats ────────────────────────────────────────────────
  Future<List<dynamic>> listerContrats({String? statut, String? clientId}) async {
    final resp = await _dio.get('/contrats', queryParameters: {
      if (statut != null) 'statut': statut,
      if (clientId != null) 'client_id': clientId,
    });
    return (resp.data as Map)['contrats'] as List;
  }

  Future<Map<String, dynamic>> creerContrat(Map<String, dynamic> data) async {
    final resp = await _dio.post('/contrats', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> detailContrat(String contratId) async {
    final resp = await _dio.get('/contrats/$contratId');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> marquerSolde(String contratId) async {
    final resp = await _dio.patch('/contrats/$contratId/marquer-solde');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> envoyerRappelSms(String clientId) async {
    final resp = await _dio.post('/rappels/client/$clientId');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> envoyerPushPaiement(
    String contratId, {
    double? montant,
  }) async {
    final resp = await _dio.post(
      '/contrats/$contratId/push-paiement',
      data: montant != null ? {'montant': montant} : <String, dynamic>{},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> paiementManuel(
    String contratId,
    double montant, {
    String? note,
  }) async {
    final resp = await _dio.post('/paiements/manuel', data: {
      'contrat_id': contratId,
      'montant': montant,
      if (note != null) 'note': note,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Scores ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> scoreClient(String clientId) async {
    final resp = await _dio.get('/scores/client/$clientId');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifierEligibilite(
    String clientId,
    double montant,
  ) async {
    final resp = await _dio.post('/scores/verifier-eligibilite', data: {
      'client_id': clientId,
      'montant': montant,
    });
    return resp.data as Map<String, dynamic>;
  }
}

// ── Intercepteur JWT ────────────────────────────────────────
class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  _AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      _storage.delete(key: 'jwt_token');
    }
    handler.next(err);
  }
}

// ── Intercepteur mode Offline ───────────────────────────────
class _OfflineInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout) {
      handler.reject(DioException(
        requestOptions: err.requestOptions,
        error: 'Pas de connexion – données locales affichées',
        type: DioExceptionType.connectionError,
      ));
      return;
    }
    handler.next(err);
  }
}
