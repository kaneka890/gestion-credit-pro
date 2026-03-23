import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/models/contrat_model.dart';
import '../../../shared/widgets/statut_badge.dart';

// ── Providers ───────────────────────────────────────────────
final _profilProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ref.read(localStorageProvider).lireProfil() ?? {};
});

final _contratsProvider = FutureProvider<List<ContratModel>>((ref) async {
  final api = ref.read(apiClientProvider);
  final storage = ref.read(localStorageProvider);
  try {
    final data = await api.listerContrats();
    await storage.cacherContrats(data);
    return data.map((j) => ContratModel.fromJson(j as Map<String, dynamic>)).toList();
  } catch (_) {
    final cache = await storage.lireContratsCache();
    return cache.map((j) => ContratModel.fromJson(j as Map<String, dynamic>)).toList();
  }
});

final _fcfa = NumberFormat('#,###', 'fr_FR');

// ── Écran Dashboard ─────────────────────────────────────────
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(_profilProvider);
    final contrats = ref.watch(_contratsProvider);

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: () async {
          ref.invalidate(_contratsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── App Bar ────────────────────────────────────
            SliverAppBar(
              floating: true,
              backgroundColor: AppColors.fondSombre,
              title: profil.when(
                data: (p) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['nom_boutique'] ?? 'Ma Boutique',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textePrincipal,
                      ),
                    ),
                    Text(
                      p['quartier'] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.texteSecondaire,
                      ),
                    ),
                  ],
                ),
                loading: () => const SizedBox(),
                error: (_, __) => const Text('Tableau de bord'),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/parametres'),
                ),
              ],
            ),

            // ── Contenu ────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: contrats.when(
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.orange),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Données hors-ligne\n$err',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.texteSecondaire),
                    ),
                  ),
                ),
                data: (liste) => _ContenuDashboard(contrats: liste),
              ),
            ),
          ],
        ),
      ),

      // ── FAB ─────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.orange,
        onPressed: () => context.push('/contrats/nouveau'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nouveau Crédit',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Barre de navigation ──────────────────────────────
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.fondCarte,
        indicatorColor: AppColors.orange.withValues(alpha: 0.15),
        selectedIndex: 0,
        onDestinationSelected: (i) {
          switch (i) {
            case 1: context.go('/clients'); break;
            case 2: context.go('/contrats'); break;
            case 3: context.go('/paiements'); break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppColors.orange),
            label: 'Tableau',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outlined),
            selectedIcon: Icon(Icons.people, color: AppColors.orange),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: AppColors.orange),
            label: 'Contrats',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments, color: AppColors.orange),
            label: 'Paiements',
          ),
        ],
      ),
    );
  }
}

// ── Contenu principal ───────────────────────────────────────
class _ContenuDashboard extends StatelessWidget {
  final List<ContratModel> contrats;
  const _ContenuDashboard({required this.contrats});

  @override
  Widget build(BuildContext context) {
    final actifs = contrats.where((c) => c.estActif).toList();
    final retards = contrats.where((c) => c.estEnRetard).toList();
    final soldes = contrats.where((c) => c.estSolde).toList();
    final encours = actifs.fold(0.0, (s, c) => s + c.montantRestant)
        + retards.fold(0.0, (s, c) => s + c.montantRestant);

    return SliverList(
      delegate: SliverChildListDelegate([
        // ── KPIs ──────────────────────────────────────────
        const _SectionTitre('Vue d\'ensemble'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _KpiCard(
            titre: 'Encours total',
            valeur: '${_fcfa.format(encours)} F',
            icon: Icons.account_balance_outlined,
            couleur: AppColors.orange,
          )),
          const SizedBox(width: 12),
          Expanded(child: _KpiCard(
            titre: 'En retard',
            valeur: '${retards.length}',
            icon: Icons.warning_amber_rounded,
            couleur: AppColors.danger,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _KpiCard(
            titre: 'Contrats actifs',
            valeur: '${actifs.length}',
            icon: Icons.check_circle_outline,
            couleur: AppColors.succes,
          )),
          const SizedBox(width: 12),
          Expanded(child: _KpiCard(
            titre: 'Soldés ce mois',
            valeur: '${soldes.length}',
            icon: Icons.verified_outlined,
            couleur: AppColors.info,
          )),
        ]),
        const SizedBox(height: 24),

        // ── Graphique camembert ──────────────────────────
        if (contrats.isNotEmpty) ...[
          const _SectionTitre('Répartition des contrats'),
          const SizedBox(height: 12),
          _GraphiqueCamembert(actifs: actifs.length, retards: retards.length, soldes: soldes.length),
          const SizedBox(height: 24),
        ],

        // ── Alertes retard ───────────────────────────────
        if (retards.isNotEmpty) ...[
          const _SectionTitre('⚠️  Retards de paiement', couleur: AppColors.danger),
          const SizedBox(height: 12),
          ...retards.take(3).map((c) => _ContratRetardCard(contrat: c)),
          const SizedBox(height: 24),
        ],

        // ── Contrats récents ─────────────────────────────
        const _SectionTitre('Contrats récents'),
        const SizedBox(height: 12),
        if (contrats.isEmpty)
          _EtatVide()
        else
          ...contrats.take(5).map((c) => _ContratMiniCard(contrat: c)),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── Widgets réutilisables ────────────────────────────────────

class _SectionTitre extends StatelessWidget {
  final String titre;
  final Color? couleur;
  const _SectionTitre(this.titre, {this.couleur});

  @override
  Widget build(BuildContext context) => Text(
    titre,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: couleur ?? AppColors.textePrincipal,
    ),
  );
}

class _KpiCard extends StatelessWidget {
  final String titre;
  final String valeur;
  final IconData icon;
  final Color couleur;

  const _KpiCard({
    required this.titre,
    required this.valeur,
    required this.icon,
    required this.couleur,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: couleur, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
          Text(
            titre,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.texteSecondaire,
            ),
          ),
        ],
      ),
    ),
  );
}

class _GraphiqueCamembert extends StatelessWidget {
  final int actifs;
  final int retards;
  final int soldes;
  const _GraphiqueCamembert({
    required this.actifs,
    required this.retards,
    required this.soldes,
  });

  @override
  Widget build(BuildContext context) {
    final total = actifs + retards + soldes;
    if (total == 0) return const SizedBox();

    return SizedBox(
      height: 180,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: [
                  if (actifs > 0) PieChartSectionData(
                    value: actifs.toDouble(),
                    color: AppColors.succes,
                    title: '$actifs',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (retards > 0) PieChartSectionData(
                    value: retards.toDouble(),
                    color: AppColors.danger,
                    title: '$retards',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (soldes > 0) PieChartSectionData(
                    value: soldes.toDouble(),
                    color: AppColors.info,
                    title: '$soldes',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Legende('Actifs', AppColors.succes),
              SizedBox(height: 8),
              _Legende('Retards', AppColors.danger),
              SizedBox(height: 8),
              _Legende('Soldés', AppColors.info),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  final String label;
  final Color color;
  const _Legende(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(3),
      )),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 13)),
    ],
  );
}

class _ContratMiniCard extends StatelessWidget {
  final ContratModel contrat;
  const _ContratMiniCard({required this.contrat});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: OperateurBadge(contrat.operateurMm),
      title: Text(
        contrat.montantInitialFormate,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textePrincipal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Restant : ${contrat.montantRestantFormate}',
            style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 12),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: contrat.pourcentageRembourse / 100,
            backgroundColor: AppColors.bordure,
            valueColor: AlwaysStoppedAnimation(
              contrat.estEnRetard ? AppColors.danger : AppColors.succes,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
      trailing: StatutBadge(contrat.statut),
      onTap: () => context.push('/contrats/${contrat.id}'),
    ),
  );
}

class _ContratRetardCard extends StatelessWidget {
  final ContratModel contrat;
  const _ContratRetardCard({required this.contrat});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.danger, width: 1),
    ),
    child: ListTile(
      leading: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
      title: Text(
        contrat.montantRestantFormate,
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
      ),
      subtitle: Text(
        'Échéance : ${contrat.dateEcheanceFormatee}',
        style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.texteSecondaire),
      onTap: () => context.push('/contrats/${contrat.id}'),
    ),
  );
}

class _EtatVide extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: AppColors.texteSecondaire.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucun contrat pour l\'instant',
            style: TextStyle(color: AppColors.texteSecondaire),
          ),
          const SizedBox(height: 8),
          const Text(
            'Appuyez sur + pour créer votre premier crédit',
            style: TextStyle(color: AppColors.texteSecondaire, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
