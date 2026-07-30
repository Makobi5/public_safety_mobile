import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  int _currentStep = 1;
  final _formKey = GlobalKey<FormState>();
  Position? _capturedPosition;
  bool _isLocating = false;
  String _locationAddress = "Location not captured yet";
  double? _latitude;
  double? _longitude;
  bool _isLoadingStations = false;
  List<Map<String, dynamic>> _policeStations = [];
  String? _selectedPoliceStationId;
  String? _selectedPoliceStationName;
  final _villageController = TextEditingController(); // Added
  final _landmarkController = TextEditingController(); // Added
  final _witnessInfoController = TextEditingController();
  final _additionalNotesController = TextEditingController();

  // --- Data for Step 1 ---
  String? _selectedIncidentType;
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  final _additionalLocationController = TextEditingController();

  // --- Data for Step 3 ---
  List<PlatformFile> _selectedFiles = [];
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
    setState(() {
      _isLocating = true;
      _locationAddress = "Fetching area name..."; // UI Feedback
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // OpenStreetMap Nominatim API
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept-Language': 'en',
          'User-Agent': 'SafeWatch_App_Uganda', // Required by Nominatim
        },
      );

      String village = "Unknown Area";
      String district = "Unknown District";

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final addr = data['address'] ?? {};

        // UGANDA SPECIFIC PARSING: Look for neighborhood levels
        // Browsers often return 'suburb' for Kampala and 'village' for Kabale
        village =
            addr['suburb'] ??
            addr['neighbourhood'] ??
            addr['village'] ??
            addr['hamlet'] ??
            addr['town'] ??
            "Unknown Area";

        district =
            addr['city'] ??
            addr['county'] ??
            addr['state'] ??
            "Unknown District";

        setState(() {
          _capturedPosition = position;
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationAddress = "$village, $district";
        });

        // Search for nearest stations
        await _fetchProximityStations(position.latitude, position.longitude);
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
      setState(() {
        _locationAddress = "GPS Signal Set (Area name unavailable)";
      });
    } finally {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _fetchProximityStations(double lat, double lon) async {
    setState(() => _isLoadingStations = true);
    try {
      final supabase = Supabase.instance.client;

      // Call the SQL function we created in Step 1
      final List<dynamic> data = await supabase.rpc(
        'find_nearest_stations',
        params: {'user_lat': lat, 'user_lon': lon},
      );

      final stations = List<Map<String, dynamic>>.from(data);

      setState(() {
        _policeStations = stations;
        if (stations.isNotEmpty) {
          // The database already sorted by distance, so index 0 is the closest
          _selectedPoliceStationId = stations[0]['id'];
          _selectedPoliceStationName = stations[0]['name'];
        }
      });
    } catch (e) {
      debugPrint("Proximity search error: $e");
    } finally {
      setState(() => _isLoadingStations = false);
    }
  }

  Future<void> _fetchNearbyStations(String districtName) async {
    setState(() => _isLoadingStations = true);
    try {
      final supabase = Supabase.instance.client;

      // Search for stations matching the detected district
      final data = await supabase
          .from('police_stations')
          .select()
          .ilike('district', '%$districtName%');

      final stations = List<Map<String, dynamic>>.from(data);

      setState(() {
        _policeStations = stations;
        if (stations.isNotEmpty) {
          _selectedPoliceStationId = stations[0]['id'];
          _selectedPoliceStationName = stations[0]['name'];
        } else {
          // If no local station found, show all as fallback (like Kabale)
          _loadAllStationsFallback();
        }
      });
    } catch (e) {
      debugPrint("Station error: $e");
    } finally {
      setState(() => _isLoadingStations = false);
    }
  }

  // Helper to load all stations if current district has none in DB
  Future<void> _loadAllStationsFallback() async {
    final data = await Supabase.instance.client
        .from('police_stations')
        .select();
    setState(() {
      _policeStations = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
        // CRITICAL FOR WEB: This ensures file.bytes is not null
        withData: true,
      );

      if (result != null) {
        setState(() {
          // Append new files to the list instead of replacing
          _selectedFiles.addAll(result.files);

          // Limit to 5 files
          if (_selectedFiles.length > 5) {
            _selectedFiles = _selectedFiles.sublist(0, 5);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Maximum 5 files allowed")),
            );
          }
        });
        debugPrint("Files in list: ${_selectedFiles.length}");
      }
    } catch (e) {
      debugPrint("Picker error: $e");
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

    // 2. Final Location Check: Ensure user captured GPS before submitting
    if (_capturedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please capture your location in Step 2 before submitting",
          ),
        ),
      );
      setState(() => _currentStep = 2); // Send them back to capture location
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      List<String> uploadedUrls = [];

      // 3. UPLOAD FILES TO STORAGE
      for (var file in _selectedFiles) {
        final String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final String storagePath = 'evidence/${user.id}/$fileName';

        try {
          if (kIsWeb) {
            if (file.bytes == null) continue;
            await supabase.storage
                .from('incident-evidence')
                .uploadBinary(
                  storagePath,
                  file.bytes!,
                  fileOptions: const FileOptions(
                    cacheControl: '3600',
                    upsert: false,
                  ),
                );
          } else {
            if (file.path == null) continue;
            await supabase.storage
                .from('incident-evidence')
                .upload(storagePath, File(file.path!));
          }

          final String publicUrl = supabase.storage
              .from('incident-evidence')
              .getPublicUrl(storagePath);
          uploadedUrls.add(publicUrl);
        } catch (uploadError) {
          debugPrint("Failed to upload ${file.name}: $uploadError");
        }
      }

      // 4. SAVE DATA TO 'incidents' TABLE (Including GPS and Station)
      final response = await supabase.from('incidents').insert({
        'user_id': user.id,
        'incident_type': _selectedIncidentType,
        'description': _descriptionController.text.trim(),
        'incident_date': _selectedDate?.toIso8601String(),
        'incident_time': _selectedTime?.format(context),

        // GPS Data
        'latitude': _capturedPosition!.latitude,
        'longitude': _capturedPosition!.longitude.toString(),

        // Location text details
        'location_address': _additionalLocationController.text.trim().isNotEmpty
            ? _additionalLocationController.text.trim()
            : 'GPS Location Captured',
        'landmark': _landmarkController.text.trim(),

        // Routing to nearby station
        'police_station_id': _selectedPoliceStationId,
        'police_station_name': _selectedPoliceStationName,

        'evidence_urls': uploadedUrls,
        'status': 'Pending', // Using Capital P for consistency with Admin side
        'user_read': true,
      }).select(); // select() helps us get the ID back for the AI agent

      // 5. TRIGGER AI TRIAGE AGENT (Optional - calls your swift-handler)
      if (response.isNotEmpty) {
        final newId = response[0]['id'];
        try {
          await supabase.functions.invoke(
            'swift-handler',
            body: {
              'action': 'triage-incident',
              'incident_id': newId,
              'description': _descriptionController.text,
            },
          );
        } catch (aiError) {
          debugPrint("AI Triage failed: $aiError");
          // Don't stop the whole process if AI fails
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Report submitted successfully! The Police Unit has been notified.",
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Return to Dashboard
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

  Widget _buildStep2() {
    bool hasLocation = _capturedPosition != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Added safety
          children: [
            const Text(
              "Location Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Capture Status Box
            Container(
              width: double.infinity, // Ensure full width
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasLocation
                    ? Colors.green.shade50
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasLocation
                      ? Colors.green.shade300
                      : Colors.orange.shade200,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        hasLocation ? Icons.check_circle : Icons.location_off,
                        color: hasLocation ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        hasLocation
                            ? "Location Captured!"
                            : "Location not captured",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // DISPLAY THE ADDRESS NAME HERE
                  Text(
                    _locationAddress,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
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
                    label: Text(
                      _isLocating ? "Locating..." : "Capture Location",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003366),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),
            const Text(
              "Forward to Police Station",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // DROPDOWN - Simplified to prevent render box errors
            _isLoadingStations
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    isExpanded: true, // Crucial for Web
                    value: _selectedPoliceStationId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.local_police),
                    ),
                    items: _policeStations.map((station) {
                      return DropdownMenuItem<String>(
                        value: station['id'].toString(),
                        child: Text(
                          "${station['name']} (${(station['distance_km'] ?? 0.0).toStringAsFixed(1)} km)",
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedPoliceStationId = val;
                        _selectedPoliceStationName = _policeStations.firstWhere(
                          (s) => s['id'].toString() == val,
                        )['name'];
                      });
                    },
                  ),

            const SizedBox(height: 20),
            // Village Controller and Landmark Fields remain same...
            _buildField(
              _villageController,
              "Village / Local Area Name",
              Icons.home_work,
              hint: "Specific village details",
            ),
            _buildField(
              _landmarkController,
              "Landmark Reference",
              Icons.location_city,
              hint: "e.g. Near the mosque",
            ),

            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: const Text("Back"),
                ),
                ElevatedButton(
                  onPressed: hasLocation
                      ? () => setState(() => _currentStep = 3)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
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
                if (_selectedFiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Column(
                      children: _selectedFiles.asMap().entries.map((entry) {
                        int index = entry.key;
                        var file = entry.value;
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.insert_drive_file,
                            color: Color(0xFF003366),
                          ),
                          title: Text(
                            file.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _selectedFiles.removeAt(index)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
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

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: const Color(0xFF003366)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
