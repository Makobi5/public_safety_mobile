import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'case_detail_screen.dart';

class AllReportsScreen extends StatefulWidget {
  final String? initialFilter; // Add this
  const AllReportsScreen({super.key, this.initialFilter});

  @override
  State<AllReportsScreen> createState() => _AllReportsScreenState();
}

class _AllReportsScreenState extends State<AllReportsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allReports = [];
  List<Map<String, dynamic>> _filteredReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('incidents')
          .select()
          .order('created_at', ascending: false);
      final allList = List<Map<String, dynamic>>.from(data);

      setState(() {
        _allReports = allList;

        // APPLY INITIAL FILTER
        if (widget.initialFilter != null) {
          if (widget.initialFilter == 'active') {
            _filteredReports = allList
                .where((i) => i['status'] != 'Resolved')
                .toList();
          } else if (widget.initialFilter == 'critical') {
            _filteredReports = allList
                .where(
                  (i) =>
                      ['Critical', 'High'].contains(i['priority']) ||
                      [
                        'Murder',
                        'Manslaughter',
                        'Accident',
                      ].contains(i['incident_type']),
                )
                .toList();
          } else if (widget.initialFilter == 'today') {
            final today = DateTime.now().toIso8601String().substring(0, 10);
            _filteredReports = allList
                .where((i) => i['created_at'].toString().startsWith(today))
                .toList();
          } else if (widget.initialFilter == 'responded') {
            _filteredReports = allList
                .where((i) => i['status'] != 'Pending')
                .toList();
          }
        } else {
          _filteredReports = allList;
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      _filteredReports = _allReports.where((item) {
        final type = (item['incident_type'] ?? '').toLowerCase();
        final desc = (item['description'] ?? '').toLowerCase();
        final village = (item['village'] ?? '').toLowerCase();
        return type.contains(query.toLowerCase()) ||
            desc.contains(query.toLowerCase()) ||
            village.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text(
          "All Incident Reports",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: "Search by type, description, or village...",
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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredReports.length,
                    itemBuilder: (context, index) {
                      final incident = _filteredReports[index];
                      return _buildReportCard(incident);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> incident) {
    final DateTime date = DateTime.parse(incident['created_at']);
    final String priority = incident['priority'] ?? 'Low';

    Color priorityColor = Colors.grey;
    if (priority == 'Critical') priorityColor = Colors.red.shade900;
    if (priority == 'High') priorityColor = Colors.red;
    if (priority == 'Medium') priorityColor = Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CaseDetailScreen(incident: incident),
            ),
          ).then((_) => _fetchReports());
        },
        leading: Container(width: 4, height: 40, color: priorityColor),
        title: Text(
          incident['incident_type'] ?? "Other",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${DateFormat('MMM d, yyyy HH:mm').format(date)} • ${incident['village'] ?? 'Unknown'}",
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            (incident['status'] ?? 'pending').toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
  }
}
