import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/statut_badge.dart';

// ── Modèle ──────────────────────────────────────────────────
class TransactionModel {
  final DateTime date;
  final double montant;
  final String operateur;
  final String reference;
  final String statut;
  final String note;
  final String contratId;
  final String clientNom;
  final String clientTelephone;
  final double montantInitialContrat;

  TransactionModel({
    required this.date,
    required this.montant,
    required this.operateur,
    required this.reference,
    required this.statut,
    required this.note,
    required this.contratId,
    required this.clientNom,
    required this.clientTelephone,
    required this.montantInitialContrat,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        date: DateTime.parse(json['date'] as String),
        montant: (json['montant'] as num).toDouble(),
        operateur: json['operateur'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        statut: json['statut'] as String? ?? 'VALIDE',
        note: json['note'] as String? ?? '',
        contratId: json['contrat_id'] as String? ?? '',
        clientNom: json['client_nom'] as String? ?? '',
        clientTelephone: json['client_telephone'] as String? ?? '',
        montantInitialContrat:
            (json['montant_initial_contrat'] as num?)?.toDouble() ?? 0,
      );
}

// ── Providers ───────────────────────────────────────────────
final _operateurFiltreProvider = StateProvider<String?>((ref) => null);

final paiementsProvider =
    FutureProvider.family<Map<String, dynamic>, String?>(
  (ref, operateur) async {
    return await ref.read(apiClientProvider).listerPaiements(
          limite: 100,
          operateur: operateur,
        );
  },
);

final _fcfa = NumberFormat('#,###', 'fr_FR');

// ── Écran ────────────────────────────────────────────────────
class PaiementsScreen extends ConsumerWidget {
  const PaiementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operateur = ref.watch(_operateurFiltreProvider);
    final data = ref.watch(paiementsProvider(operateur));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des paiements'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: operateur != null ? AppColors.orange : AppColors.textePrincipal,
            ),
            tooltip: 'Filtrer par opérateur',
            onPressed: () => _choisirFiltre(context, ref, operateur),
          ),
        ],
      ),
      body: data.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.orange)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppColors.texteSecondaire, size: 48),
              const SizedBox(height: 12),
              Text('$e', style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(paiementsProvider(operateur)),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (payload) {
          final transactions = (payload['transactions'] as List)
              .map((j) => TransactionModel.fromJson(j as Map<String, dynamic>))
              .toList();
          final totalMontant = (payload['total_montant'] as num?)?.toDouble() ?? 0;

          if (transactions.isEmpty) {
            return _EtatVide(operateur: operateur);
          }

          return RefreshIndicator(
            color: AppColors.orange,
            onRefresh: () async => ref.invalidate(paiementsProvider(operateur)),
            child: CustomScrollView(
              slivers: [
                // ── Résumé ─────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _CarteResume(
                      total: transactions.length,
                      totalMontant: totalMontant,
                      operateur: operateur,
                    ),
                  ),
                ),

                // ── Filtre actif ───────────────────────
                if (operateur != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          OperateurBadge(operateur),
                          const SizedBox(width: 8),
                          Text(
                            'filtre actif',
                            style: const TextStyle(
                                color: AppColors.texteSecondaire, fontSize: 12),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => ref
                                .read(_operateurFiltreProvider.notifier)
                                .state = null,
                            child: const Text('Effacer',
                                style: TextStyle(color: AppColors.orange, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Liste ──────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final tx = transactions[i];
                        final prev = i > 0 ? transactions[i - 1] : null;
                        final afficherEntete = prev == null ||
                            !_memJour(prev.date, tx.date);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (afficherEntete) _EnteteJour(tx.date),
                            _CartePaiement(tx: tx),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                      childCount: transactions.length,
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.fondCarte,
        indicatorColor: AppColors.orange.withValues(alpha: 0.15),
        selectedIndex: 3,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard'); break;
            case 1: context.go('/clients'); break;
            case 2: context.go('/contrats'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Tableau'),
          NavigationDestination(icon: Icon(Icons.people_outlined), label: 'Clients'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Contrats'),
          NavigationDestination(
            icon: Icon(Icons.payments, color: AppColors.orange),
            label: 'Paiements',
          ),
        ],
      ),
    );
  }

  bool _memJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _choisirFiltre(BuildContext context, WidgetRef ref, String? courant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.fondCarte,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtrer par opérateur',
              style: TextStyle(
                color: AppColors.textePrincipal,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            for (final (op, label, color) in [
              (null, 'Tous les paiements', AppColors.texteSecondaire),
              ('wave', 'Wave', const Color(0xFF1A56DB)),
              ('orange', 'Orange Money', const Color(0xFFFF6900)),
              ('mtn', 'MTN MoMo', const Color(0xFFFFCC00)),
              ('cash', 'Espèces', AppColors.succes),
            ])
              ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(
                    op == null ? Icons.all_inclusive : Icons.payment,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(label,
                    style: TextStyle(
                      color: courant == op
                          ? AppColors.orange
                          : AppColors.textePrincipal,
                      fontWeight: courant == op
                          ? FontWeight.w700
                          : FontWeight.normal,
                    )),
                trailing: courant == op
                    ? const Icon(Icons.check, color: AppColors.orange)
                    : null,
                onTap: () {
                  ref.read(_operateurFiltreProvider.notifier).state = op;
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Carte résumé ─────────────────────────────────────────────
class _CarteResume extends StatelessWidget {
  final int total;
  final double totalMontant;
  final String? operateur;

  const _CarteResume({
    required this.total,
    required this.totalMontant,
    this.operateur,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total encaissé',
                      style: TextStyle(
                          color: AppColors.texteSecondaire, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fcfa.format(totalMontant)} FCFA',
                      style: const TextStyle(
                        color: AppColors.succes,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'paiements',
                      style: TextStyle(
                          color: AppColors.texteSecondaire, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

// ── En-tête de groupe par jour ───────────────────────────────
class _EnteteJour extends StatelessWidget {
  final DateTime date;
  const _EnteteJour(this.date);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hier = now.subtract(const Duration(days: 1));
    String label;
    if (_memJour(date, now)) {
      label = "Aujourd'hui";
    } else if (_memJour(date, hier)) {
      label = 'Hier';
    } else {
      label = DateFormat('EEEE d MMMM yyyy', 'fr').format(date);
      label = label[0].toUpperCase() + label.substring(1);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.texteSecondaire,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  bool _memJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Carte transaction ────────────────────────────────────────
class _CartePaiement extends StatelessWidget {
  final TransactionModel tx;
  const _CartePaiement({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône opérateur
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _couleurOp.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconeOp, color: _couleurOp, size: 22),
            ),
            const SizedBox(width: 14),

            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          tx.clientNom,
                          style: const TextStyle(
                            color: AppColors.textePrincipal,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '+${_fcfa.format(tx.montant)} FCFA',
                        style: const TextStyle(
                          color: AppColors.succes,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      OperateurBadge(tx.operateur),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm').format(tx.date),
                        style: const TextStyle(
                            color: AppColors.texteSecondaire, fontSize: 12),
                      ),
                    ],
                  ),
                  if (tx.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tx.note,
                      style: const TextStyle(
                          color: AppColors.texteSecondaire, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (tx.reference.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Réf : ${tx.reference}',
                      style: const TextStyle(
                          color: AppColors.texteSecondaire, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _couleurOp => switch (tx.operateur.toLowerCase()) {
        'wave' => const Color(0xFF1A56DB),
        'orange' => const Color(0xFFFF6900),
        'mtn' => const Color(0xFFFFCC00),
        'cash' => AppColors.succes,
        _ => AppColors.texteSecondaire,
      };

  IconData get _iconeOp => switch (tx.operateur.toLowerCase()) {
        'wave' => Icons.waves,
        'orange' => Icons.circle,
        'mtn' => Icons.signal_cellular_alt,
        'cash' => Icons.payments,
        _ => Icons.payment,
      };
}

// ── État vide ────────────────────────────────────────────────
class _EtatVide extends StatelessWidget {
  final String? operateur;
  const _EtatVide({this.operateur});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: AppColors.texteSecondaire.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              operateur != null
                  ? 'Aucun paiement via $operateur'
                  : 'Aucun paiement enregistré',
              style: const TextStyle(color: AppColors.texteSecondaire),
            ),
          ],
        ),
      );
}
