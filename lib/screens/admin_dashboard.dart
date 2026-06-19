import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/auth_service.dart';
import 'welcome_screen.dart';
import 'user_management_screen.dart';
import 'add_admin_screen.dart';
import 'case_detail_screen.dart';
import 'all_reports_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;

  String _adminName = "Loading...";
  String _adminRole = "Admin";
  int _totalIncidentsCount = 0;
  int _activeCases = 0;
  int _criticalCases = 0;
  int _newReportsToday = 0;
  String _responseRate = "0%";
  String _emergencyLevel = "Low";

  List<Map<String, dynamic>> _recentIncidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllDashboardData();
  }

  // --- NAVIGATION HELPER ---
  void _navigateToFilteredReports(String filter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllReportsScreen(initialFilter: filter),
      ),
    ).then((_) => _loadAllDashboardData());
  }

  Future<void> _loadAllDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profileData = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .single();

      final incidentData = await supabase
          .from('incidents')
          .select()
          .order('created_at', ascending: false);
      final List<Map<String, dynamic>> allIncidents =
          List<Map<String, dynamic>>.from(incidentData);

      final today = DateTime.now().toIso8601String().substring(0, 10);

      if (mounted) {
        setState(() {
          _adminName =
              "${profileData['first_name'] ?? 'Admin'} ${profileData['last_name'] ?? ''}";
          _adminRole = profileData['role'] == 'super_admin'
              ? "Super Admin"
              : "Station Admin";
          _totalIncidentsCount = allIncidents.length;
          _recentIncidents = allIncidents.take(5).toList();
          _activeCases = allIncidents
              .where((i) => i['status'] != 'Resolved')
              .length;
          _criticalCases = allIncidents
              .where(
                (i) => [
                  'Accident',
                  'Murder',
                  'Fire outbreak',
                  'Robbery',
                  'Kidnap',
                  'Manslaughter',
                ].contains(i['incident_type']),
              )
              .length;
          _newReportsToday = allIncidents
              .where(
                (i) => (i['created_at'] ?? '').toString().startsWith(today),
              )
              .length;

          if (allIncidents.isNotEmpty) {
            int responded = allIncidents
                .where(
                  (i) => (i['status'] ?? 'Pending').toLowerCase() != 'pending',
                )
                .length;
            _responseRate =
                "${((responded / allIncidents.length) * 100).toInt()}%";
          }
          _emergencyLevel = _criticalCases > 3
              ? "High"
              : _criticalCases > 0
              ? "Medium"
              : "Low";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Admin Dashboard Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Admin Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllDashboardData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF003366)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEmergencyBanner(),
                  const SizedBox(height: 24),
                  const Text(
                    "Public Safety Control Center",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003366),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- UPDATED STAT GRID ---
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    childAspectRatio: 1.4,
                    children: [
                      _AdminStatCard(
                        label: "Active Cases",
                        value: _activeCases.toString(),
                        color: const Color(0xFF003366),
                        onTap: () =>
                            _navigateToFilteredReports('active'), // Added
                      ),
                      _AdminStatCard(
                        label: "Critical Cases",
                        value: _criticalCases.toString(),
                        color: Colors.red,
                        onTap: () =>
                            _navigateToFilteredReports('critical'), // Added
                      ),
                      _AdminStatCard(
                        label: "New Reports Today",
                        value: _newReportsToday.toString(),
                        color: const Color(0xFF003366),
                        onTap: () =>
                            _navigateToFilteredReports('today'), // Added
                      ),
                      _AdminStatCard(
                        label: "Response Rate",
                        value: _responseRate,
                        color: Colors.teal,
                        onTap: () =>
                            _navigateToFilteredReports('responded'), // Added
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recent Reports Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Recent Reports",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF003366),
                        ),
                      ),
                      if (_totalIncidentsCount > 5)
                        Text(
                          "Showing 5 of $_totalIncidentsCount",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_recentIncidents.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Text(
                          "No incidents reported yet.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ..._recentIncidents
                            .map(
                              (incident) => _buildRecentIncidentItem(incident),
                            )
                            .toList(),
                        if (_totalIncidentsCount > 5)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 8.0,
                              bottom: 10.0,
                            ),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AllReportsScreen(),
                                  ),
                                ).then((_) => _loadAllDashboardData()),
                                icon: const Icon(
                                  Icons.list_alt_rounded,
                                  color: Color(0xFF003366),
                                  size: 20,
                                ),
                                label: const Text(
                                  "VIEW ALL REPORTS",
                                  style: TextStyle(
                                    color: Color(0xFF003366),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  _buildMapPlaceholder(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: _buildFABs(context),
    );
  }

  // Sub-widgets
  Widget _buildEmergencyBanner() {
    Color bannerColor = _emergencyLevel == "High"
        ? Colors.red.shade800
        : _emergencyLevel == "Medium"
        ? Colors.orange.shade800
        : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            "Emergency Level: $_emergencyLevel",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: bannerColor,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              "QUICK ALERT",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentIncidentItem(Map<String, dynamic> incident) {
    final DateTime date = DateTime.parse(
      incident['created_at'] ?? DateTime.now().toIso8601String(),
    );

    // 1. Get raw priority from DB
    String dbPriority = (incident['priority'] ?? 'Low').toString();
    String type = (incident['incident_type'] ?? 'Other').toString();

    // 2. SMART LOGIC: Ensure serious types always show as Critical
    bool isUrgentType = [
      'Murder',
      'Accident',
      'Fire outbreak',
      'Kidnap',
      'Manslaughter',
      'Robbery',
    ].contains(type);

    String displayPriority = isUrgentType ? 'Critical' : dbPriority;

    // Define priority colors
    Color priorityColor = Colors.grey;
    if (displayPriority == 'Critical') priorityColor = Colors.red.shade900;
    if (displayPriority == 'High') priorityColor = Colors.red;
    if (displayPriority == 'Medium') priorityColor = Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CaseDetailScreen(incident: incident),
            ),
          ).then((_) => _loadAllDashboardData());
        },
        // The colored stripe on the left
        leading: Container(
          width: 5,
          height: 40,
          decoration: BoxDecoration(
            color: priorityColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Row(
          children: [
            Text(type, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),

            // --- THE CRITICAL BADGE (FIXED) ---
            if (displayPriority != 'Low')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: priorityColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayPriority.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          "Reported at ${DateFormat('HH:mm').format(date)} • ${incident['village'] ?? 'Unknown Location'}",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: const Column(
        children: [
          Text(
            "District Activity Map",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 40),
          Icon(Icons.map_outlined, size: 60, color: Colors.grey),
          Text(
            "Interactive District Map",
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildFABs(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: "u_m",
          backgroundColor: Colors.blue,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UserManagementScreen(),
            ),
          ).then((_) => _loadAllDashboardData()),
          child: const Icon(Icons.people, color: Colors.white),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: "a_a",
          backgroundColor: const Color(0xFF003366),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddAdminScreen()),
          ).then((_) => _loadAllDashboardData()),
          child: const Icon(Icons.person_add, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 60,
              left: 20,
              right: 20,
              bottom: 25,
            ),
            color: const Color(0xFF003366),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Safety Control Center",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Welcome, $_adminName",
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _adminRole.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.dashboard_rounded,
                  label: "Dashboard",
                  isSelected: true,
                  onTap: () => Navigator.pop(context),
                ),
                _buildDrawerItem(
                  icon: Icons.people_alt_rounded,
                  label: "User Management",
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserManagementScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.analytics_rounded,
                  label: "Reports & Analytics",
                  onTap: () {},
                ),
                _buildDrawerItem(
                  icon: Icons.map_rounded,
                  label: "District Mapping",
                  onTap: () {},
                ),
                const Divider(indent: 20, endIndent: 20),
                _buildDrawerItem(
                  icon: Icons.settings_rounded,
                  label: "Settings",
                  onTap: () {},
                ),
                _buildDrawerItem(
                  icon: Icons.help_outline_rounded,
                  label: "Help & Support",
                  onTap: () {},
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildDrawerItem(
            icon: Icons.logout_rounded,
            label: "Logout",
            color: Colors.red,
            onTap: () => _handleLogout(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool isSelected = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: color ?? (isSelected ? const Color(0xFF003366) : Colors.black87),
      ),
      title: Text(
        label,
        style: TextStyle(
          color:
              color ?? (isSelected ? const Color(0xFF003366) : Colors.black87),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFFE3F2FD),
      onTap: onTap,
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _AdminStatCard({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
