import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'edit_profile_screen.dart';
import 'welcome_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() => _isLoading = true);
    final user = supabase.auth.currentUser;
    if (user != null) {
      final data = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .single();
      setState(() {
        userData = data;
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return "N/A";
    DateTime date = DateTime.parse(dateStr);
    return DateFormat('d/M/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final userAuth = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("User Profile"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Blue Header Area
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    color: const Color(0xFF003366),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            "${userData!['first_name'][0]}${userData!['last_name'][0]}"
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 32,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "${userData!['first_name']} ${userData!['last_name']}",
                          style: const TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          userData!['email'],
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle("Personal Information"),
                        _buildInfoRow("First Name", userData!['first_name']),
                        _buildInfoRow("Last Name", userData!['last_name']),
                        _buildInfoRow("Email", userData!['email']),

                        const SizedBox(height: 25),
                        _buildSectionTitle("Location Details"),
                        _buildInfoRow("Region", userData!['region']),
                        _buildInfoRow("District", userData!['district']),
                        _buildInfoRow(
                          "Village",
                          userData!['village_area'] ?? "Unknown",
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle("Account Information"),
                        _buildInfoRow(
                          "User ID",
                          userAuth?.id.substring(0, 15) ?? "...",
                        ),
                        _buildInfoRow(
                          "Created At",
                          _formatDate(userData!['created_at']),
                        ),
                        _buildInfoRow(
                          "Last Sign In",
                          _formatDate(userAuth?.lastSignInAt.toString()),
                        ),

                        const SizedBox(height: 40),

                        // Action Buttons
                        ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditProfileScreen(userData: userData!),
                            ),
                          ).then((_) => _fetchUserData()),
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: const Text(
                            "Edit Profile",
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003366),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await supabase.auth.signOut();
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const WelcomeScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.logout, color: Colors.red),
                          label: const Text(
                            "Sign Out",
                            style: TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF003366),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
