import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/app_video_player.dart';
// ignore: avoid_web_libraries_in_dot_dart
import '../widgets/app_audio_player.dart';
import 'package:url_launcher/url_launcher.dart';

class UserCaseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  const UserCaseDetailScreen({super.key, required this.incident});

  @override
  State<UserCaseDetailScreen> createState() => _UserCaseDetailScreenState();
}

class _UserCaseDetailScreenState extends State<UserCaseDetailScreen> {
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  // --- LOGIC: MARK AS READ ---
  Future<void> _markAsRead() async {
    try {
      await Supabase.instance.client
          .from('incidents')
          .update({'user_read': true})
          .eq('id', widget.incident['id']);
      debugPrint("Notification cleared for user.");
    } catch (e) {
      debugPrint("Mark as read error: $e");
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

  Future<void> _downloadFile(String url) async {
    setState(() => _isDownloading = true);
    String fileName = url.split('/').last;
    try {
      if (kIsWeb) {
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      } else {
        if (Platform.isAndroid)
          await [Permission.storage, Permission.photos].request();
        final response = await http.get(Uri.parse(url));
        Directory? dir = Platform.isAndroid
            ? Directory('/storage/emulated/0/Download')
            : await getApplicationDocumentsDirectory();
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
        final File file = File("${dir!.path}/SafeWatch_$fileName");
        await file.writeAsBytes(response.bodyBytes);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Saved to Downloads: ${file.path}"),
              backgroundColor: Colors.green,
            ),
          );
      }
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Safely parse date and data
    final DateTime date = DateTime.parse(
      widget.incident['created_at'] ?? DateTime.now().toIso8601String(),
    );
    final List<dynamic> evidence = widget.incident['evidence_urls'] ?? [];
    final String status = widget.incident['status'] ?? 'PENDING';

    return Scaffold(
      backgroundColor: const Color(
        0xFFF4F7F9,
      ), // Light professional grey background
      appBar: AppBar(
        title: const Text("Report Progress"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Status Info Card (Using the improved header style)
            _buildStatusHeader(status),

            const SizedBox(height: 30),
            const Text(
              "Officer's Official Response",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 10),

            // 2. Response Box (Matching the requested styling)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Text(
                widget.incident['police_notes'] ??
                    "No message from the police yet. Your case is currently under review.",
                style: TextStyle(
                  color: widget.incident['police_notes'] == null
                      ? Colors.grey
                      : Colors.black87,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),

            // 3. Original Report Details
            Text(
              "Report Category: ${widget.incident['incident_type']}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              "Filed on: ${DateFormat('MMM d, yyyy HH:mm').format(date)}",
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 15),
            Text(
              widget.incident['description'] ?? "",
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),

            const SizedBox(height: 40),

            // 4. EVIDENCE LIST (Smart Thumbnails for Audio/Video/Image)
            if (evidence.isNotEmpty) ...[
              const Text(
                "Evidence Submitted",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF003366),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  itemBuilder: (context, index) {
                    final String url = evidence[index].toString();
                    return _buildMediaThumbnail(url);
                  },
                ),
              ),
            ],
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildStatusHeader(String status) {
    return Card(
      elevation: 0,
      color: const Color(0xFFE3F2FD), // Soft blue
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF003366)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CURRENT STATUS: ${status.toUpperCase()}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003366),
                    ),
                  ),
                  const Text(
                    "Check back later for instructions from the OC.",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaThumbnail(String url) {
    final bool isVideo = _isVideo(url);
    final bool isAudio = _isAudio(url);

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: InkWell(
        onTap: () => _showMediaDialog(url), // Unified Dialog call
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 130,
                height: 110,
                color: const Color(0xFFE9EEF2),
                child: isAudio
                    ? const Icon(
                        Icons.audiotrack_rounded,
                        size: 40,
                        color: Color(0xFF003366),
                      )
                    : isVideo
                    ? const Icon(
                        Icons.play_circle_fill,
                        size: 40,
                        color: Color(0xFF003366),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const Icon(Icons.broken_image, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAudio
                  ? "Play Audio"
                  : isVideo
                  ? "Play Video"
                  : "View Photo",
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaDialog(String url) {
    final bool isVideo = _isVideo(url);
    final bool isAudio = _isAudio(url);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: isAudio ? Colors.white : Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // 1. THE CONTENT VIEWER
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: isAudio
                      ? AppAudioPlayer(url: url)
                      : isVideo
                      ? AspectRatio(
                          aspectRatio: 16 / 9,
                          child: AppVideoPlayer(url: url),
                        )
                      : InteractiveViewer(child: Image.network(url)),
                ),
              ),

              // 2. TOP ACTIONS
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
                        color: isAudio ? Colors.black : Colors.white,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isDownloading ? "Saving..." : "Save"),
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
}
