import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/contrat_model.dart';

final _scoreProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, clientId) async {
  return await ref.read(apiClientProvider).scoreClient(clientId);
});

class ScoreScreen extends ConsumerWidget {
  final String clientId;
  const ScoreScreen({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreData = ref.watch(_scoreProvider(clientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Passeport de Confiance')),
      body: scoreData.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
        error: (e, _) => Center(
          child: Text('Erreur : $e', style: const TextStyle(color: AppColors.danger)),
        ),
        data: (data) {
          final client = ClientModel.fromJson(data['client'] as Map<String, dynamic>);
          final score = ScoreModel.fromJson(
              data['passeport_confiance'] as Map<String, dynamic>);
          final recommandation = data['recommandation'] as String? ?? '';
          return _ContenuScore(
            client: client,
            score: score,
            recommandation: recommandation,
          );
        },
      ),
    );
  }
}

class _ContenuScore extends StatelessWidget {
  final ClientModel client;
  final ScoreModel score;
  final String recommandation;

  const _ContenuScore({
    required this.client,
    required this.score,
    required this.recommandation,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = AppColors.couleurScore(score.scoreGlobal);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Score principal ────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Avatar client
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.orange.withOpacity(0.2),
                    child: Text(
                      client.initiales,
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    client.nomComplet,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textePrincipal,
                    ),
                  ),
                  Text(
                    client.telephone,
                    style: const TextStyle(color: AppColors.texteSecondaire),
                  ),
                  const SizedBox(height: 24),

                  // Jaugeomètre
                  SizedBox(
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            startDegreeOffset: 180,
                            sectionsSpace: 0,
                            centerSpaceRadius: 55,
                            sections: [
                              PieChartSectionData(
                                value: score.scoreGlobal.toDouble(),
                                color: couleur,
                                radius: 18,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: (100 - score.scoreGlobal).toDouble(),
                                color: AppColors.bordure,
                                radius: 18,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${score.scoreGlobal}',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: couleur,
                              ),
                            ),
                            const Text(
                              '/ 100',
                              style: TextStyle(
                                color: AppColors.texteSecondaire,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Niveau de risque
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: couleur.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: couleur.withOpacity(0.4)),
                    ),
                    child: Text(
                      'Risque ${score.niveauRisque}',
                      style: TextStyle(
                        color: couleur,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recommandation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.texteSecondaire,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plafond autorisé : ${score.plafondFormate}',
                    style: const TextStyle(
                      color: AppColors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Composantes du score ───────────────────
          const Text(
            'Détail du score',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textePrincipal,
            ),
          ),
          const SizedBox(height: 12),
          ...score.composantes.entries.map((entry) {
            final nom = entry.key;
            final val = entry.value as Map;
            final scoreComp = val['score'] as int;
            final poids = val['poids'] as String;
            return _ComposanteScore(
              nom: _libeleComposante(nom),
              score: scoreComp,
              poids: poids,
            );
          }),
          const SizedBox(height: 24),

          // ── Statistiques ───────────────────────────
          const Text(
            'Historique',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textePrincipal,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StatLigne(
                    'Total contrats',
                    '${score.statistiques["total_contrats"]}',
                    Icons.receipt_long,
                  ),
                  _StatLigne(
                    'Soldés à temps',
                    '${score.statistiques["soldes_a_temps"]}',
                    Icons.check_circle_outline,
                    couleur: AppColors.succes,
                  ),
                  _StatLigne(
                    'En retard',
                    '${score.statistiques["en_retard"]}',
                    Icons.warning_amber,
                    couleur: AppColors.danger,
                  ),
                  _StatLigne(
                    'Jours de relation',
                    '${score.statistiques["jours_relation"]} jours',
                    Icons.calendar_month,
                    couleur: AppColors.info,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _libeleComposante(String cle) => switch (cle) {
    'regularite' => 'Régularité des paiements',
    'anciennete' => 'Ancienneté / fidélité',
    'recommandation' => 'Recommandation (garant)',
    'reactivite' => 'Vitesse de réponse USSD',
    _ => cle,
  };
}

class _ComposanteScore extends StatelessWidget {
  final String nom;
  final int score;
  final String poids;

  const _ComposanteScore({
    required this.nom,
    required this.score,
    required this.poids,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = AppColors.couleurScore(score);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(nom, style: const TextStyle(color: AppColors.textePrincipal, fontSize: 14)),
                Row(
                  children: [
                    Text(
                      poids,
                      style: const TextStyle(
                        color: AppColors.texteSecondaire,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$score/100',
                      style: TextStyle(
                        color: couleur,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 8,
                backgroundColor: AppColors.bordure,
                valueColor: AlwaysStoppedAnimation(couleur),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLigne extends StatelessWidget {
  final String label;
  final String valeur;
  final IconData icon;
  final Color? couleur;

  const _StatLigne(this.label, this.valeur, this.icon, {this.couleur});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: couleur ?? AppColors.texteSecondaire),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.texteSecondaire)),
        ),
        Text(
          valeur,
          style: TextStyle(
            color: couleur ?? AppColors.textePrincipal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
