import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
    _notesController.text = widget.incident['police_notes'] ?? "";
    // 1. Get the raw status from the database
    String rawStatus = widget.incident['status'] ?? 'Pending';

    // 2. Find the version in our list that matches (ignoring case)
    // This prevents the crash if the DB has 'pending' but our list has 'Pending'
    _currentStatus = _statusOptions.firstWhere(
      (option) => option.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => 'Pending', // Fallback if no match found
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);

    try {
      // 1. Attempt to update the database
      final response = await supabase
          .from('incidents')
          .update({'status': newStatus})
          .eq('id', widget.incident['id'])
          .select(); // Requesting data back to verify success

      if (response.isEmpty) {
        throw "Update failed: No rows affected. Check RLS policies.";
      }

      // 2. If successful, update the local UI state
      setState(() {
        _currentStatus = newStatus;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Success: Status updated to $newStatus"),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("DATABASE UPDATE ERROR: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: Permission denied or connection lost."),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Revert the dropdown value if it failed
      setState(() {
        _currentStatus = widget.incident['status'];
      });
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _savePoliceNotes() async {
    try {
      await supabase
          .from('incidents')
          .update({'police_notes': _notesController.text.trim()})
          .eq('id', widget.incident['id']);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notes saved and sent to reporter")),
      );
    } catch (e) {
      print("Error saving notes: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.incident['created_at']);
    final List<dynamic> evidence = widget.incident['evidence_urls'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("Case Details"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER CARD (Type & Status)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF003366).withOpacity(0.1),
                      child: const Icon(
                        Icons.report_gmailerrorred_rounded,
                        color: Color(0xFF003366),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.incident['incident_type'] ?? "Other",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Reported: ${DateFormat('MMM d, yyyy HH:mm').format(date)}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(_currentStatus),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. STATUS CONTROL CARD
            const Text(
              "Actions / Feedback",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Update Progress",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _currentStatus,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
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
                    if (_isUpdating)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(
                          color: Color(0xFF003366),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // 3. DESCRIPTION
            const Text(
              "Description",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Text(
                widget.incident['description'] ?? "No details provided.",
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),

            const SizedBox(height: 25),
            // Police Notes section
            const Text(
              "Officer's Feedback (Visible to User)",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Enter instructions or updates for the citizen...",
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _savePoliceNotes,
              child: const Text("Save Feedback"),
            ),
            // 4. EVIDENCE GALLERY (With Step 4: Zoom Functionality)
            const Text(
              "Evidence Attached",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),
            if (evidence.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    "No files attached.",
                    style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: evidence.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      // FULL SCREEN VIEWER DIALOG
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.black.withOpacity(0.9),
                          insetPadding: EdgeInsets.zero,
                          child: Stack(
                            children: [
                              // InteractiveViewer allows pinch-to-zoom on Mobile
                              Center(
                                child: InteractiveViewer(
                                  panEnabled: true,
                                  minScale: 0.5,
                                  maxScale: 4,
                                  child: Image.network(
                                    evidence[index],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 40,
                                right: 20,
                                child: CircleAvatar(
                                  backgroundColor: Colors.white24,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Hero(
                        // Smooth transition animation
                        tag: evidence[index],
                        child: Image.network(
                          evidence[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 120), // Extra space for the bottom area
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;

    switch (status) {
      case 'Resolved':
        color = Colors.green;
        break;
      case 'Under Investigation':
      case 'Filed':
        color = Colors.blue;
        break;
      case 'Action Taken':
        color = Colors.purple;
        break;
      case 'Requires Follow-up':
        color = Colors.red;
        break;
      case 'Closed':
        color = Colors.grey;
        break;
      case 'Pending':
      default:
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
