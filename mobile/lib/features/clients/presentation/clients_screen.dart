import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/models/contrat_model.dart';

final clientsProvider = FutureProvider<List<ClientModel>>((ref) async {
  final api = ref.read(apiClientProvider);
  final storage = ref.read(localStorageProvider);
  try {
    final data = await api.listerClients();
    await storage.cacherClients(data);
    return data.map((j) => ClientModel.fromJson(j as Map<String, dynamic>)).toList();
  } catch (_) {
    final cache = await storage.lireClientsCache();
    return cache.map((j) => ClientModel.fromJson(j as Map<String, dynamic>)).toList();
  }
});

class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(
              context: context,
              delegate: _RechercheClient(
                clients: clients.value ?? [],
              ),
            ),
          ),
        ],
      ),
      body: clients.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
        error: (e, _) => Center(
          child: Text('Erreur : $e',
              style: const TextStyle(color: AppColors.danger)),
        ),
        data: (liste) => liste.isEmpty
            ? _EtatVide(onAjouter: () => context.push('/clients/nouveau'))
            : RefreshIndicator(
                color: AppColors.orange,
                onRefresh: () async => ref.invalidate(clientsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ClientCard(client: liste[i]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.orange,
        onPressed: () => context.push('/clients/nouveau'),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.fondCarte,
        indicatorColor: AppColors.orange.withValues(alpha: 0.15),
        selectedIndex: 1,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard'); break;
            case 2: context.go('/contrats'); break;
            case 3: context.go('/paiements'); break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Tableau',
          ),
          NavigationDestination(
            icon: Icon(Icons.people, color: AppColors.orange),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Contrats',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            label: 'Paiements',
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final ClientModel client;
  const _ClientCard({required this.client});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: AppColors.orange.withValues(alpha: 0.2),
        child: Text(
          client.initiales,
          style: const TextStyle(
            color: AppColors.orange,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        client.nomComplet,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textePrincipal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            client.telephone,
            style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 13),
          ),
          if (client.quartierResidence != null)
            Text(
              client.quartierResidence!,
              style: const TextStyle(color: AppColors.texteSecondaire, fontSize: 11),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (client.aGarant)
            const Tooltip(
              message: 'A un garant',
              child: Icon(Icons.verified, color: AppColors.succes, size: 18),
            ),
          const Icon(Icons.chevron_right, color: AppColors.texteSecondaire),
        ],
      ),
      onTap: () => context.push('/clients/${client.id}'),
    ),
  );
}

// ── Formulaire Nouveau Client ────────────────────────────────
class NouveauClientScreen extends ConsumerStatefulWidget {
  const NouveauClientScreen({super.key});

  @override
  ConsumerState<NouveauClientScreen> createState() =>
      _NouveauClientScreenState();
}

class _NouveauClientScreenState extends ConsumerState<NouveauClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _waveCtrl = TextEditingController();
  final _orangeCtrl = TextEditingController();
  final _mtnCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();
  final _garantNomCtrl = TextEditingController();
  final _garantTelCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final api = ref.read(apiClientProvider);
      await api.creerClient({
        'nom_complet': _nomCtrl.text.trim(),
        'telephone': _telCtrl.text.trim(),
        if (_waveCtrl.text.isNotEmpty) 'wave_numero': _waveCtrl.text.trim(),
        if (_orangeCtrl.text.isNotEmpty) 'orange_money_numero': _orangeCtrl.text.trim(),
        if (_mtnCtrl.text.isNotEmpty) 'mtn_momo_numero': _mtnCtrl.text.trim(),
        if (_quartierCtrl.text.isNotEmpty) 'quartier_residence': _quartierCtrl.text.trim(),
        if (_garantNomCtrl.text.isNotEmpty) 'garant_nom': _garantNomCtrl.text.trim(),
        if (_garantTelCtrl.text.isNotEmpty) 'garant_telephone': _garantTelCtrl.text.trim(),
      });

      ref.invalidate(clientsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Client enregistré avec succès'),
            backgroundColor: AppColors.succes,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
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
      appBar: AppBar(title: const Text('Nouveau Client')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionHeader('Informations personnelles'),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _nomCtrl,
              label: 'Nom complet *',
              icon: Icons.person,
              validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _telCtrl,
              label: 'Téléphone principal *',
              icon: Icons.phone,
              type: TextInputType.phone,
              hint: '+2250700000000',
              validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _quartierCtrl,
              label: 'Quartier de résidence',
              icon: Icons.location_on,
              hint: 'ex: Treichville, Yopougon...',
            ),
            const SizedBox(height: 24),

            const _SectionHeader('Comptes Mobile Money'),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _waveCtrl,
              label: 'Numéro Wave',
              icon: Icons.waves,
              type: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _orangeCtrl,
              label: 'Numéro Orange Money',
              icon: Icons.circle,
              type: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _mtnCtrl,
              label: 'Numéro MTN MoMo',
              icon: Icons.circle_outlined,
              type: TextInputType.phone,
            ),
            const SizedBox(height: 24),

            const _SectionHeader('Garant (optionnel – booste le score de 15%)'),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _garantNomCtrl,
              label: 'Nom du garant',
              icon: Icons.verified_user,
              hint: 'ex: Chef de quartier Yao',
            ),
            const SizedBox(height: 12),
            _ChampTexte(
              controller: _garantTelCtrl,
              label: 'Téléphone du garant',
              icon: Icons.phone_in_talk,
              type: TextInputType.phone,
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _enregistrer,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Enregistrer le client'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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

class _ChampTexte extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final TextInputType? type;
  final String? Function(String?)? validator;

  const _ChampTexte({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.type,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: type,
    style: const TextStyle(color: AppColors.textePrincipal),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.orange, size: 20),
    ),
    validator: validator,
  );
}

// ── Modification Client ──────────────────────────────────────
class ModifierClientScreen extends ConsumerStatefulWidget {
  final ClientModel client;
  const ModifierClientScreen({super.key, required this.client});

  @override
  ConsumerState<ModifierClientScreen> createState() => _ModifierClientScreenState();
}

class _ModifierClientScreenState extends ConsumerState<ModifierClientScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nomCtrl = TextEditingController(text: widget.client.nomComplet);
  late final _telCtrl = TextEditingController(text: widget.client.telephone);
  late final _quartierCtrl = TextEditingController(text: widget.client.quartierResidence ?? '');
  late final _waveCtrl = TextEditingController(text: widget.client.waveNumero ?? '');
  late final _orangeCtrl = TextEditingController(text: widget.client.orangeMoneyNumero ?? '');
  late final _mtnCtrl = TextEditingController(text: widget.client.mtnMomoNumero ?? '');
  late final _garantNomCtrl = TextEditingController(text: widget.client.garantNom ?? '');
  late final _garantTelCtrl = TextEditingController(text: widget.client.garantTelephone ?? '');
  bool _loading = false;

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).modifierClient(widget.client.id, {
        'nom_complet': _nomCtrl.text.trim(),
        'telephone': _telCtrl.text.trim(),
        'quartier_residence': _quartierCtrl.text.trim(),
        'wave_numero': _waveCtrl.text.trim(),
        'orange_money_numero': _orangeCtrl.text.trim(),
        'mtn_momo_numero': _mtnCtrl.text.trim(),
        'garant_nom': _garantNomCtrl.text.trim(),
        'garant_telephone': _garantTelCtrl.text.trim(),
      });
      ref.invalidate(clientsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modifications enregistrées'), backgroundColor: AppColors.succes),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Modifier ${widget.client.nomComplet}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionHeader('Informations personnelles'),
            const SizedBox(height: 12),
            _ChampTexte(controller: _nomCtrl, label: 'Nom complet *', icon: Icons.person,
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null),
            const SizedBox(height: 12),
            _ChampTexte(controller: _telCtrl, label: 'Téléphone *', icon: Icons.phone,
                type: TextInputType.phone,
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null),
            const SizedBox(height: 12),
            _ChampTexte(controller: _quartierCtrl, label: 'Quartier', icon: Icons.location_on),
            const SizedBox(height: 24),
            const _SectionHeader('Comptes Mobile Money'),
            const SizedBox(height: 12),
            _ChampTexte(controller: _waveCtrl, label: 'Numéro Wave', icon: Icons.waves, type: TextInputType.phone),
            const SizedBox(height: 12),
            _ChampTexte(controller: _orangeCtrl, label: 'Orange Money', icon: Icons.circle, type: TextInputType.phone),
            const SizedBox(height: 12),
            _ChampTexte(controller: _mtnCtrl, label: 'MTN MoMo', icon: Icons.circle_outlined, type: TextInputType.phone),
            const SizedBox(height: 24),
            const _SectionHeader('Garant'),
            const SizedBox(height: 12),
            _ChampTexte(controller: _garantNomCtrl, label: 'Nom du garant', icon: Icons.verified_user),
            const SizedBox(height: 12),
            _ChampTexte(controller: _garantTelCtrl, label: 'Téléphone garant', icon: Icons.phone_in_talk, type: TextInputType.phone),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _enregistrer,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Enregistrer les modifications'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Recherche ────────────────────────────────────────────────
class _RechercheClient extends SearchDelegate<ClientModel?> {
  final List<ClientModel> clients;
  _RechercheClient({required this.clients});

  @override
  String get searchFieldLabel => 'Rechercher un client...';

  @override
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      );

  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildListe(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildListe(context);

  Widget _buildListe(BuildContext context) {
    final filtres = clients.where((c) =>
        c.nomComplet.toLowerCase().contains(query.toLowerCase()) ||
        c.telephone.contains(query)).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtres.length,
      itemBuilder: (_, i) => _ClientCard(client: filtres[i]),
    );
  }
}

// ── État vide ────────────────────────────────────────────────
class _EtatVide extends StatelessWidget {
  final VoidCallback onAjouter;
  const _EtatVide({required this.onAjouter});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people_outline, size: 80,
            color: AppColors.texteSecondaire.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        const Text('Aucun client enregistré',
            style: TextStyle(color: AppColors.texteSecondaire, fontSize: 16)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onAjouter,
          icon: const Icon(Icons.person_add),
          label: const Text('Ajouter un client'),
        ),
      ],
    ),
  );
}
