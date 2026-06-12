import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  int _currentStep = 1;
  final _formKey = GlobalKey<FormState>();

  // --- Data for Step 1 ---
  String? _selectedIncidentType;
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // --- Data for Step 2 ---
  Position? _capturedPosition;
  bool _isLocating = false;
  final _additionalLocationController = TextEditingController();
  final _landmarkController = TextEditingController();

  // --- Data for Step 3 ---
  List<PlatformFile> _selectedFiles = [];
  final _witnessInfoController = TextEditingController();
  final _additionalNotesController = TextEditingController();
  bool _isLoading = false;

  final List<String> _crimeTypes = [
    'Robbery',
    'Theft',
    'Rape',
    'Defilement',
    'Sexual Assault',
    'Domestic Violence',
    'Murder',
    'Manslaughter',
    'Drug Abuse',
    'Kidnap',
    'Child Labour',
    'Cyber Crime',
    'Fraud and financial crimes',
    'Accident',
    'Fire outbreak',
    'Other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _additionalLocationController.dispose();
    _landmarkController.dispose();
    _witnessInfoController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  // --- Logic Helpers ---

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _captureLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition();
      setState(() => _capturedPosition = position);
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );
    if (result != null) {
      setState(() => _selectedFiles = result.files);
    }
  }

  Future<void> _submitReport() async {
    // 1. Validation Check
    if (_selectedIncidentType == null || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please provide incident type and description"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      List<String> uploadedUrls = [];

      // 2. UPLOAD FILES TO STORAGE
      for (var file in _selectedFiles) {
        final String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final String path = 'evidence/${user.id}/$fileName';

        if (kIsWeb) {
          // Web uses bytes
          await supabase.storage
              .from('incident-evidence')
              .uploadBinary(
                path,
                file.bytes!,
                fileOptions: FileOptions(
                  contentType: file.extension != null
                      ? 'image/${file.extension}'
                      : 'image/jpeg',
                ),
              );
        } else {
          // Mobile uses file path
          await supabase.storage
              .from('incident-evidence')
              .upload(path, File(file.path!));
        }

        // Get the Public URL for the admin to view later
        final String publicUrl = supabase.storage
            .from('incident-evidence')
            .getPublicUrl(path);
        uploadedUrls.add(publicUrl);
      }

      // 3. SAVE DATA TO 'incidents' TABLE
      await supabase.from('incidents').insert({
        'user_id': user.id,
        'incident_type': _selectedIncidentType,
        'description': _descriptionController.text.trim(),
        'incident_date': _selectedDate?.toIso8601String(),
        'incident_time': _selectedTime?.format(context),
        'latitude': _capturedPosition?.latitude,
        'longitude': _capturedPosition?.longitude.toString(),
        'location_address':
            'GPS Captured', // We will improve this with Geocoding later
        'evidence_urls': uploadedUrls,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Report submitted successfully! The AI Agent is triaging your case.",
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Go back to the User Dashboard
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("SUBMISSION ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Submission failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String stepTitle = "Incident Details";
    if (_currentStep == 2) stepTitle = "Location Information";
    if (_currentStep == 3) stepTitle = "Evidence & Submission";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text(
          "Submit Safety Report",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF003366),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Step $_currentStep of 3: $stepTitle",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _currentStep / 3,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStepUI(),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            width: double.infinity,
            child: const Text(
              "All information submitted will be handled confidentially in accordance with privacy regulations.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepUI() {
    if (_currentStep == 1) return _buildStep1();
    if (_currentStep == 2) return _buildStep2();
    return _buildStep3();
  }

  // --- STEP 1: Incident Details ---
  Widget _buildStep1() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Incident Type",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedIncidentType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Select incident type",
              ),
              items: _crimeTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedIncidentType = val),
            ),
            const SizedBox(height: 20),
            const Text(
              "Description",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Provide detailed description...",
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildPickerTile(
                    icon: Icons.calendar_today,
                    label: _selectedDate == null
                        ? "Select date"
                        : DateFormat('d/M/yyyy').format(_selectedDate!),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPickerTile(
                    icon: Icons.access_time,
                    label: _selectedTime == null
                        ? "Select time"
                        : _selectedTime!.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _currentStep = 2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    "Next",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 2: Location Information (Matches Image 1) ---
  Widget _buildStep2() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Location Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_off, color: Colors.orange.shade700),
                      const SizedBox(width: 10),
                      Text(
                        _capturedPosition == null
                            ? "Location not captured"
                            : "Location Captured!",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Please capture your location to see nearby police stations",
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: _isLocating ? null : _captureLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gps_fixed, size: 18),
                    label: const Text("Capture Location"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003366),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Additional Location Details",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _additionalLocationController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Provide any additional details...",
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Landmark Reference (Optional)",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _landmarkController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "e.g., Near Kabale University",
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text("Back"),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _currentStep = 3),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    "Next",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3() {
    return Column(
      children: [
        // 1. Evidence Upload Box
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  "Upload Evidence",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003366),
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _isLoading ? null : _pickFiles,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey.shade300,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: _isLoading ? Colors.grey.shade50 : Colors.white,
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF003366),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_upload,
                                  color: Colors.white,
                                  size: 30,
                                ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          "Tap to upload photos, videos, or audio",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${_selectedFiles.length} files selected",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 15),

        // 2. Review and Submission Section
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Review Your Report",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                _buildReviewRow(
                  "Incident Type:",
                  _selectedIncidentType ?? "Not specified",
                ),
                _buildReviewRow(
                  "Location:",
                  _capturedPosition == null
                      ? "Will be captured at submission"
                      : "GPS Coordinates Set",
                  isWarning: _capturedPosition == null,
                ),
                _buildReviewRow(
                  "Date & Time:",
                  _selectedDate == null
                      ? "Not specified"
                      : "${DateFormat('d/M/yyyy').format(_selectedDate!)} ${_selectedTime?.format(context) ?? ''}",
                ),

                const SizedBox(height: 25),

                // SAVE AS DRAFT (Visual only for now)
                OutlinedButton(
                  onPressed: _isLoading ? null : () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text("Save as Draft"),
                ),

                const SizedBox(height: 12),

                // THE SUBMIT BUTTON
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : _submitReport, // Correctly linked to the logic
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Submit Report",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),

                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _currentStep = 2),
                    child: const Text(
                      "Back",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                if (isWarning)
                  const Icon(Icons.info, size: 14, color: Colors.orange),
                if (isWarning) const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: isWarning ? Colors.orange.shade800 : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF003366)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
