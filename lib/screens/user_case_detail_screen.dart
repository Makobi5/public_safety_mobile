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

  // --- LOGIC: SECURE DOWNLOAD (WEB & MOBILE) ---
  Future<void> _downloadFile(String url) async {
    setState(() => _isDownloading = true);
    String fileName = url.split('/').last;

    try {
      if (kIsWeb) {
        // WEB LOGIC: Safe for the mobile compiler
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // MOBILE LOGIC: Android/iOS
        if (Platform.isAndroid) {
          await Permission.storage.request();
          await Permission.photos.request();
        }

        final response = await http.get(Uri.parse(url));
        Directory? directory = Platform.isAndroid
            ? Directory('/storage/emulated/0/Download')
            : await getApplicationDocumentsDirectory();

        if (!await directory.exists())
          directory = await getExternalStorageDirectory();

        final File file = File("${directory!.path}/SafeWatch_$fileName");
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Saved to Downloads: ${file.path}"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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
            // Status Info Card
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
                          "Status: ${widget.incident['status']?.toUpperCase() ?? 'PENDING'}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003366),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Your report is currently being processed by the system.",
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
                    "Waiting for official feedback. Please stay safe.",
                style: TextStyle(
                  color: widget.incident['police_notes'] == null
                      ? Colors.grey
                      : Colors.black87,
                ),
              ),
            ),

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              "Report Type: ${widget.incident['incident_type']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Filed on: ${DateFormat('MMM d, yyyy HH:mm').format(date)}"),
            const SizedBox(height: 15),
            Text(widget.incident['description'] ?? ""),

            const SizedBox(height: 30),

            // EVIDENCE LIST
            if (evidence.isNotEmpty) ...[
              const Text(
                "Evidence Submitted",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  itemBuilder: (context, index) {
                    final url = evidence[index].toString();
                    final bool isVideoFile = _isVideo(url);
                    final bool isAudioFile = _isAudio(url);

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () => _showUserZoomView(context, url),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 120,
                                height: 110,
                                color: const Color(0xFFF0F4F8),
                                // --- SMART UI BASED ON FILE TYPE ---
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
                                        url,
                                        width: 120,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAudioFile
                                  ? "Play Audio"
                                  : isVideoFile
                                  ? "Play Video"
                                  : "View Photo",
                              style: const TextStyle(
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
    final bool isVideoFile = _isVideo(url);
    final bool isAudioFile = _isAudio(url);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        // Use white for audio (so buttons are visible), black for others
        backgroundColor: isAudioFile ? Colors.white : Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: isAudioFile
                    ? AppAudioPlayer(url: url) // Show Audio Player
                    : isVideoFile
                    ? AspectRatio(
                        aspectRatio: 16 / 9,
                        child: AppVideoPlayer(url: url), // Show Video Player
                      )
                    : InteractiveViewer(
                        child: Image.network(url),
                      ), // Show Image
              ),
            ),
            // Close Button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: isAudioFile ? Colors.black : Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
