import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/contrat_model.dart';
import '../../clients/presentation/clients_screen.dart';
import 'package:intl/intl.dart';

class NouveauContratScreen extends ConsumerStatefulWidget {
  const NouveauContratScreen({super.key});

  @override
  ConsumerState<NouveauContratScreen> createState() =>
      _NouveauContratScreenState();
}

class _NouveauContratScreenState extends ConsumerState<NouveauContratScreen> {
  final _formKey = GlobalKey<FormState>();
  ClientModel? _clientSelectionne;
  final _montantCtrl = TextEditingController();
  final _fluxCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _dateEcheance = DateTime.now().add(const Duration(days: 30));
  String _operateur = 'wave';
  String _typeRemboursement = 'FLUX_QUOTIDIEN';
  bool _loading = false;
  Map<String, dynamic>? _resultDecision;


  Future<void> _verifierEligibilite() async {
    if (_clientSelectionne == null || _montantCtrl.text.isEmpty) return;
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', ''));
    if (montant == null) return;

    try {
      final decision = await ref.read(apiClientProvider).verifierEligibilite(
        _clientSelectionne!.id,
        montant,
      );
      setState(() => _resultDecision = decision);
    } catch (_) {
      setState(() => _resultDecision = null);
    }
  }

  Future<void> _creerContrat() async {
    if (!_formKey.currentState!.validate()) return;
    if (_clientSelectionne == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez un client'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final montant = double.parse(_montantCtrl.text.replaceAll(' ', ''));
      final data = await ref.read(apiClientProvider).creerContrat({
        'client_id': _clientSelectionne!.id,
        'montant_initial': montant,
        'date_echeance': _dateEcheance.toIso8601String(),
        'operateur_mm': _operateur,
        'type_remboursement': _typeRemboursement,
        if (_typeRemboursement == 'FLUX_QUOTIDIEN' && _fluxCtrl.text.isNotEmpty)
          'montant_flux_quotidien': double.tryParse(_fluxCtrl.text),
        if (_descCtrl.text.isNotEmpty) 'description': _descCtrl.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contrat créé – notification WhatsApp envoyée'),
            backgroundColor: AppColors.succes,
          ),
        );
        final contratId = (data['contrat'] as Map)['id'] as String;
        context.pushReplacement('/contrats/$contratId');
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.contains('403') ? 'Crédit refusé – score insuffisant' : 'Erreur : $msg'),
            backgroundColor: AppColors.danger,
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
      appBar: AppBar(title: const Text('Nouveau Contrat de Crédit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Sélection client ───────────────────────
            const _SectionHeader('Client'),
            const SizedBox(height: 12),
            _SelecteurClient(
              selectionne: _clientSelectionne,
              onSelectionne: (c) {
                setState(() {
                  _clientSelectionne = c;
                  _resultDecision = null;
                });
              },
            ),
            const SizedBox(height: 24),

            // ── Montant ────────────────────────────────
            const _SectionHeader('Montant du crédit'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montantCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: AppColors.textePrincipal,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant (FCFA)',
                prefixIcon: Icon(Icons.money, color: AppColors.orange),
                suffixText: 'FCFA',
              ),
              onChanged: (_) => setState(() => _resultDecision = null),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requis';
                if (double.tryParse(v.replaceAll(' ', '')) == null) return 'Nombre invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Bouton vérification score
            if (_clientSelectionne != null && _montantCtrl.text.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _verifierEligibilite,
                icon: const Icon(Icons.verified_user, color: AppColors.info),
                label: const Text('Vérifier l\'éligibilité',
                    style: TextStyle(color: AppColors.info)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.info),
                ),
              ),

            // Résultat décision
            if (_resultDecision != null) ...[
              const SizedBox(height: 12),
              _CarteDecision(decision: _resultDecision!),
            ],
            const SizedBox(height: 24),

            // ── Opérateur Mobile Money ─────────────────
            const _SectionHeader('Opérateur Mobile Money'),
            const SizedBox(height: 12),
            _SelecteurOperateur(
              valeur: _operateur,
              onChanged: (v) => setState(() => _operateur = v),
            ),
            const SizedBox(height: 24),

            // ── Type de remboursement ──────────────────
            const _SectionHeader('Mode de remboursement'),
            const SizedBox(height: 12),
            _SelecteurTypeRemboursement(
              valeur: _typeRemboursement,
              onChanged: (v) => setState(() => _typeRemboursement = v),
            ),

            if (_typeRemboursement == 'FLUX_QUOTIDIEN') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _fluxCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textePrincipal),
                decoration: const InputDecoration(
                  labelText: 'Montant par jour (FCFA)',
                  prefixIcon: Icon(Icons.calendar_today, color: AppColors.orange),
                  hintText: 'ex: 500',
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Date d'échéance ────────────────────────
            const _SectionHeader('Date limite de remboursement'),
            const SizedBox(height: 12),
            _SelecteurDate(
              date: _dateEcheance,
              onChanged: (d) => setState(() => _dateEcheance = d),
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _descCtrl,
              style: const TextStyle(color: AppColors.textePrincipal),
              decoration: const InputDecoration(
                labelText: 'Objet du crédit (optionnel)',
                prefixIcon: Icon(Icons.description, color: AppColors.orange),
                hintText: 'ex: Sacs de riz, Tissu wax...',
              ),
            ),
            const SizedBox(height: 32),

            // ── Bouton créer ───────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _creerContrat,
                icon: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: const Text('Créer le contrat'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Widgets spécifiques ──────────────────────────────────────

class _SelecteurClient extends ConsumerWidget {
  final ClientModel? selectionne;
  final void Function(ClientModel) onSelectionne;
  const _SelecteurClient({required this.selectionne, required this.onSelectionne});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);

    if (selectionne != null) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.vert),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.vert.withValues(alpha: 0.2),
            child: Text(selectionne!.initiales,
                style: const TextStyle(color: AppColors.vert, fontWeight: FontWeight.w700)),
          ),
          title: Text(selectionne!.nomComplet,
              style: const TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w600)),
          subtitle: Text(selectionne!.telephone,
              style: const TextStyle(color: AppColors.texteSecondaire)),
          trailing: TextButton(
            onPressed: () => _choisirClient(context, clients.value ?? []),
            child: const Text('Changer', style: TextStyle(color: AppColors.orange)),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => _choisirClient(context, clients.value ?? []),
      icon: const Icon(Icons.person_search, color: AppColors.orange),
      label: const Text('Sélectionner un client',
          style: TextStyle(color: AppColors.orange)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: AppColors.orange),
      ),
    );
  }

  void _choisirClient(BuildContext context, List<ClientModel> clients) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.fondCarte,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Choisir un client',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: AppColors.textePrincipal)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: clients.length,
              itemBuilder: (_, i) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.orange.withValues(alpha: 0.2),
                  child: Text(clients[i].initiales,
                      style: const TextStyle(color: AppColors.orange)),
                ),
                title: Text(clients[i].nomComplet,
                    style: const TextStyle(color: AppColors.textePrincipal)),
                subtitle: Text(clients[i].telephone,
                    style: const TextStyle(color: AppColors.texteSecondaire)),
                onTap: () {
                  Navigator.pop(context);
                  onSelectionne(clients[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelecteurOperateur extends StatelessWidget {
  final String valeur;
  final void Function(String) onChanged;
  const _SelecteurOperateur({required this.valeur, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final op in ['wave', 'orange', 'mtn'])
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(op),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: valeur == op
                    ? AppColors.orange.withValues(alpha: 0.2)
                    : AppColors.fondInput,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: valeur == op ? AppColors.orange : AppColors.bordure,
                  width: valeur == op ? 2 : 1,
                ),
              ),
              child: Text(
                op.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: valeur == op ? AppColors.orange : AppColors.texteSecondaire,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SelecteurTypeRemboursement extends StatelessWidget {
  final String valeur;
  final void Function(String) onChanged;
  const _SelecteurTypeRemboursement({required this.valeur, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (type, label, desc) in [
        ('FLUX_QUOTIDIEN', 'Flux quotidien', 'Ex: 500 FCFA/soir pendant 20 jours'),
        ('ECHEANCES', 'Échéances fixes', 'Ex: 3 versements mensuels'),
        ('LIBRE', 'Libre', 'Le client paie quand il veut avant l\'échéance'),
      ])
        GestureDetector(
          onTap: () => onChanged(type),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: valeur == type
                  ? AppColors.orange.withValues(alpha: 0.1)
                  : AppColors.fondInput,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: valeur == type ? AppColors.orange : AppColors.bordure,
              ),
            ),
            child: Row(
              children: [
                Radio<String>(
                  value: type,
                  groupValue: valeur,
                  onChanged: (v) => v != null ? onChanged(v) : null,
                  activeColor: AppColors.orange,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: AppColors.textePrincipal,
                              fontWeight: FontWeight.w600)),
                      Text(desc,
                          style: const TextStyle(
                              color: AppColors.texteSecondaire, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _SelecteurDate extends StatelessWidget {
  final DateTime date;
  final void Function(DateTime) onChanged;
  const _SelecteurDate({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.orange),
          ),
          child: child!,
        ),
      );
      if (picked != null) onChanged(picked);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.fondInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bordure),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: AppColors.orange),
          const SizedBox(width: 12),
          Text(
            DateFormat('dd MMMM yyyy', 'fr').format(date),
            style: const TextStyle(color: AppColors.textePrincipal, fontSize: 16),
          ),
          const Spacer(),
          const Icon(Icons.edit_calendar, color: AppColors.texteSecondaire, size: 18),
        ],
      ),
    ),
  );
}

class _CarteDecision extends StatelessWidget {
  final Map<String, dynamic> decision;
  const _CarteDecision({required this.decision});

  @override
  Widget build(BuildContext context) {
    final autorise = decision['autorise'] as bool? ?? false;
    final score = decision['score'] as int? ?? 0;
    final raison = decision['raison'] as String? ?? '';
    final plafond = (decision['plafond'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: autorise
            ? AppColors.succes.withValues(alpha: 0.1)
            : AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: autorise ? AppColors.succes : AppColors.danger,
        ),
      ),
      child: Row(
        children: [
          Icon(
            autorise ? Icons.check_circle : Icons.cancel,
            color: autorise ? AppColors.succes : AppColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  autorise ? 'Crédit autorisé' : 'Crédit refusé',
                  style: TextStyle(
                    color: autorise ? AppColors.succes : AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  raison,
                  style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 12),
                ),
                if (autorise && plafond > 0)
                  Text(
                    'Plafond : ${NumberFormat('#,###', 'fr_FR').format(plafond)} FCFA',
                    style: const TextStyle(color: AppColors.info, fontSize: 12),
                  ),
              ],
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              color: AppColors.couleurScore(score),
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String titre;
  const _SectionHeader(this.titre);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.orange.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
    ),
    child: Text(
      titre,
      style: const TextStyle(
        color: AppColors.orange,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    ),
  );
}
