import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _loading = false;
  bool _pwVisible = false;

  @override
  void dispose() {
    _telCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final api = ref.read(apiClientProvider);
      final storage = ref.read(localStorageProvider);
      final data = await api.connexion(_telCtrl.text.trim(), _pwCtrl.text);
      await storage.sauvegarderToken(data['token'] as String);
      await storage.sauvegarderProfil(data['commercant'] as Map<String, dynamic>);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_messageErreur(e.toString())),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageErreur(String erreur) {
    if (erreur.contains('401')) return 'Numéro ou mot de passe incorrect';
    if (erreur.contains('connection') || erreur.contains('connexion') || erreur.contains('Connection refused')) {
      return 'Serveur inaccessible – vérifiez que le backend tourne';
    }
    if (erreur.contains('409')) return 'Ce numéro est déjà utilisé';
    return 'Erreur de connexion – réessayez';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Logo / Titre
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.orange, Color(0xFFE06300)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Gestion Crédit Pro',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textePrincipal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'La finance de confiance – Côte d\'Ivoire',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 48),

                // Téléphone
                TextFormField(
                  controller: _telCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.textePrincipal),
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '+2250700000000',
                    prefixIcon: Icon(Icons.phone, color: AppColors.orange),
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Entrez votre numéro'
                      : null,
                ),
                const SizedBox(height: 16),

                // Mot de passe
                TextFormField(
                  controller: _pwCtrl,
                  obscureText: !_pwVisible,
                  style: const TextStyle(color: AppColors.textePrincipal),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock, color: AppColors.orange),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _pwVisible ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.texteSecondaire,
                      ),
                      onPressed: () => setState(() => _pwVisible = !_pwVisible),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 4
                      ? 'Mot de passe trop court'
                      : null,
                ),
                const SizedBox(height: 32),

                // Bouton connexion
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _connecter,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Se connecter'),
                  ),
                ),
                const SizedBox(height: 16),

                // Inscription
                TextButton(
                  onPressed: () => context.push('/inscription'),
                  child: const Text.rich(
                    TextSpan(
                      text: 'Pas encore inscrit ? ',
                      style: TextStyle(color: AppColors.texteSecondaire),
                      children: [
                        TextSpan(
                          text: 'Créer un compte',
                          style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
