import 'package:intl/intl.dart';

final _fcfa = NumberFormat('#,###', 'fr_FR');

class ContratModel {
  final String id;
  final String clientId;
  final String commercantId;
  final double montantInitial;
  final double montantRembourse;
  final double montantRestant;
  final double tauxService;
  final String typeRemboursement;
  final double? montantFluxQuotidien;
  final String statut;
  final String operateurMm;
  final String? description;
  final DateTime dateCreation;
  final DateTime dateEcheance;
  final double pourcentageRembourse;
  final int? scoreAuMomentOctroi;

  ContratModel({
    required this.id,
    required this.clientId,
    required this.commercantId,
    required this.montantInitial,
    required this.montantRembourse,
    required this.montantRestant,
    required this.tauxService,
    required this.typeRemboursement,
    this.montantFluxQuotidien,
    required this.statut,
    required this.operateurMm,
    this.description,
    required this.dateCreation,
    required this.dateEcheance,
    required this.pourcentageRembourse,
    this.scoreAuMomentOctroi,
  });

  factory ContratModel.fromJson(Map<String, dynamic> json) => ContratModel(
    id: json['id'] as String,
    clientId: json['client_id'] as String,
    commercantId: json['commercant_id'] as String,
    montantInitial: (json['montant_initial'] as num).toDouble(),
    montantRembourse: (json['montant_rembourse'] as num).toDouble(),
    montantRestant: (json['montant_restant'] as num).toDouble(),
    tauxService: (json['taux_service'] as num).toDouble(),
    typeRemboursement: json['type_remboursement'] as String,
    montantFluxQuotidien: json['montant_flux_quotidien'] != null
        ? (json['montant_flux_quotidien'] as num).toDouble()
        : null,
    statut: json['statut'] as String,
    operateurMm: json['operateur_mm'] as String? ?? '',
    description: json['description'] as String?,
    dateCreation: DateTime.parse(json['date_creation'] as String),
    dateEcheance: DateTime.parse(json['date_echeance'] as String),
    pourcentageRembourse: (json['pourcentage_rembourse'] as num).toDouble(),
    scoreAuMomentOctroi: json['score_au_moment_octroi'] as int?,
  );

  String get montantInitialFormate => '${_fcfa.format(montantInitial)} FCFA';
  String get montantRestantFormate => '${_fcfa.format(montantRestant)} FCFA';
  String get montantRembourseFormate => '${_fcfa.format(montantRembourse)} FCFA';
  String get dateEcheanceFormatee => DateFormat('dd/MM/yyyy').format(dateEcheance);
  String get dateCreationFormatee => DateFormat('dd/MM/yyyy').format(dateCreation);

  bool get estEnRetard => statut == 'EN_RETARD';
  bool get estSolde => statut == 'SOLDE';
  bool get estActif => statut == 'ACTIF';
}

class ClientModel {
  final String id;
  final String nomComplet;
  final String telephone;
  final String? quartierResidence;
  final bool aGarant;
  final DateTime dateCreation;
  final String? waveNumero;
  final String? orangeMoneyNumero;
  final String? mtnMomoNumero;
  final String? garantNom;
  final String? garantTelephone;

  ClientModel({
    required this.id,
    required this.nomComplet,
    required this.telephone,
    this.quartierResidence,
    required this.aGarant,
    required this.dateCreation,
    this.waveNumero,
    this.orangeMoneyNumero,
    this.mtnMomoNumero,
    this.garantNom,
    this.garantTelephone,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) => ClientModel(
    id: json['id'] as String,
    nomComplet: json['nom_complet'] as String,
    telephone: json['telephone'] as String,
    quartierResidence: json['quartier_residence'] as String?,
    aGarant: json['a_garant'] as bool? ?? false,
    dateCreation: DateTime.parse(json['date_creation'] as String),
    waveNumero: json['wave_numero'] as String?,
    orangeMoneyNumero: json['orange_money_numero'] as String?,
    mtnMomoNumero: json['mtn_momo_numero'] as String?,
    garantNom: json['garant_nom'] as String?,
    garantTelephone: json['garant_telephone'] as String?,
  );

  String get initiales {
    final parts = nomComplet.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return nomComplet.substring(0, 2).toUpperCase();
  }
}

class ScoreModel {
  final String clientId;
  final int scoreGlobal;
  final Map<String, dynamic> composantes;
  final String niveauRisque;
  final double plafondCreditAutorise;
  final Map<String, dynamic> statistiques;
  final DateTime dateCalcul;

  ScoreModel({
    required this.clientId,
    required this.scoreGlobal,
    required this.composantes,
    required this.niveauRisque,
    required this.plafondCreditAutorise,
    required this.statistiques,
    required this.dateCalcul,
  });

  factory ScoreModel.fromJson(Map<String, dynamic> json) => ScoreModel(
    clientId: json['client_id'] as String,
    scoreGlobal: json['score_global'] as int,
    composantes: json['composantes'] as Map<String, dynamic>,
    niveauRisque: json['niveau_risque'] as String,
    plafondCreditAutorise: (json['plafond_credit_autorise'] as num).toDouble(),
    statistiques: json['statistiques'] as Map<String, dynamic>,
    dateCalcul: DateTime.parse(json['date_calcul'] as String),
  );

  String get plafondFormate => '${NumberFormat('#,###', 'fr_FR').format(plafondCreditAutorise)} FCFA';
}
