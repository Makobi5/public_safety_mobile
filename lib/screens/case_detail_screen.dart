import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CaseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  const CaseDetailScreen({super.key, required this.incident});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  final supabase = Supabase.instance.client;
  late String _currentStatus;
  bool _isUpdating = false;
  final _notesController = TextEditingController();

  final List<String> _statusOptions = [
    'Pending',
    'Filed',
    'Under Investigation',
    'Action Taken',
    'Resolved',
    'Closed',
    'Requires Follow-up',
  ];

  @override
  void initState() {
    super.initState();
    // 1. Pre-fill the notes from database
    _notesController.text = widget.incident['police_notes'] ?? "";

    // 2. Safe Status Initialization
    String rawStatus = widget.incident['status'] ?? 'Pending';
    _currentStatus = _statusOptions.firstWhere(
      (option) => option.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => 'Pending',
    );

    // 3. Mark as read for Admin (Optional: if you have admin-read tracking)
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      await supabase
          .from('incidents')
          .update({
            'status': newStatus,
            'user_read': false, // Alert the user that something changed
          })
          .eq('id', widget.incident['id']);

      setState(() => _currentStatus = newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Status updated to $newStatus"),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Update failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _savePoliceNotes() async {
    setState(() => _isUpdating = true);
    try {
      await supabase
          .from('incidents')
          .update({
            'police_notes': _notesController.text.trim(),
            'user_read':
                false, // Mark as unread for user so they see the red dot
          })
          .eq('id', widget.incident['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Feedback saved successfully!"),
            backgroundColor: Color(0xFF003366),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.incident['created_at']);
    final List<dynamic> evidence = widget.incident['evidence_urls'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("Admin Case Review"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0F4F8),
                  child: Icon(Icons.security, color: Color(0xFF003366)),
                ),
                title: Text(
                  widget.incident['incident_type'] ?? "Incident",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  "Reported: ${DateFormat('MMM d, yyyy HH:mm').format(date)}",
                ),
                trailing: _buildStatusBadge(_currentStatus),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Action Section
            const Text(
              "Actions / Feedback",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _currentStatus,
                      decoration: const InputDecoration(
                        labelText: "Update Progress",
                        border: OutlineInputBorder(),
                      ),
                      items: _statusOptions
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isUpdating
                          ? null
                          : (val) => _updateStatus(val!),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Officer Feedback",
                        hintText: "Write a message to the reporter...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      onPressed: _isUpdating ? null : _savePoliceNotes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003366),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: _isUpdating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Update Feedback & Notify User",
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Description & Evidence (using InteractiveViewer for zoom)
            const Text(
              "Case Description",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.incident['description'] ?? "No description",
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 25),
            const Text(
              "Evidence Gallery",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (evidence.isEmpty)
              const Text("No evidence attached.")
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: evidence.length,
                itemBuilder: (context, index) {
                  final imageUrl = evidence[index].toString();
                  return InkWell(
                    onTap: () => _showEvidenceActions(context, imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(imageUrl, fit: BoxFit.cover),
                          // Tiny download indicator on thumbnail
                          Positioned(
                            right: 5,
                            bottom: 5,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.download,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEvidenceActions(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                // Allows Admin to pinch and zoom
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(url),
              ),
            ),
            // Top Bar with Close and Download
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (await canLaunchUrl(Uri.parse(url))) {
                        await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text("Download"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
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

  void _showFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
