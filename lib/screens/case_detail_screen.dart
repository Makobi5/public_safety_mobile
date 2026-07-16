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
import 'dart:html' as html; // For web downloads
import '../widgets/app_video_player.dart';
import '../widgets/app_audio_player.dart';

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
                  final String mediaUrl = evidence[index].toString();
                  final bool isVideoFile = _isVideo(mediaUrl);
                  final bool isAudioFile = _isAudio(mediaUrl);

                  return InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: isAudioFile
                              ? Colors.white
                              : Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAudioFile)
                                  AppAudioPlayer(url: mediaUrl)
                                else if (isVideoFile)
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: AppVideoPlayer(url: mediaUrl),
                                  )
                                else
                                  InteractiveViewer(
                                    child: Image.network(mediaUrl),
                                  ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Close"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.grey.shade100,
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
                            : Image.network(mediaUrl, fit: BoxFit.cover),
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

  Future<void> _downloadFile(String url, String originalFileName) async {
    setState(() => _isUpdating = true); // Use your existing loading state

    try {
      if (kIsWeb) {
        // --- WEB DOWNLOAD LOGIC ---
        final response = await http.get(Uri.parse(url));
        final blob = html.Blob([response.bodyBytes]);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute("download", originalFileName)
          ..click();
        html.Url.revokeObjectUrl(blobUrl);
      } else {
        // --- MOBILE DOWNLOAD LOGIC ---
        // 1. Request Permission
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          // For Android 13+, storage permission is slightly different, check media permissions
          await Permission.photos.request();
        }

        // 2. Download bytes
        final response = await http.get(Uri.parse(url));

        // 3. Get directory to save (Downloads folder on Android)
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final String fileName =
            "SafeWatch_Evidence_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final File file = File("${directory!.path}/$fileName");

        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("File saved to: ${file.path}"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Download Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to download file"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showEvidenceActions(BuildContext context, String url) {
    // Extract a name from the URL or use a timestamp
    String fileName = url.split('/').last;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(url),
              ),
            ),
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
                    onPressed: _isUpdating
                        ? null
                        : () {
                            Navigator.pop(context);
                            _downloadFile(url, fileName);
                          },
                    icon: _isUpdating
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text("Download to Device"),
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
