import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/admin_role.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String? _currentUserRole;
  String? _currentUserStationId;
  List<Map<String, dynamic>> _stations = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentRole();
    _fetchUsers();
  }

  Future<void> _loadCurrentRole() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw StateError('You must be signed in to manage users.');
      }
      final profile = await supabase
          .from('user_profiles')
          .select('role, assigned_station_id')
          .eq('user_id', user.id)
          .maybeSingle();
      await _refreshStations();
      if (mounted) {
        setState(() {
          _currentUserRole = profile?['role'] as String?;
          _currentUserStationId = profile?['assigned_station_id']?.toString();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load your management scope: $error'),
          ),
        );
      }
    }
  }

  Future<void> _refreshStations() async {
    final data = await supabase
        .from('police_stations')
        .select('id, name, district, station_type, parent_station_id')
        .order('name');
    if (mounted) {
      setState(() => _stations = List<Map<String, dynamic>>.from(data));
    }
  }

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('user_profiles')
          .select()
          .order('first_name', ascending: true);

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(data);
          _filteredUsers = _users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching users: $e")));
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _filteredUsers = _users.where((user) {
        final name = "${user['first_name']} ${user['last_name']}".toLowerCase();
        final email = user['email']?.toString().toLowerCase() ?? "";
        return name.contains(query.toLowerCase()) ||
            email.contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<String?> _showStationPicker(
    List<Map<String, dynamic>> stations,
    String? selectedStationId,
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
              final filteredStations = stations.where((station) {
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
                          labelText: 'Search locations',
                          hintText: 'Station name or district',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setDialogState(() => query = value),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filteredStations.isEmpty
                            ? const Center(
                                child: Text('No matching locations.'),
                              )
                            : ListView.builder(
                                itemCount: filteredStations.length,
                                itemBuilder: (context, index) {
                                  final station = filteredStations[index];
                                  final stationId = station['id'].toString();
                                  return ListTile(
                                    title: Text(
                                      station['name']?.toString() ??
                                          'Unnamed location',
                                    ),
                                    subtitle: Text(
                                      station['district']?.toString() ?? '',
                                    ),
                                    trailing: stationId == selectedStationId
                                        ? const Icon(
                                            Icons.check,
                                            color: Color(0xFF003366),
                                          )
                                        : null,
                                    onTap: () =>
                                        Navigator.pop(dialogContext, stationId),
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

  // --- 1. EDIT ROLE DIALOG (Implementation of Screenshot 2) ---
  Future<void> _showEditRoleDialog(Map<String, dynamic> targetUser) async {
    try {
      await _refreshStations();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load police stations: $error')),
        );
      }
      return;
    }
    if (!mounted) return;

    final actorRole = AdminRole.fromDatabase(_currentUserRole);
    final targetRole = AdminRole.fromDatabase(targetUser['role']?.toString());
    if (actorRole == null ||
        targetRole == null ||
        targetRole == AdminRole.standardUser ||
        !actorRole.canManageStaff) {
      return;
    }

    final allowedRoles = switch (actorRole) {
      AdminRole.systemAdmin => [
        'system_admin',
        'central_admin',
        'station_admin',
        'field_officer',
      ],
      AdminRole.centralAdmin => ['station_admin', 'field_officer'],
      AdminRole.stationAdmin => ['field_officer'],
      _ => <String>[],
    };
    if (!allowedRoles.contains(targetUser['role'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot manage this account.')),
      );
      return;
    }

    String selectedRole = targetUser['role'].toString();
    String selectedStatus =
        targetUser['account_status']?.toString() ?? 'active';
    String? selectedStationId = targetUser['assigned_station_id']?.toString();

    List<Map<String, dynamic>> availableStations(String role) {
      if (role == 'system_admin') return [];
      Iterable<Map<String, dynamic>> choices = _stations;
      if (actorRole == AdminRole.centralAdmin) {
        choices = choices.where(
          (station) =>
              station['parent_station_id']?.toString() == _currentUserStationId,
        );
      } else if (actorRole == AdminRole.stationAdmin) {
        choices = choices.where(
          (station) => station['id']?.toString() == _currentUserStationId,
        );
      }
      if (role == 'central_admin') {
        choices = choices.where(
          (station) =>
              station['station_type']?.toString().toLowerCase() == 'cps',
        );
      } else {
        choices = choices.where(
          (station) =>
              station['station_type']?.toString().toLowerCase() == 'station',
        );
      }
      if (role == 'central_admin' || role == 'station_admin') {
        choices = choices.where((station) {
          final stationId = station['id']?.toString();
          return !_users.any(
            (user) =>
                user['user_id']?.toString() !=
                    targetUser['user_id']?.toString() &&
                user['role'] == role &&
                user['assigned_station_id']?.toString() == stationId,
          );
        });
      }
      return choices.toList();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Edit User Role",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: allowedRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(AdminRole.fromDatabase(role)!.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedRole = value;
                    final stations = availableStations(value);
                    if (!stations.any(
                      (station) =>
                          station['id']?.toString() == selectedStationId,
                    )) {
                      selectedStationId = stations.isEmpty
                          ? null
                          : stations.first['id'].toString();
                    }
                  });
                },
              ),
              if (selectedRole != 'system_admin')
                Builder(
                  builder: (context) {
                    final stations = availableStations(selectedRole);
                    Map<String, dynamic>? selectedStation;
                    for (final station in stations) {
                      if (station['id']?.toString() == selectedStationId) {
                        selectedStation = station;
                        break;
                      }
                    }
                    final label = selectedRole == 'central_admin'
                        ? 'Assigned CPS'
                        : 'Assigned Police Station';
                    return InkWell(
                      onTap: stations.isEmpty
                          ? null
                          : () async {
                              final stationId = await _showStationPicker(
                                stations,
                                selectedStationId,
                                label,
                              );
                              if (stationId != null) {
                                setDialogState(
                                  () => selectedStationId = stationId,
                                );
                              }
                            },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: stations.isEmpty
                              ? selectedRole == 'central_admin'
                                    ? 'No CPS found. Classify a location as CPS in Station Management, then reopen this dialog.'
                                    : 'No eligible police stations found. Check station classifications.'
                              : 'Tap to search by name or district',
                          suffixIcon: const Icon(Icons.search),
                          enabled: stations.isNotEmpty,
                        ),
                        child: Text(
                          selectedStation == null
                              ? 'No eligible locations'
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
              DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: const InputDecoration(labelText: 'Account status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedStatus = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed:
                  selectedRole != 'system_admin' &&
                      (selectedStationId == null ||
                          !availableStations(selectedRole).any(
                            (station) =>
                                station['id']?.toString() == selectedStationId,
                          ))
                  ? null
                  : () async {
                      try {
                        await supabase.rpc(
                          'admin_update_user_access',
                          params: {
                            'target_user_id': targetUser['user_id'],
                            'new_role': selectedRole,
                            'new_station_id': selectedRole == 'system_admin'
                                ? null
                                : selectedStationId,
                            'new_account_status': selectedStatus,
                          },
                        );
                        if (mounted) Navigator.pop(context);
                        _fetchUsers();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Update failed: $e")),
                          );
                        }
                      }
                    },
              child: const Text(
                "Update Role",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDetailsDialog(Map<String, dynamic> targetUser) async {
    final firstNameController = TextEditingController(
      text: targetUser['first_name']?.toString() ?? '',
    );
    final lastNameController = TextEditingController(
      text: targetUser['last_name']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: targetUser['email']?.toString() ?? '',
    );
    final regionController = TextEditingController(
      text: targetUser['region']?.toString() ?? '',
    );
    final districtController = TextEditingController(
      text: targetUser['district']?.toString() ?? '',
    );
    final subCountyController = TextEditingController(
      text: targetUser['sub_county']?.toString() ?? '',
    );
    final villageController = TextEditingController(
      text: targetUser['village_area']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Account Details'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailsField(firstNameController, 'First name'),
                _detailsField(lastNameController, 'Last name'),
                _detailsField(emailController, 'Email'),
                _detailsField(regionController, 'Region'),
                _detailsField(districtController, 'District'),
                _detailsField(subCountyController, 'Sub-county'),
                _detailsField(villageController, 'Village / area'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (firstNameController.text.trim().isEmpty ||
                  lastNameController.text.trim().isEmpty ||
                  !emailController.text.trim().contains('@')) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter a first name, last name, and valid email.',
                    ),
                  ),
                );
                return;
              }
              try {
                await supabase.rpc(
                  'admin_update_user_details',
                  params: {
                    'target_user_id': targetUser['user_id'],
                    'new_first_name': firstNameController.text.trim(),
                    'new_last_name': lastNameController.text.trim(),
                    'new_email': emailController.text.trim(),
                    'new_region': regionController.text.trim(),
                    'new_district': districtController.text.trim(),
                    'new_sub_county': subCountyController.text.trim(),
                    'new_village_area': villageController.text.trim(),
                  },
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Update failed: $error')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    regionController.dispose();
    districtController.dispose();
    subCountyController.dispose();
    villageController.dispose();
    if (saved == true) _fetchUsers();
  }

  Widget _detailsField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  // --- 2. RESET PASSWORD DIALOG (Implementation of Screenshot 3) ---
  void _showResetPasswordDialog(Map<String, dynamic> targetUser) {
    final TextEditingController _passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Reset User Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter a new password for:"),
            Text(
              targetUser['email'] ?? "",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New Password",
                hintText: "Minimum 6 characters",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
            ),
            onPressed: () async {
              if (_passController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password too short!")),
                );
                return;
              }

              try {
                // CALL THE DATABASE RPC METHOD
                await supabase.rpc(
                  'admin_reset_password',
                  params: {
                    'target_user_id': targetUser['user_id'],
                    'new_password': _passController.text.trim(),
                  },
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Password reset successfully via Database RPC",
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text(
              "Confirm Reset",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. DELETE CONFIRMATION (Implementation of Screenshot 4) ---
  void _showDeleteConfirmDialog(Map<String, dynamic> targetUser) {
    if (targetUser['user_id'] == supabase.auth.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Safety Error: You cannot delete yourself!"),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent clicking outside during delete
      builder: (context) {
        var isDeleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text("Confirm Delete"),
              content: isDeleting
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Text(
                      "Are you sure you want to delete ${targetUser['first_name']} ${targetUser['last_name']}? This action will remove their account permanently.",
                    ),
              actions: isDeleting
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          setDialogState(() => isDeleting = true);

                          try {
                            // CALL THE NEW DELETE RPC
                            await supabase.rpc(
                              'admin_delete_user',
                              params: {'target_user_id': targetUser['user_id']},
                            );

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("User deleted successfully"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _fetchUsers(); // Refresh the list
                            }
                          } catch (e) {
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Delete failed: $e"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        child: const Text(
                          "Delete",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminCount = _users.where((user) {
      final role = AdminRole.fromDatabase(user['role']?.toString());
      return role != null && role.canManageStaff;
    }).length;
    final fieldOfficerCount = _users
        .where((user) => user['role'] == 'field_officer')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text(
          "User Management",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchUsers),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _filterUsers,
              decoration: InputDecoration(
                hintText: "Search users...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildStatCard(
                  "Total Users",
                  _users.length.toString(),
                  Colors.blue,
                ),
                const SizedBox(width: 10),
                _buildStatCard("Admins", adminCount.toString(), Colors.purple),
                const SizedBox(width: 10),
                _buildStatCard(
                  "Field Officers",
                  fieldOfficerCount.toString(),
                  Colors.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return _buildUserCard(user);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    // 1. DATA EXTRACTION
    final String fName = user['first_name'] ?? "";
    final String lName = user['last_name'] ?? "";
    final String email = user['email'] ?? "";
    final String role = user['role'] ?? 'standard_user';
    final assignedStationId = user['assigned_station_id']?.toString();
    final assignedStations = _stations.where(
      (station) => station['id']?.toString() == assignedStationId,
    );
    final assignedStation = assignedStations.isEmpty
        ? null
        : assignedStations.first;
    final String targetUserId = user['user_id'] ?? "";
    final String currentUserId = supabase.auth.currentUser?.id ?? "";

    final actorRole = AdminRole.fromDatabase(_currentUserRole);
    final targetRole = AdminRole.fromDatabase(role);
    final canManageTarget = switch (actorRole) {
      AdminRole.systemAdmin =>
        targetRole != null && targetRole != AdminRole.standardUser,
      AdminRole.centralAdmin =>
        targetRole == AdminRole.stationAdmin ||
            targetRole == AdminRole.fieldOfficer,
      AdminRole.stationAdmin => targetRole == AdminRole.fieldOfficer,
      _ => false,
    };
    final canEditDetails =
        canManageTarget || actorRole == AdminRole.systemAdmin;
    bool isMe = targetUserId == currentUserId;

    // 3. UI STYLING CONSTANTS
    String initials = (fName.isNotEmpty && lName.isNotEmpty)
        ? "${fName[0]}${lName[0]}".toUpperCase()
        : "U";

    Color roleColor;
    String roleLabel;

    switch (role) {
      case 'system_admin':
      case 'super_admin':
        roleColor = Colors.purple;
        roleLabel = "System Admin";
        break;
      case 'central_admin':
        roleColor = Colors.deepPurple;
        roleLabel = "Central Admin";
        break;
      case 'station_admin':
      case 'admin':
        roleColor = Colors.indigo;
        roleLabel = "Station Admin";
        break;
      case 'field_officer':
        roleColor = Colors.orange.shade800;
        roleLabel = "Field Officer";
        break;
      default:
        roleColor = Colors.blue;
        roleLabel = "Standard User";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // TOP SECTION: Profile Info
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: roleColor.withOpacity(0.1),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$fName $lName",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Color(0xFF003366),
                      ),
                    ),
                    Text(
                      email,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (assignedStation != null)
                      Text(
                        '${assignedStation['name']} • ${assignedStation['district']}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: roleColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (user['account_status'] == 'suspended')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'SUSPENDED',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 32, thickness: 1),

          // BOTTOM SECTION: Action Buttons
          if (canEditDetails)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Icons.edit_note_rounded,
                  label: "Details",
                  color: Colors.teal,
                  onTap: () => _showEditDetailsDialog(user),
                ),
                if (canManageTarget) ...[
                  _buildActionButton(
                    icon: Icons.edit_outlined,
                    label: "Access",
                    color: Colors.blue,
                    onTap: () => _showEditRoleDialog(user),
                  ),

                  _buildActionButton(
                    icon: Icons.password_rounded,
                    label: "Reset Password",
                    color: Colors.orange.shade700,
                    onTap: () => _showResetPasswordDialog(user),
                  ),

                  // 3. Delete Button
                  _buildActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: "Delete",
                    color: isMe ? Colors.grey : Colors.red,
                    onTap: isMe ? null : () => _showDeleteConfirmDialog(user),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // SUPPORTING HELPER: The Action Button Widget
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    bool isDisabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: isDisabled ? 0.4 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
