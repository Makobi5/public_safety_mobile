import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class UserCaseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  const UserCaseDetailScreen({super.key, required this.incident});

  @override
  State<UserCaseDetailScreen> createState() => _UserCaseDetailScreenState();
}

class _UserCaseDetailScreenState extends State<UserCaseDetailScreen> {
  @override
  void initState() {
    super.initState();
    _markAsRead(); // Step 5: Mark as read immediately when user opens it
  }

  Future<void> _markAsRead() async {
    try {
      final response = await Supabase.instance.client
          .from('incidents')
          .update({'user_read': true})
          .eq('id', widget.incident['id'])
          .select(); // This 'select' confirms if the row was actually updated

      if (response.isNotEmpty) {
        debugPrint(
          "✅ Database updated: Case ${widget.incident['id']} is now READ",
        );
      } else {
        debugPrint(
          "❌ Database update failed: No rows were changed. Check RLS policies!",
        );
      }
    } catch (e) {
      debugPrint("Log error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.incident['created_at']);
    final List<dynamic> evidence = widget.incident['evidence_urls'] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Progress"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Timeline Card
            Card(
              elevation: 0,
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF003366),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Current Status: ${widget.incident['status']?.toUpperCase() ?? 'PENDING'}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003366),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Your report is being reviewed by the local police unit.",
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            const Text(
              "Officer's Response",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade100, width: 2),
              ),
              child: Text(
                widget.incident['police_notes'] ??
                    "No message from the police yet. Please stay safe.",
                style: TextStyle(
                  color: widget.incident['police_notes'] == null
                      ? Colors.grey
                      : Colors.black87,
                ),
              ),
            ),

            const SizedBox(height: 30),
            const Divider(),
            Text(
              "Reported Type: ${widget.incident['incident_type']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Date: ${DateFormat('MMM d, yyyy').format(date)}"),
            const SizedBox(height: 15),
            Text(widget.incident['description'] ?? ""),
            const SizedBox(height: 30),

            if (evidence.isNotEmpty) ...[
              const Text(
                "Evidence Submitted",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        evidence[index],
                        width: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
