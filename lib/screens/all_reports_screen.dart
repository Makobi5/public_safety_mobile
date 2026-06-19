import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'case_detail_screen.dart';

class AllReportsScreen extends StatefulWidget {
  final String? initialFilter; // Added
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
      final List<Map<String, dynamic>> allList =
          List<Map<String, dynamic>>.from(data);

      if (mounted) {
        setState(() {
          _allReports = allList;

          // --- APPLY INITIAL FILTER FROM DASHBOARD ---
          if (widget.initialFilter != null) {
            if (widget.initialFilter == 'active') {
              _filteredReports = allList
                  .where((i) => i['status'] != 'Resolved')
                  .toList();
            } else if (widget.initialFilter == 'critical') {
              _filteredReports = allList
                  .where(
                    (i) => [
                      'Murder',
                      'Manslaughter',
                      'Accident',
                      'Fire outbreak',
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
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      _filteredReports = _allReports.where((item) {
        final type = (item['incident_type'] ?? '').toLowerCase();
        final village = (item['village'] ?? '').toLowerCase();
        return type.contains(query.toLowerCase()) ||
            village.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Text(
          widget.initialFilter != null
              ? "${widget.initialFilter!.toUpperCase()} Reports"
              : "All Incident Reports",
          style: const TextStyle(fontWeight: FontWeight.bold),
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
                hintText: "Search reports...",
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
                : _filteredReports.isEmpty
                ? const Center(child: Text("No matching reports found."))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredReports.length,
                    itemBuilder: (context, index) {
                      return _buildReportCard(_filteredReports[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> incident) {
    final DateTime date = DateTime.parse(incident['created_at']);
    String type = incident['incident_type'] ?? "Other";
    bool isUrgent = ['Murder', 'Accident', 'Fire outbreak'].contains(type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CaseDetailScreen(incident: incident),
          ),
        ).then((_) => _fetchReports()),
        leading: Container(
          width: 4,
          height: 40,
          color: isUrgent ? Colors.red : Colors.blue,
        ),
        title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          "${DateFormat('MMM d, HH:mm').format(date)} • ${incident['village'] ?? 'Unknown'}",
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
