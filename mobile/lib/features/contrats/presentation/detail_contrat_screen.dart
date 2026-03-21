import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/contrat_model.dart';
import '../../../shared/widgets/statut_badge.dart';

final _detailContratProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await ref.read(apiClientProvider).detailContrat(id);
});

final _fcfa = NumberFormat('#,###', 'fr_FR');

class DetailContratScreen extends ConsumerWidget {
  final String contratId;
  const DetailContratScreen({super.key, required this.contratId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(_detailContratProvider(contratId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail du contrat'),
        actions: [
          detail.whenData((d) {
            final contrat = ContratModel.fromJson(d['contrat'] as Map<String, dynamic>);
            if (contrat.estSolde) return const SizedBox();
            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'push', child: Text('Envoyer Push paiement')),
                const PopupMenuItem(
                  value: 'sms',
                  child: Row(children: [
                    Icon(Icons.sms, color: AppColors.orange, size: 18),
                    SizedBox(width: 8),
                    Text('Envoyer rappel SMS'),
                  ]),
                ),
                const PopupMenuItem(value: 'cash', child: Text('Enregistrer paiement espèces')),
                const PopupMenuItem(
                  value: 'solde',
                  child: Text('Marquer comme soldé',
                      style: TextStyle(color: AppColors.succes)),
                ),
              ],
              onSelected: (action) => _handleAction(context, ref, contrat, action),
            );
          }).value ?? const SizedBox(),
        ],
      ),
      body: detail.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
        error: (e, _) => Center(
          child: Text('Erreur : $e', style: const TextStyle(color: AppColors.danger)),
        ),
        data: (data) {
          final contrat = ContratModel.fromJson(data['contrat'] as Map<String, dynamic>);
          final transactions = data['historique_paiements'] as List? ?? [];
          return _ContenuDetail(contrat: contrat, transactions: transactions);
        },
      ),
    );
  }

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
    ContratModel contrat,
    String action,
  ) {
    switch (action) {
      case 'push':
        _confirmerPushPaiement(context, ref, contrat);
      case 'sms':
        _envoyerRappelSms(context, ref, contrat);
      case 'cash':
        _dialogPaiementEspeces(context, ref, contrat);
      case 'solde':
        _confirmerSolde(context, ref, contrat);
    }
  }

  void _confirmerPushPaiement(
    BuildContext context,
    WidgetRef ref,
    ContratModel contrat,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.fondCarte,
        title: const Text('Envoyer Push paiement',
            style: TextStyle(color: AppColors.textePrincipal)),
        content: Text(
          'Envoyer une demande de ${contrat.montantFluxQuotidien != null ? "${_fcfa.format(contrat.montantFluxQuotidien!)} FCFA" : contrat.montantRestantFormate} via ${contrat.operateurMm.toUpperCase()} ?',
          style: const TextStyle(color: AppColors.texteSecondaire),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(apiClientProvider).envoyerPushPaiement(contrat.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Push envoyé – en attente confirmation client'),
                      backgroundColor: AppColors.succes,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.danger),
                  );
                }
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  void _envoyerRappelSms(
    BuildContext context,
    WidgetRef ref,
    ContratModel contrat,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.fondCarte,
        title: const Row(children: [
          Icon(Icons.sms, color: AppColors.orange),
          SizedBox(width: 8),
          Text('Rappel SMS', style: TextStyle(color: AppColors.textePrincipal)),
        ]),
        content: Text(
          'Envoyer un SMS de rappel de remboursement au client via son numéro ${contrat.operateurMm.toUpperCase()} ?',
          style: const TextStyle(color: AppColors.texteSecondaire),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Envoyer SMS'),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(apiClientProvider).envoyerRappelSms(contrat.clientId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('SMS de rappel envoyé au client'),
                      backgroundColor: AppColors.succes,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur SMS : $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _dialogPaiementEspeces(
    BuildContext context,
    WidgetRef ref,
    ContratModel contrat,
  ) {
    final montantCtrl = TextEditingController(
      text: contrat.montantFluxQuotidien?.toString() ?? contrat.montantRestant.toString(),
    );
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.fondCarte,
        title: const Text('Paiement en espèces',
            style: TextStyle(color: AppColors.textePrincipal)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: montantCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textePrincipal),
              decoration: const InputDecoration(
                labelText: 'Montant (FCFA)',
                prefixIcon: Icon(Icons.money, color: AppColors.orange),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              style: const TextStyle(color: AppColors.textePrincipal),
              decoration: const InputDecoration(
                labelText: 'Note (optionnel)',
                prefixIcon: Icon(Icons.note, color: AppColors.orange),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final montant = double.tryParse(montantCtrl.text);
              if (montant == null || montant <= 0) return;
              Navigator.pop(context);
              try {
                await ref.read(apiClientProvider).paiementManuel(
                  contrat.id,
                  montant,
                  note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                );
                ref.invalidate(_detailContratProvider(contrat.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Paiement enregistré'),
                      backgroundColor: AppColors.succes,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.danger),
                  );
                }
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _confirmerSolde(BuildContext context, WidgetRef ref, ContratModel contrat) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.fondCarte,
        title: const Text('Marquer comme soldé',
            style: TextStyle(color: AppColors.textePrincipal)),
        content: const Text(
          'Confirmer que ce crédit est intégralement remboursé ?',
          style: TextStyle(color: AppColors.texteSecondaire),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.succes),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(apiClientProvider).marquerSolde(contrat.id);
              ref.invalidate(_detailContratProvider(contrat.id));
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}

// ── Contenu du détail ────────────────────────────────────────
class _ContenuDetail extends StatelessWidget {
  final ContratModel contrat;
  final List transactions;

  const _ContenuDetail({required this.contrat, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Carte résumé ───────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatutBadge(contrat.statut),
                    OperateurBadge(contrat.operateurMm),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  contrat.montantInitialFormate,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textePrincipal,
                  ),
                ),
                if (contrat.description?.isNotEmpty == true)
                  Text(
                    contrat.description!,
                    style: const TextStyle(color: AppColors.texteSecondaire),
                  ),
                const SizedBox(height: 20),

                // Barre de progression
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${contrat.pourcentageRembourse.toStringAsFixed(0)}% remboursé',
                      style: const TextStyle(
                        color: AppColors.texteSecondaire,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Restant : ${contrat.montantRestantFormate}',
                      style: TextStyle(
                        color: contrat.estEnRetard
                            ? AppColors.danger
                            : AppColors.succes,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: contrat.pourcentageRembourse / 100,
                    minHeight: 10,
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
        const SizedBox(height: 16),

        // ── Détails ────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _LignDetail('Montant initial', contrat.montantInitialFormate),
                _LignDetail('Remboursé', contrat.montantRembourseFormate,
                    couleur: AppColors.succes),
                _LignDetail('Restant', contrat.montantRestantFormate,
                    couleur: contrat.estEnRetard ? AppColors.danger : null),
                const Divider(color: AppColors.bordure),
                _LignDetail('Date création', contrat.dateCreationFormatee),
                _LignDetail(
                  'Date échéance',
                  contrat.dateEcheanceFormatee,
                  couleur: contrat.estEnRetard ? AppColors.danger : null,
                ),
                if (contrat.montantFluxQuotidien != null)
                  _LignDetail(
                    'Flux quotidien',
                    '${_fcfa.format(contrat.montantFluxQuotidien!)} FCFA/jour',
                    couleur: AppColors.info,
                  ),
                if (contrat.scoreAuMomentOctroi != null)
                  _LignDetail(
                    'Score au moment de l\'octroi',
                    '${contrat.scoreAuMomentOctroi}/100',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Historique paiements ───────────────────────
        const Text(
          'Historique des paiements',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textePrincipal,
          ),
        ),
        const SizedBox(height: 12),

        if (transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Aucun paiement enregistré',
                  style: TextStyle(color: AppColors.texteSecondaire),
                ),
              ),
            ),
          )
        else
          ...transactions.reversed.map(
            (tx) => _TransactionCard(transaction: tx as Map<String, dynamic>),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LignDetail extends StatelessWidget {
  final String label;
  final String valeur;
  final Color? couleur;

  const _LignDetail(this.label, this.valeur, {this.couleur});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 14)),
        Text(
          valeur,
          style: TextStyle(
            color: couleur ?? AppColors.textePrincipal,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;
  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final montant = (transaction['montant'] as num?)?.toDouble() ?? 0;
    final statut = transaction['statut'] as String? ?? 'INCONNU';
    final source = transaction['source'] as String? ?? '';
    final date = transaction['date'] as String? ?? '';
    final ref = transaction['reference_api'] as String? ?? '';

    final couleurStatut = switch (statut) {
      'VALIDE' => AppColors.succes,
      'EN_ATTENTE' => AppColors.avertissement,
      'ECHEC' => AppColors.danger,
      _ => AppColors.texteSecondaire,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: couleurStatut.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            statut == 'VALIDE' ? Icons.check_circle : Icons.pending,
            color: couleurStatut,
            size: 20,
          ),
        ),
        title: Text(
          '${_fcfa.format(montant)} FCFA',
          style: TextStyle(
            color: couleurStatut,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              date.isNotEmpty
                  ? DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(date))
                  : '',
              style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 12),
            ),
            if (ref.isNotEmpty)
              Text(
                'Réf: $ref',
                style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 11),
              ),
          ],
        ),
        trailing: OperateurBadge(source),
      ),
    );
  }
}
