import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_role.dart';

class AddAdminScreen extends StatefulWidget {
  const AddAdminScreen({super.key});

  @override
  State<AddAdminScreen> createState() => _AddAdminScreenState();
}

class _AddAdminScreenState extends State<AddAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabase = Supabase.instance.client;

  AdminRole? _currentRole;
  String? _currentStationId;
  String _selectedRole = 'field_officer';
  String? _selectedStationId;
  List<Map<String, dynamic>> _stations = [];
  Map<String, Set<String>> _occupiedOcAssignments = {
    'central_admin': <String>{},
    'station_admin': <String>{},
  };
  bool _isLoading = true;
  bool _isCreating = false;
  String? _loadError;

  List<String> get _availableRoles {
    switch (_currentRole) {
      case AdminRole.systemAdmin:
        return [
          'system_admin',
          'central_admin',
          'station_admin',
          'field_officer',
        ];
      case AdminRole.centralAdmin:
        return ['station_admin', 'field_officer'];
      case AdminRole.stationAdmin:
        return ['field_officer'];
      default:
        return [];
    }
  }

  List<Map<String, dynamic>> get _availableStations {
    Iterable<Map<String, dynamic>> stations = _stations;
    if (_currentRole == AdminRole.centralAdmin) {
      stations = stations.where(
        (station) =>
            station['parent_station_id']?.toString() == _currentStationId,
      );
    } else if (_currentRole == AdminRole.stationAdmin) {
      stations = stations.where(
        (station) => station['id']?.toString() == _currentStationId,
      );
    }

    if (_selectedRole == 'central_admin') {
      stations = stations.where(
        (station) =>
            station['station_type'] == 'cps' &&
            !(_occupiedOcAssignments['central_admin'] ?? <String>{}).contains(
              station['id']?.toString(),
            ),
      );
    } else if (_selectedRole == 'station_admin' ||
        _selectedRole == 'field_officer') {
      stations = stations.where(
        (station) =>
            station['station_type'] == 'station' &&
            (_selectedRole == 'field_officer' ||
                !(_occupiedOcAssignments['station_admin'] ?? <String>{})
                    .contains(station['id']?.toString())),
      );
    } else {
      return [];
    }

    return stations.toList();
  }

  @override
  void initState() {
    super.initState();
    _loadManagementContext();
  }

  Future<void> _loadManagementContext() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('You must be signed in to manage accounts.');
      }

      final profile = await _supabase
          .from('user_profiles')
          .select('role, assigned_station_id')
          .eq('user_id', user.id)
          .single();
      final stations = await _supabase
          .from('police_stations')
          .select('id, name, district, station_type, parent_station_id')
          .order('name');
      final existingOcs = List<Map<String, dynamic>>.from(
        await _supabase
            .from('user_profiles')
            .select('role, assigned_station_id')
            .inFilter('role', ['central_admin', 'station_admin']),
      );
      final occupiedAssignments = <String, Set<String>>{
        'central_admin': <String>{},
        'station_admin': <String>{},
      };
      for (final profile in existingOcs) {
        final role = profile['role']?.toString();
        final stationId = profile['assigned_station_id']?.toString();
        if (stationId != null && occupiedAssignments.containsKey(role)) {
          occupiedAssignments[role]!.add(stationId);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentRole = AdminRole.fromDatabase(profile['role'] as String?);
        _currentStationId = profile['assigned_station_id']?.toString();
        _stations = List<Map<String, dynamic>>.from(stations);
        _occupiedOcAssignments = occupiedAssignments;
        final roles = _availableRoles;
        if (roles.isNotEmpty) _selectedRole = roles.last;
        _selectedStationId = _availableStations.firstOrNull?['id']?.toString();
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

  Future<String?> _showStationPicker(
    List<Map<String, dynamic>> stations,
    String label,
  ) async {
    final searchController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var query = '';
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final normalizedQuery = query.trim().toLowerCase();
              final matchingStations = stations.where((station) {
                final name = station['name']?.toString().toLowerCase() ?? '';
                final district =
                    station['district']?.toString().toLowerCase() ?? '';
                return name.contains(normalizedQuery) ||
                    district.contains(normalizedQuery);
              }).toList();
              return AlertDialog(
                title: Text('Select $label'),
                content: SizedBox(
                  width: 420,
                  height: 360,
                  child: Column(
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Search police locations',
                          hintText: 'Name or district',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setDialogState(() => query = value),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: matchingStations.isEmpty
                            ? const Center(
                                child: Text('No matching locations.'),
                              )
                            : ListView.builder(
                                itemCount: matchingStations.length,
                                itemBuilder: (context, index) {
                                  final station = matchingStations[index];
                                  final id = station['id'].toString();
                                  return ListTile(
                                    title: Text(
                                      station['name']?.toString() ??
                                          'Unnamed location',
                                    ),
                                    subtitle: Text(
                                      station['district']?.toString() ?? '',
                                    ),
                                    trailing: id == _selectedStationId
                                        ? const Icon(
                                            Icons.check,
                                            color: Color(0xFF003366),
                                          )
                                        : null,
                                    onTap: () =>
                                        Navigator.pop(dialogContext, id),
                                  );
                                },
                              ),
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
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _createNewAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole != 'system_admin' && _selectedStationId == null) {
      _showMessage('Select an assigned CPS or police station.');
      return;
    }

    setState(() => _isCreating = true);
    try {
      await _supabase.functions.invoke(
        'swift-handler',
        body: {
          'action': 'create-admin',
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'role': _selectedRole,
          'station_id': _selectedStationId,
        },
      );

      if (!mounted) return;
      _showMessage('Account created successfully.');
      Navigator.pop(context);
    } catch (error) {
      _showMessage('Could not create account: $error');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = _availableRoles;
    final stations = _availableStations;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text('Staff Management'),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Text('Unable to load assignment options: $_loadError'),
            )
          : roles.isEmpty
          ? const Center(
              child: Text('Your role is not allowed to create staff accounts.'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create Staff Account',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003366),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildField(_firstNameController, 'First Name'),
                        _buildField(_lastNameController, 'Last Name'),
                        _buildField(_emailController, 'Email'),
                        _buildField(
                          _passwordController,
                          'Password (minimum 6 characters)',
                          isPassword: true,
                        ),
                        DropdownButtonFormField<String>(
                          value: _selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Assigned Role',
                          ),
                          items: roles
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(
                                    AdminRole.fromDatabase(role)!.label,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedRole = value;
                              _selectedStationId = _availableStations
                                  .firstOrNull?['id']
                                  ?.toString();
                            });
                          },
                        ),
                        if (_selectedRole != 'system_admin') ...[
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final selected = stations.where(
                                (station) =>
                                    station['id']?.toString() ==
                                    _selectedStationId,
                              );
                              final selectedStation = selected.isEmpty
                                  ? null
                                  : selected.first;
                              final label = _selectedRole == 'central_admin'
                                  ? 'Assigned CPS'
                                  : 'Assigned Police Station';
                              final isOcRole =
                                  _selectedRole == 'central_admin' ||
                                  _selectedRole == 'station_admin';
                              return InkWell(
                                onTap: stations.isEmpty
                                    ? null
                                    : () async {
                                        final id = await _showStationPicker(
                                          stations,
                                          label,
                                        );
                                        if (id != null && mounted) {
                                          setState(
                                            () => _selectedStationId = id,
                                          );
                                        }
                                      },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: label,
                                    helperText: stations.isEmpty && isOcRole
                                        ? 'All eligible locations already have an OC.'
                                        : stations.isEmpty
                                        ? 'No locations are configured for this role.'
                                        : 'Tap to search by name or district',
                                    suffixIcon: const Icon(Icons.search),
                                    enabled: stations.isNotEmpty,
                                  ),
                                  child: Text(
                                    selectedStation == null
                                        ? 'No location selected'
                                        : '${selectedStation['name']} — ${selectedStation['district']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: stations.isEmpty
                                          ? Theme.of(context).disabledColor
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                _isCreating ||
                                    (_selectedRole != 'system_admin' &&
                                        stations.isEmpty)
                                ? null
                                : _createNewAdmin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _isCreating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Create Account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Required';
          if (isPassword && text.length < 6) {
            return 'Password must be at least 6 characters';
          }
          return null;
        },
      ),
    );
  }
}
