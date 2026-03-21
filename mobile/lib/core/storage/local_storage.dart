import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localStorageProvider = Provider<LocalStorage>((ref) => LocalStorage());

class LocalStorage {
  static const _storage = FlutterSecureStorage();

  // ── JWT Token ────────────────────────────────────────────────
  Future<void> sauvegarderToken(String token) =>
      _storage.write(key: 'jwt_token', value: token);

  Future<String?> lireToken() => _storage.read(key: 'jwt_token');

  Future<void> supprimerToken() => _storage.delete(key: 'jwt_token');

  // ── Profil commerçant ────────────────────────────────────────
  Future<void> sauvegarderProfil(Map<String, dynamic> profil) =>
      _storage.write(key: 'profil_commercant', value: jsonEncode(profil));

  Future<Map<String, dynamic>?> lireProfil() async {
    final json = await _storage.read(key: 'profil_commercant');
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  // ── Cache offline clients ────────────────────────────────────
  Future<void> cacherClients(List<dynamic> clients) =>
      _storage.write(key: 'cache_clients', value: jsonEncode(clients));

  Future<List<dynamic>> lireClientsCache() async {
    final json = await _storage.read(key: 'cache_clients');
    if (json == null) return [];
    return jsonDecode(json) as List;
  }

  // ── Cache offline contrats ───────────────────────────────────
  Future<void> cacherContrats(List<dynamic> contrats) =>
      _storage.write(key: 'cache_contrats', value: jsonEncode(contrats));

  Future<List<dynamic>> lireContratsCache() async {
    final json = await _storage.read(key: 'cache_contrats');
    if (json == null) return [];
    return jsonDecode(json) as List;
  }

  // ── Paiements en attente (offline-first) ────────────────────
  Future<void> ajouterPaiementEnAttente(Map<String, dynamic> paiement) async {
    final liste = await lirePaiementsEnAttente();
    liste.add(paiement);
    await _storage.write(
        key: 'paiements_en_attente', value: jsonEncode(liste));
  }

  Future<List<dynamic>> lirePaiementsEnAttente() async {
    final json = await _storage.read(key: 'paiements_en_attente');
    if (json == null) return [];
    return jsonDecode(json) as List;
  }

  Future<void> viderPaiementsEnAttente() =>
      _storage.delete(key: 'paiements_en_attente');

  Future<void> deconnexion() async {
    await _storage.deleteAll();
  }
}
