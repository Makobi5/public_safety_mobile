import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_service.dart'; // Ensure this path is correct

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
  String _searchQuery = "";
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadCurrentRole();
    _fetchUsers();
  }

  // Determine if the current logged-in person is a Super Admin or regular Admin
  Future<void> _loadCurrentRole() async {
    final role = await AuthService().getUserRole();
    if (mounted) {
      setState(() {
        _currentUserRole = role;
      });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching users: $e")));
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;
      _filteredUsers = _users.where((user) {
        final name = "${user['first_name']} ${user['last_name']}".toLowerCase();
        final email = user['email']?.toString().toLowerCase() ?? "";
        return name.contains(query.toLowerCase()) ||
            email.contains(query.toLowerCase());
      }).toList();
    });
  }

  // --- 1. EDIT ROLE DIALOG (Implementation of Screenshot 2) ---
  void _showEditRoleDialog(Map<String, dynamic> targetUser) {
    String selectedRole = targetUser['role'] ?? 'standard_user';

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
              // ONLY show Super Admin option if current logged-in user is a Super Admin
              if (_currentUserRole == 'super_admin')
                RadioListTile<String>(
                  title: const Text("Super Admin (Main OC)"),
                  value: 'super_admin',
                  groupValue: selectedRole,
                  activeColor: const Color(0xFF003366),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
              RadioListTile<String>(
                title: const Text("Admin"),
                value: 'admin',
                groupValue: selectedRole,
                activeColor: const Color(0xFF003366),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              ),
              RadioListTile<String>(
                title: const Text("Standard User"),
                value: 'standard_user',
                groupValue: selectedRole,
                activeColor: const Color(0xFF003366),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              ),
              RadioListTile<String>(
                title: const Text("Field Officer"),
                value: 'field_officer',
                groupValue: selectedRole,
                activeColor: const Color(0xFF003366),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
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
              onPressed: () async {
                try {
                  await supabase
                      .from('user_profiles')
                      .update({'role': selectedRole})
                      .eq('user_id', targetUser['user_id']);
                  if (mounted) Navigator.pop(context);
                  _fetchUsers();
                } catch (e) {
                  debugPrint("Update error: $e");
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
    // Safety check: Prevent Super Admin from deleting themselves
    if (targetUser['user_id'] == supabase.auth.currentUser!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Safety Error: You cannot delete yourself!"),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirm Delete"),
        content: Text(
          "Are you sure you want to delete ${targetUser['first_name']}? This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () async {
              try {
                await supabase
                    .from('user_profiles')
                    .delete()
                    .eq('user_id', targetUser['user_id']);
                if (mounted) Navigator.pop(context);
                _fetchUsers();
              } catch (e) {
                debugPrint("Delete error: $e");
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int adminCount = _users
        .where((u) => u['role'] == 'admin' || u['role'] == 'super_admin')
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
                _buildStatCard("Field Officers", "0", Colors.orange),
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
    final String targetUserId = user['user_id'] ?? "";
    final String currentUserId = supabase.auth.currentUser?.id ?? "";

    // 2. PERMISSION LOGIC (Hierarchy Protection)
    // Check if the person being viewed is a Super Admin
    bool isTargetSuperAdmin = role == 'super_admin';

    // Check if the person currently logged in is NOT a Super Admin
    bool iAmNotSuperAdmin = _currentUserRole != 'super_admin';

    // RULE: Regular Admins cannot modify Super Admins
    bool disableAllActions = isTargetSuperAdmin && iAmNotSuperAdmin;

    // RULE: You cannot delete yourself
    bool isMe = targetUserId == currentUserId;

    // 3. UI STYLING CONSTANTS
    String initials = (fName.isNotEmpty && lName.isNotEmpty)
        ? "${fName[0]}${lName[0]}".toUpperCase()
        : "U";

    Color roleColor;
    String roleLabel;

    switch (role) {
      case 'super_admin':
        roleColor = Colors.purple;
        roleLabel = "Super Admin (OC)";
        break;
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
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 32, thickness: 1),

          // BOTTOM SECTION: Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Edit Role Button
              _buildActionButton(
                icon: Icons.edit_outlined,
                label: "Edit Role",
                color: disableAllActions ? Colors.grey : Colors.blue,
                onTap: disableAllActions
                    ? null
                    : () => _showEditRoleDialog(user),
              ),

              // 2. Reset Password Button (RPC Method)
              _buildActionButton(
                icon: Icons.password_rounded,
                label: "Reset Password",
                color: disableAllActions ? Colors.grey : Colors.orange.shade700,
                onTap: disableAllActions
                    ? null
                    : () => _showResetPasswordDialog(user),
              ),

              // 3. Delete Button
              _buildActionButton(
                icon: Icons.delete_outline_rounded,
                label: "Delete",
                color: (disableAllActions || isMe) ? Colors.grey : Colors.red,
                onTap: (disableAllActions || isMe)
                    ? null
                    : () => _showDeleteConfirmDialog(user),
              ),
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
