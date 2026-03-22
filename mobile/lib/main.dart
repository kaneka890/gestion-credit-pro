import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/constants/app_theme.dart';
import 'core/network/api_client.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/clients/presentation/clients_screen.dart';
import 'features/contrats/presentation/detail_contrat_screen.dart';
import 'features/contrats/presentation/nouveau_contrat_screen.dart';
import 'features/contrats/presentation/contrats_screen.dart';
import 'features/scores/presentation/score_screen.dart';
import 'shared/models/contrat_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GestionCreditProApp()));
}

// ── Routeur ──────────────────────────────────────────────────
final _routeur = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_token');
    final estConnecte = token != null;
    final versLogin = state.matchedLocation == '/login' ||
        state.matchedLocation == '/inscription';

    if (!estConnecte && !versLogin) return '/login';
    if (estConnecte && versLogin) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/inscription',
      builder: (_, __) => const _InscriptionScreen(),
    ),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(path: '/clients', builder: (_, __) => const ClientsScreen()),
    GoRoute(
      path: '/clients/nouveau',
      builder: (_, __) => const NouveauClientScreen(),
    ),
    GoRoute(
      path: '/clients/:id',
      builder: (_, state) => _DetailClientScreen(
        clientId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/clients/:id/modifier',
      builder: (_, state) => ModifierClientScreen(
        client: state.extra as ClientModel,
      ),
    ),
    GoRoute(
      path: '/contrats',
      builder: (_, __) => const ContratsScreen(),
    ),
    GoRoute(
      path: '/contrats/nouveau',
      builder: (_, __) => const NouveauContratScreen(),
    ),
    GoRoute(
      path: '/contrats/:id',
      builder: (_, state) => DetailContratScreen(
        contratId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/scores/:clientId',
      builder: (_, state) => ScoreScreen(
        clientId: state.pathParameters['clientId']!,
      ),
    ),
    GoRoute(path: '/parametres', builder: (_, __) => const _ParametresScreen()),
  ],
);

// ── Application principale ───────────────────────────────────
class GestionCreditProApp extends StatelessWidget {
  const GestionCreditProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Gestion Crédit Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _routeur,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('fr', 'CI'),
      ],
    );
  }
}

// ── Écrans simples (placeholder) ─────────────────────────────

class _InscriptionScreen extends ConsumerStatefulWidget {
  const _InscriptionScreen();

  @override
  ConsumerState<_InscriptionScreen> createState() => _InscriptionScreenState();
}

class _InscriptionScreenState extends ConsumerState<_InscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _boutiqueCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _inscrire() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.inscription({
        'nom_boutique': _boutiqueCtrl.text.trim(),
        'nom_proprietaire': _nomCtrl.text.trim(),
        'telephone': _telCtrl.text.trim(),
        'password': _pwCtrl.text,
        'quartier': _quartierCtrl.text.trim(),
      });
      const storage = FlutterSecureStorage();
      await storage.write(key: 'jwt_token', value: data['token'] as String);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        String messageAffiche;
        if (msg.contains('409')) {
          messageAffiche = 'Ce numéro est déjà enregistré. Connectez-vous plutôt.';
        } else if (msg.contains('connection') || msg.contains('connexion')) {
          messageAffiche = 'Pas de connexion au serveur. Vérifiez que le backend est démarré.';
        } else if (msg.contains('400')) {
          messageAffiche = 'Informations incorrectes. Vérifiez les champs.';
        } else {
          messageAffiche = 'Erreur inattendue. Réessayez.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(messageAffiche),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte commerçant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Field(_boutiqueCtrl, 'Nom de la boutique *', Icons.store),
            const SizedBox(height: 12),
            _Field(_nomCtrl, 'Nom du propriétaire *', Icons.person),
            const SizedBox(height: 12),
            _Field(_telCtrl, 'Téléphone *', Icons.phone,
                type: TextInputType.phone),
            const SizedBox(height: 12),
            _Field(_quartierCtrl, 'Quartier', Icons.location_on),
            const SizedBox(height: 12),
            _Field(_pwCtrl, 'Mot de passe *', Icons.lock,
                obscure: true, minLen: 6),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _inscrire,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Créer mon compte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? type;
  final bool obscure;
  final int minLen;

  const _Field(this.ctrl, this.label, this.icon,
      {this.type, this.obscure = false, this.minLen = 1});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: type,
    obscureText: obscure,
    style: const TextStyle(color: AppColors.textePrincipal),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.orange),
    ),
    validator: (v) {
      if (label.contains('*') && (v == null || v.isEmpty)) return 'Requis';
      if (v != null && v.isNotEmpty && v.length < minLen) {
        return 'Minimum $minLen caractères';
      }
      return null;
    },
  );
}

final _detailClientProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, clientId) async {
  return await ref.read(apiClientProvider).detailClient(clientId);
});

class _DetailClientScreen extends ConsumerWidget {
  final String clientId;
  const _DetailClientScreen({required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_detailClientProvider(clientId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil client'),
        actions: [
          if (data.value != null)
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.orange),
              tooltip: 'Modifier',
              onPressed: () {
                final client = ClientModel.fromJson(
                    data.value!['client'] as Map<String, dynamic>);
                context.push('/clients/$clientId/modifier', extra: client)
                    .then((_) => ref.invalidate(_detailClientProvider(clientId)));
              },
            ),
        ],
      ),
      body: data.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.orange)),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final client = ClientModel.fromJson(d['client'] as Map<String, dynamic>);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.orange.withValues(alpha: 0.2),
                      child: Text(client.initiales,
                          style: const TextStyle(
                              color: AppColors.orange,
                              fontSize: 24,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 12),
                    Text(client.nomComplet,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textePrincipal)),
                    Text(client.telephone,
                        style: const TextStyle(color: AppColors.texteSecondaire)),
                    if (client.quartierResidence != null)
                      Text(client.quartierResidence!,
                          style: const TextStyle(color: AppColors.texteSecondaire)),
                    if (client.garantNom != null) ...[
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.verified, color: AppColors.succes, size: 16),
                        const SizedBox(width: 4),
                        Text('Garant : ${client.garantNom}',
                            style: const TextStyle(color: AppColors.succes, fontSize: 13)),
                      ]),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/scores/$clientId'),
                    icon: const Icon(Icons.verified_user),
                    label: const Text('Voir le score'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/contrats/nouveau'),
                    icon: const Icon(Icons.add, color: AppColors.orange),
                    label: const Text('Nouveau crédit',
                        style: TextStyle(color: AppColors.orange)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.orange)),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}


class _ParametresScreen extends ConsumerWidget {
  const _ParametresScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Déconnexion',
                style: TextStyle(color: AppColors.danger)),
            onTap: () async {
              const storage = FlutterSecureStorage();
              await storage.deleteAll();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
