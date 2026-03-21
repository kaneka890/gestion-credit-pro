import 'package:flutter/material.dart';
import '../../core/constants/app_theme.dart';

class StatutBadge extends StatelessWidget {
  final String statut;
  const StatutBadge(this.statut, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (statut) {
      'ACTIF'     => ('Actif', AppColors.succes),
      'EN_RETARD' => ('En retard', AppColors.danger),
      'SOLDE'     => ('Soldé', AppColors.info),
      'LITIGE'    => ('Litige', AppColors.avertissement),
      _           => (statut, AppColors.texteSecondaire),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  final int score;
  const ScoreBadge(this.score, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.couleurScore(score);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class OperateurBadge extends StatelessWidget {
  final String operateur;
  const OperateurBadge(this.operateur, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (operateur.toLowerCase()) {
      'wave'   => ('Wave', const Color(0xFF1A56DB)),
      'orange' => ('Orange', const Color(0xFFFF6900)),
      'mtn'    => ('MTN', const Color(0xFFFFCC00)),
      'cash'   => ('Espèces', AppColors.succes),
      _        => (operateur, AppColors.texteSecondaire),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
