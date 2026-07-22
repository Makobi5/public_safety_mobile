import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// ignore: avoid_web_libraries_in_dot_dart
import '../widgets/app_video_player.dart';
import '../widgets/app_audio_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  bool _isDownloading = false;
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

  bool _isVideo(String url) {
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => url.toLowerCase().contains(ext));
  }

  bool _isAudio(String url) {
    final audioExtensions = ['.mp3', '.wav', '.m4a', '.aac', '.ogg'];
    return audioExtensions.any((ext) => url.toLowerCase().contains(ext));
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

  Future<void> _downloadMedia(String url) async {
    setState(() => _isUpdating = true);
    final String fileName = "SafeWatch_Evidence_${url.split('/').last}";

    try {
      if (kIsWeb) {
        // WEB: Trigger browser to open link (most browsers will handle download)
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // MOBILE: Real local download
        // 1. Check Permissions
        if (Platform.isAndroid) {
          await Permission.storage.request();
          await Permission.photos.request(); // For Android 13+
        }

        // 2. Download the data
        final response = await http.get(Uri.parse(url));

        // 3. Get path to "Downloads" or "Documents"
        Directory? directory = Platform.isAndroid
            ? Directory('/storage/emulated/0/Download')
            : await getApplicationDocumentsDirectory();

        if (!await directory.exists())
          directory = await getExternalStorageDirectory();

        // 4. Write to disk
        final File file = File("${directory!.path}/$fileName");
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("File saved to: ${file.path}"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Download error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Download failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Basic null-safety for date parsing
    DateTime date;
    try {
      date = DateTime.parse(
        widget.incident['created_at'] ?? DateTime.now().toIso8601String(),
      );
    } catch (e) {
      date = DateTime.now();
    }

    final List<dynamic> evidence = widget.incident['evidence_urls'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("Admin Case Review"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER CARD (Case Type & Dynamic Status Badge)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0F4F8),
                  child: Icon(Icons.security_rounded, color: Color(0xFF003366)),
                ),
                title: Text(
                  widget.incident['incident_type'] ?? "Incident",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF003366),
                  ),
                ),
                subtitle: Text(
                  "Reported: ${DateFormat('MMM d, yyyy HH:mm').format(date)}",
                ),
                trailing: _buildStatusBadge(_currentStatus),
              ),
            ),
            const SizedBox(height: 20),

            // 2. ACTION & FEEDBACK SECTION
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
                  children: [
                    // Status Dropdown
                    DropdownButtonFormField<String>(
                      value: _currentStatus,
                      decoration: const InputDecoration(
                        labelText: "Update Case Progress",
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
                    const SizedBox(height: 20),
                    // Officer Feedback Field
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Officer Feedback (Public)",
                        hintText: "Enter updates for the reporter...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    // Update Button
                    ElevatedButton(
                      onPressed: _isUpdating ? null : _savePoliceNotes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003366),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isUpdating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Update Feedback & Notify User",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // 3. CASE DESCRIPTION
            const Text(
              "Case Description",
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
              ),
              child: Text(
                widget.incident['description'] ?? "No details provided.",
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 25),

            // 4. EVIDENCE GALLERY (Unified Grid calling _showEvidenceActions)
            const Text(
              "Evidence Gallery",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),
            if (evidence.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "No evidence files attached.",
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
                  final String mediaUrl = evidence[index].toString();
                  final bool isVideoFile = _isVideo(mediaUrl);
                  final bool isAudioFile = _isAudio(mediaUrl);

                  return InkWell(
                    onTap: () => _showEvidenceActions(
                      context,
                      mediaUrl,
                    ), // FIXED: Consolidated method
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFFF0F4F8),
                        child: isAudioFile
                            ? const Icon(
                                Icons.audiotrack_rounded,
                                size: 40,
                                color: Color(0xFF003366),
                              )
                            : isVideoFile
                            ? const Icon(
                                Icons.play_circle_fill,
                                size: 40,
                                color: Color(0xFF003366),
                              )
                            : Image.network(
                                mediaUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) =>
                                    const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(String url) async {
    // Ensure we use the same variable everywhere
    setState(() => _isDownloading = true);
    String fileName = url.split('/').last;

    try {
      if (kIsWeb) {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // MOBILE LOGIC
        if (Platform.isAndroid) {
          await Permission.storage.request();
          await Permission.photos.request();
        }

        final response = await http.get(Uri.parse(url));
        Directory? directory = Platform.isAndroid
            ? Directory('/storage/emulated/0/Download')
            : await getApplicationDocumentsDirectory();

        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }

        final File file = File("${directory!.path}/SafeWatch_$fileName");
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Success: Saved to ${directory.path}"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      // Ensure this matches the start variable
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showEvidenceActions(BuildContext context, String url) {
    final bool isVideoFile = _isVideo(url);
    final bool isAudioFile = _isAudio(url);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          // Use white for audio (so controls are visible), black for media
          backgroundColor: isAudioFile ? Colors.white : Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // 1. THE VIEWER (Audio, Video, or Zoomable Image)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: isAudioFile
                      ? AppAudioPlayer(url: url)
                      : isVideoFile
                      ? AspectRatio(
                          aspectRatio: 16 / 9,
                          child: AppVideoPlayer(url: url),
                        )
                      : InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Image.network(url, fit: BoxFit.contain),
                        ),
                ),
              ),

              // 2. TOP CONTROLS (Close & Download)
              Positioned(
                top: 40,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isAudioFile ? Colors.black : Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isDownloading
                          ? null
                          : () async {
                              setDialogState(() => _isDownloading = true);
                              await _downloadFile(url);
                              setDialogState(() => _isDownloading = false);
                            },
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF003366),
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _isDownloading ? "Saving..." : "Save to Device",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF003366),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
