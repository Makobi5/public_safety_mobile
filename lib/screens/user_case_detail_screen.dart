import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150, // Slightly taller for better visibility
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  itemBuilder: (context, index) {
                    final url = evidence[index].toString();
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () =>
                            _showUserZoomView(context, url), // Call zoom view
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                width: 120,
                                height: 110,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Tap to view/save",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showUserZoomView(BuildContext context, String url) {
    // We reuse the same logic as Admin for consistency
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(
              bottom: 40,
              left: 40,
              right: 40,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri))
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.download),
                label: const Text("Download Evidence"),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
