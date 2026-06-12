import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'incident_report_screen.dart';
import 'welcome_screen.dart';
import 'user_profile_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final supabase = Supabase.instance.client;

  // State variables
  String userName = "Loading...";
  int activeReportsCount = 0;
  List<Map<String, dynamic>> _myIncidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Fetches both User Profile and their specific Incident Reports
  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch Profile Name
      final profileData = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .single();

      // 2. Fetch User's Incidents from the database
      final incidentData = await supabase
          .from('incidents')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          userName = "${profileData['first_name']} ${profileData['last_name']}";
          _myIncidents = List<Map<String, dynamic>>.from(incidentData);

          // Count only non-resolved cases as "Active"
          activeReportsCount = _myIncidents
              .where((i) => i['status'] != 'resolved')
              .length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        elevation: 0,
        title: const Text(
          "PSRA",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Data',
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            tooltip: 'My Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserProfileScreen(),
                ),
              ).then((_) => _loadDashboardData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const WelcomeScreen(),
                  ),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF003366),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome back,",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Your safety is our priority",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Report Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const IncidentReportScreen(),
                  ),
                ).then((_) => _loadDashboardData());
              },
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              label: const Text(
                "Report New Case",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: "Active Reports",
                    count: activeReportsCount.toString(), // Real dynamic count
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: _SummaryCard(
                    title: "Community Alert",
                    count: "Updates",
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "My Reports",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003366),
                ),
              ),
            ),
          ),

          // Scrollable Reports List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _myIncidents.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 50,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "You have no active reports.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: _myIncidents.length,
                    itemBuilder: (context, index) {
                      final incident = _myIncidents[index];

                      // SAFE DATA EXTRACTION
                      final String type =
                          incident['incident_type']?.toString() ?? "Unknown";
                      final String desc =
                          incident['description']?.toString() ??
                          "No description";
                      final String status =
                          incident['status']?.toString() ?? "pending";
                      final String createdAt =
                          incident['created_at']?.toString() ??
                          DateTime.now().toIso8601String();

                      // Safely parse date
                      String formattedDate = "N/A";
                      try {
                        formattedDate = DateFormat(
                          'MMM d, yyyy',
                        ).format(DateTime.parse(createdAt));
                      } catch (e) {
                        formattedDate = "Invalid Date";
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF003366,
                            ).withOpacity(0.1),
                            child: const Icon(
                              Icons.description,
                              color: Color(0xFF003366),
                            ),
                          ),
                          title: Text(
                            type,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Reported: $formattedDate",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(status),
                              ),
                            ),
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Resolved':
        return Colors.green;
      case 'Under Investigation':
      case 'Filed':
        return Colors.blue;
      case 'Action Taken':
        return Colors.purple;
      case 'Requires Follow-up':
        return Colors.red;
      case 'Closed':
        return Colors.grey;
      case 'Pending':
      default:
        return Colors.orange;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String count;
  final Color color;
  const _SummaryCard({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              // Show a circle badge only if it is a number
              if (int.tryParse(count) != null)
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    count,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            int.tryParse(count) != null
                ? "View all ongoing cases"
                : "Updates for your district",
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
