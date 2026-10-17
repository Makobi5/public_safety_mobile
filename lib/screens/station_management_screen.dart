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
  List<Map<String, dynamic>> _stations = [];
  AdminRole? _role;
  String? _assignedStationId;
  bool _isLoading = true;
  String? _loadError;

  bool get _isSystemAdmin => _role == AdminRole.systemAdmin;

  @override
  void initState() {
    super.initState();
    _loadStations();
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
      setState(() {
        _role = role;
        _assignedStationId = assignedId;
        _stations = stations;
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
                    value: stationType,
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
                    value:
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
                  ScaffoldMessenger.of(context).showSnackBar(
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
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Unable to save station: $error')),
                    );
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
    if (saved == true) _loadStations();
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _stations.length,
              itemBuilder: (context, index) {
                final station = _stations[index];
                final type = station['station_type']?.toString() ?? 'station';
                final parent = _stations.where(
                  (item) =>
                      item['id']?.toString() ==
                      station['parent_station_id']?.toString(),
                );
                final parentName = parent.isEmpty
                    ? null
                    : parent.first['name']?.toString();
                return Card(
                  child: ListTile(
                    leading: Icon(
                      type == 'cps'
                          ? Icons.account_balance
                          : Icons.local_police,
                      color: const Color(0xFF003366),
                    ),
                    title: Text(station['name']?.toString() ?? 'Unnamed'),
                    subtitle: Text(
                      '${station['district']} • ${type.toUpperCase()}'
                      '${parentName == null ? '' : ' • $parentName'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Edit station',
                      onPressed: () => _showStationDialog(station: station),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
