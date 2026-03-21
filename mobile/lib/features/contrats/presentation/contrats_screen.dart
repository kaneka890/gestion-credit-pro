import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/models/contrat_model.dart';
import '../../../shared/widgets/statut_badge.dart';

final contratsListProvider = FutureProvider.family<List<ContratModel>, String?>(
  (ref, statut) async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(localStorageProvider);
    try {
      final data = await api.listerContrats(statut: statut);
      if (statut == null) await storage.cacherContrats(data);
      return data
          .map((j) => ContratModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final cache = await storage.lireContratsCache();
      return cache
          .map((j) => ContratModel.fromJson(j as Map<String, dynamic>))
          .where((c) => statut == null || c.statut == statut)
          .toList();
    }
  },
);

class ContratsScreen extends ConsumerStatefulWidget {
  const ContratsScreen({super.key});

  @override
  ConsumerState<ContratsScreen> createState() => _ContratsScreenState();
}

class _ContratsScreenState extends ConsumerState<ContratsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrats de crédit'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.orange,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.texteSecondaire,
          tabs: const [
            Tab(text: 'Tous'),
            Tab(text: 'Actifs'),
            Tab(text: 'Retards'),
            Tab(text: 'Soldés'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ListeContrats(statut: null),
          _ListeContrats(statut: 'ACTIF'),
          _ListeContrats(statut: 'EN_RETARD'),
          _ListeContrats(statut: 'SOLDE'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.orange,
        onPressed: () => context.push('/contrats/nouveau'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouveau', style: TextStyle(color: Colors.white)),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.fondCarte,
        indicatorColor: AppColors.orange.withOpacity(0.15),
        selectedIndex: 2,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard'); break;
            case 1: context.go('/clients'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Tableau'),
          NavigationDestination(icon: Icon(Icons.people_outlined), label: 'Clients'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long, color: AppColors.orange),
            label: 'Contrats',
          ),
        ],
      ),
    );
  }
}

class _ListeContrats extends ConsumerWidget {
  final String? statut;
  const _ListeContrats({this.statut});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contrats = ref.watch(contratsListProvider(statut));

    return contrats.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      ),
      error: (e, _) => Center(
        child: Text('$e', style: const TextStyle(color: AppColors.danger)),
      ),
      data: (liste) {
        if (liste.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 60,
                    color: AppColors.texteSecondaire.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text(
                  statut == 'EN_RETARD' ? 'Aucun retard !' : 'Aucun contrat',
                  style: const TextStyle(color: AppColors.texteSecondaire),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppColors.orange,
          onRefresh: () async => ref.invalidate(contratsListProvider(statut)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ContratCard(contrat: liste[i]),
          ),
        );
      },
    );
  }
}

class _ContratCard extends StatelessWidget {
  final ContratModel contrat;
  const _ContratCard({required this.contrat});

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: contrat.estEnRetard ? AppColors.danger.withOpacity(0.4) : AppColors.bordure,
        width: contrat.estEnRetard ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/contrats/${contrat.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  contrat.montantInitialFormate,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textePrincipal,
                  ),
                ),
                Row(children: [
                  OperateurBadge(contrat.operateurMm),
                  const SizedBox(width: 8),
                  StatutBadge(contrat.statut),
                ]),
              ],
            ),
            if (contrat.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(contrat.description!,
                  style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Restant : ${contrat.montantRestantFormate}',
                  style: TextStyle(
                    color: contrat.estEnRetard ? AppColors.danger : AppColors.succes,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  contrat.estSolde
                      ? 'Soldé'
                      : 'Échéance : ${contrat.dateEcheanceFormatee}',
                  style: const TextStyle(
                    color: AppColors.texteSecondaire,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: contrat.pourcentageRembourse / 100,
                minHeight: 6,
                backgroundColor: AppColors.bordure,
                valueColor: AlwaysStoppedAnimation(
                  contrat.estEnRetard ? AppColors.danger : AppColors.succes,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
