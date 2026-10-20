import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_role.dart';

class StationManagementScreen extends StatefulWidget {
  const StationManagementScreen({super.key});

  @override
  State<StationManagementScreen> createState() =>
      _StationManagementScreenState();
}

class _StationManagementScreenState extends State<StationManagementScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _stations = [];
  AdminRole? _role;
  String? _assignedStationId;
  bool _isLoading = true;
  String? _loadError;
  String _searchQuery = '';
  Map<String, Map<String, dynamic>> _officersInCharge = {};

  bool get _isSystemAdmin => _role == AdminRole.systemAdmin;
  bool get _canAssignStationOcs =>
      _isSystemAdmin || _role == AdminRole.centralAdmin;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('You must be signed in.');

      final profile = await _supabase
          .from('user_profiles')
          .select('role, assigned_station_id')
          .eq('user_id', user.id)
          .single();
      final response = await _supabase
          .from('police_stations')
          .select(
            'id, name, district, address, phone_number, station_type, parent_station_id',
          )
          .order('district')
          .order('name');

      if (!mounted) return;
      final role = AdminRole.fromDatabase(profile['role'] as String?);
      final assignedId = profile['assigned_station_id']?.toString();
      var stations = List<Map<String, dynamic>>.from(response);
      if (role == AdminRole.centralAdmin) {
        stations = stations
            .where(
              (station) =>
                  station['parent_station_id']?.toString() == assignedId,
            )
            .toList();
      }

      final stationIds = stations
          .where(
            (station) =>
                station['station_type'] == 'station' ||
                station['station_type'] == 'cps',
          )
          .map((station) => station['id'].toString())
          .toList();
      final officers = stationIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                  .from('user_profiles')
                  .select(
                    'user_id, assigned_station_id, first_name, last_name, email, role',
                  )
                  .inFilter('assigned_station_id', stationIds)
                  .inFilter('role', ['station_admin', 'central_admin'])
                  .eq('account_status', 'active'),
            );

      final officersByStation = <String, Map<String, dynamic>>{};
      for (final officer in officers) {
        final officerStationId = officer['assigned_station_id']?.toString();
        final assignedStation = stations.where(
          (item) => item['id']?.toString() == officerStationId,
        );
        if (assignedStation.isEmpty) continue;
        final stationType = assignedStation.first['station_type'];
        final isOcRole = stationType == 'cps'
            ? officer['role'] == 'central_admin'
            : stationType == 'station' && officer['role'] == 'station_admin';
        if (isOcRole && officerStationId != null) {
          officersByStation[officerStationId] = officer;
        }
      }

      setState(() {
        _role = role;
        _assignedStationId = assignedId;
        _stations = stations;
        _officersInCharge = officersByStation;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showStationDialog({Map<String, dynamic>? station}) async {
    final isEditing = station != null;
    final nameController = TextEditingController(
      text: station?['name']?.toString() ?? '',
    );
    final districtController = TextEditingController(
      text: station?['district']?.toString() ?? '',
    );
    final addressController = TextEditingController(
      text: station?['address']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: station?['phone_number']?.toString() ?? '',
    );
    var stationType = station?['station_type']?.toString() ?? 'station';
    String? parentStationId = station?['parent_station_id']?.toString();
    final parentChoices = _isSystemAdmin
        ? _stations
              .where(
                (item) =>
                    item['station_type'] == 'cps' &&
                    item['id']?.toString() != station?['id']?.toString(),
              )
              .toList()
        : <Map<String, dynamic>>[];

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Station' : 'Add Station'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: districtController,
                  decoration: const InputDecoration(labelText: 'District'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                if (_isSystemAdmin)
                  DropdownButtonFormField<String>(
                    initialValue: stationType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'cps', child: Text('CPS')),
                      DropdownMenuItem(
                        value: 'station',
                        child: Text('Police Station'),
                      ),
                      DropdownMenuItem(
                        value: 'post',
                        child: Text('Police Post'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        stationType = value;
                        if (value == 'cps') parentStationId = null;
                      });
                    },
                  ),
                if (_isSystemAdmin && stationType != 'cps')
                  DropdownButtonFormField<String>(
                    initialValue:
                        parentChoices.any(
                          (item) => item['id']?.toString() == parentStationId,
                        )
                        ? parentStationId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Parent CPS (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('No CPS assignment'),
                      ),
                      ...parentChoices.map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(item['name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => parentStationId = value),
                  ),
                if (!_isSystemAdmin)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('This station will be added under your CPS.'),
                    ),
                  ),
                if (isEditing &&
                    (stationType == 'station' || stationType == 'cps'))
                  Builder(
                    builder: (context) {
                      final oc = _officersInCharge[station['id'].toString()];
                      final ocName = oc == null
                          ? 'Not assigned'
                          : '${oc['first_name'] ?? ''} ${oc['last_name'] ?? ''}'
                                .trim();
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stationType == 'cps'
                                    ? 'CPS Officer in Charge'
                                    : 'Station Officer in Charge',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(ocName),
                              if (oc != null) ...[
                                if (oc['email']?.toString().isNotEmpty == true)
                                  Text(oc['email'].toString()),
                                Text(
                                  stationType == 'cps'
                                      ? 'Central Admin'
                                      : 'Station Admin',
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final district = districtController.text.trim();
                if (name.isEmpty || district.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Station name and district are required.'),
                    ),
                  );
                  return;
                }
                try {
                  final values = {
                    'name': name,
                    'district': district,
                    'address': addressController.text.trim().isEmpty
                        ? null
                        : addressController.text.trim(),
                    'phone_number': phoneController.text.trim().isEmpty
                        ? null
                        : phoneController.text.trim(),
                    'station_type': _isSystemAdmin ? stationType : 'station',
                    'parent_station_id': _isSystemAdmin
                        ? (stationType == 'cps' ? null : parentStationId)
                        : _assignedStationId,
                  };
                  if (isEditing) {
                    await _supabase
                        .from('police_stations')
                        .update(values)
                        .eq('id', station['id']);
                  } else {
                    await _supabase.from('police_stations').insert(values);
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    final message =
                        error is PostgrestException && error.code == '42501'
                        ? 'The database rejected this station change. Apply the latest station OC migration and confirm the station is assigned under your CPS.'
                        : 'Unable to save station: $error';
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(message)));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    districtController.dispose();
    addressController.dispose();
    phoneController.dispose();
    if (saved == true) await _loadStations();
  }

  Future<void> _showStationOcDialog(Map<String, dynamic> station) async {
    final stationId = station['id'].toString();
    try {
      final candidates = List<Map<String, dynamic>>.from(
        await _supabase
            .from('user_profiles')
            .select('user_id, first_name, last_name, email, role')
            .eq('assigned_station_id', stationId)
            .eq('account_status', 'active')
            .inFilter('role', ['station_admin', 'field_officer'])
            .order('first_name'),
      );
      if (!mounted) return;

      final currentOcId = _officersInCharge[stationId]?['user_id']?.toString();
      final selectedUserId = await showDialog<String?>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Station OC — ${station['name']}'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Not set'),
                  trailing: currentOcId == null
                      ? const Icon(Icons.check, color: Color(0xFF003366))
                      : null,
                  onTap: () => Navigator.pop(dialogContext, ''),
                ),
                for (final candidate in candidates)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      '${candidate['first_name'] ?? ''} ${candidate['last_name'] ?? ''}'
                          .trim(),
                    ),
                    subtitle: Text(
                      '${candidate['email'] ?? ''} • ${candidate['role'] == 'station_admin' ? 'Current Station Admin' : 'Field Officer'}',
                    ),
                    trailing: candidate['user_id']?.toString() == currentOcId
                        ? const Icon(Icons.check, color: Color(0xFF003366))
                        : null,
                    onTap: () => Navigator.pop(
                      dialogContext,
                      candidate['user_id'].toString(),
                    ),
                  ),
                if (candidates.isEmpty)
                  const ListTile(
                    title: Text('No active Station Admins or Field Officers'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selectedUserId == null || !mounted) return;

      await _supabase.rpc(
        'admin_assign_station_oc',
        params: {
          'target_station_id': stationId,
          'target_user_id': selectedUserId.isEmpty ? null : selectedUserId,
        },
      );
      await _loadStations();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to assign station OC: $error')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _visibleStations {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _stations;
    return _stations.where((station) {
      final name = station['name']?.toString().toLowerCase() ?? '';
      final district = station['district']?.toString().toLowerCase() ?? '';
      final type = station['station_type']?.toString().toLowerCase() ?? '';
      final ocDetails = _officersInCharge[station['id']?.toString()];
      final oc =
          '${ocDetails?['first_name'] ?? ''} ${ocDetails?['last_name'] ?? ''} ${ocDetails?['email'] ?? ''}'
              .toLowerCase();
      return name.contains(query) ||
          district.contains(query) ||
          type.contains(query) ||
          oc.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Station Management'),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadStations, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: !_isLoading && _loadError == null
          ? FloatingActionButton.extended(
              onPressed: () => _showStationDialog(),
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Add Station'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text('Unable to load stations: $_loadError'))
          : _stations.isEmpty
          ? const Center(
              child: Text('No stations are assigned to this area yet.'),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search stations',
                      hintText: 'Name, district, type, or OC',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Expanded(
                  child: _visibleStations.isEmpty
                      ? const Center(child: Text('No matching stations.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _visibleStations.length,
                          itemBuilder: (context, index) {
                            final station = _visibleStations[index];
                            final stationId = station['id'].toString();
                            final type =
                                station['station_type']?.toString() ??
                                'station';
                            final parent = _stations.where(
                              (item) =>
                                  item['id']?.toString() ==
                                  station['parent_station_id']?.toString(),
                            );
                            final parentName = parent.isEmpty
                                ? null
                                : parent.first['name']?.toString();
                            final oc = _officersInCharge[stationId];
                            final ocName = oc == null
                                ? 'Not set'
                                : '${oc['first_name'] ?? ''} ${oc['last_name'] ?? ''}'
                                      .trim();
                            final showOc = type == 'station' || type == 'cps';

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  type == 'cps'
                                      ? Icons.account_balance
                                      : Icons.local_police,
                                  color: const Color(0xFF003366),
                                ),
                                title: Text(
                                  station['name']?.toString() ?? 'Unnamed',
                                ),
                                subtitle: Text(
                                  '${station['district']} • ${type.toUpperCase()}'
                                  '${parentName == null ? '' : ' • $parentName'}'
                                  '${showOc ? ' • OC: $ocName' : ''}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canAssignStationOcs &&
                                        type == 'station')
                                      IconButton(
                                        tooltip: 'Set Station OC',
                                        onPressed: () =>
                                            _showStationOcDialog(station),
                                        icon: const Icon(
                                          Icons.person_add_alt_1_outlined,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Edit station',
                                      onPressed: () =>
                                          _showStationDialog(station: station),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
