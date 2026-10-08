import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
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
  String? _autoDetectedVillage;
  bool _isLocating = false;
  String _locationAddress = "Location not captured yet";
  double? _latitude;
  double? _longitude;
  bool _isLoadingStations = false;
  List<Map<String, dynamic>> _policeStations = [];
  String? _stationLoadError;
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
      _locationAddress = _capturedPosition == null
          ? "Getting GPS coordinates..."
          : "Refreshing GPS coordinates...";
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception("Location services are disabled.");
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception("Location permission was not granted.");
      }

      final position = await _getBestLocationFix();

      if (!mounted) return;
      setState(() {
        _capturedPosition = position;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationAddress = "Coordinates captured; looking up area name...";
        _isLoadingStations = true;
        _stationLoadError = null;
        _policeStations = [];
        _selectedPoliceStationId = null;
        _selectedPoliceStationName = null;
      });

      var district = '';
      try {
        final area = await _reverseGeocode(position);
        district = area['district'] ?? '';
        if (mounted) {
          setState(() {
            final village = area['area'];
            if (village != null) _updateDetectedVillage(village);
            _locationAddress = village == null
                ? (district.isEmpty ? "Area name unavailable" : district)
                : district.isEmpty ||
                      village.toLowerCase() == district.toLowerCase()
                ? village
                : "$village, $district";
          });
        }
      } catch (error) {
        debugPrint("Reverse geocoding failed: $error");
        if (mounted) {
          setState(() {
            _locationAddress =
                "GPS coordinates captured (area name unavailable)";
          });
        }
      }

      await _fetchProximityStations(
        position.latitude,
        position.longitude,
        district,
      );
    } catch (e) {
      debugPrint("Location capture failed: $e");
      if (mounted) {
        setState(() {
          _locationAddress = _capturedPosition == null
              ? "Unable to get GPS coordinates"
              : "Previous GPS location retained (refresh failed)";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Could not capture your location: ${e.toString().replaceFirst('Exception: ', '')}",
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<Position> _getBestLocationFix() async {
    Position? bestPosition;
    final startedAt = DateTime.now();

    try {
      await for (final candidate in Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).timeout(const Duration(seconds: 18))) {
        if (DateTime.now().difference(startedAt) >=
            const Duration(seconds: 12)) {
          break;
        }

        final age = DateTime.now().difference(candidate.timestamp).abs();
        if (!candidate.accuracy.isFinite ||
            candidate.accuracy < 0 ||
            candidate.accuracy > 1000 ||
            age > const Duration(seconds: 30)) {
          continue;
        }

        if (bestPosition == null ||
            candidate.accuracy < bestPosition.accuracy) {
          bestPosition = candidate;
          if (mounted) {
            setState(() {
              _locationAddress =
                  "Improving GPS accuracy (±${candidate.accuracy.round()} m)...";
            });
          }
        }

        if (candidate.accuracy <= 10) break;
      }
    } on TimeoutException {
      debugPrint("GPS stream timed out; using the best available fix.");
    } catch (error) {
      debugPrint("GPS position stream failed: $error");
      if (bestPosition == null) {
        return Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 25),
        );
      }
    }

    if (bestPosition != null) return bestPosition;
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 25),
    );
  }

  Future<Map<String, String?>> _reverseGeocode(Position position) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final response = await http
          .get(
            uri,
            headers: kIsWeb
                ? const {'Accept': 'application/json'}
                : const {
                    'Accept': 'application/json',
                    'User-Agent': 'CommunitySafeWatch/1.0',
                  },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('Nominatim returned HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid Nominatim response');
      }
      final rawAddress = decoded['address'];
      if (rawAddress is! Map) {
        throw const FormatException('Nominatim returned no address details');
      }
      final address = Map<String, dynamic>.from(rawAddress);
      final area = _firstAddressValue(address, [
        'village',
        'hamlet',
        'suburb',
        'neighbourhood',
        'city_district',
        'quarter',
        'town',
        'city',
      ]);
      final district = _firstAddressValue(address, [
        'city',
        'county',
        'state_district',
        'state',
      ]);
      if (area == null && district == null) {
        throw const FormatException('Nominatim returned no area name');
      }
      return {'area': area, 'district': district};
    } catch (error) {
      debugPrint("Nominatim reverse geocoding failed: $error");
    }

    if (!kIsWeb) {
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final area = _firstNonEmpty([
            placemark.subLocality,
            placemark.locality,
          ]);
          final district = _firstNonEmpty([
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
          ]);
          if (area != null || district != null) {
            return {'area': area, 'district': district};
          }
        }
      } catch (error) {
        debugPrint("Platform reverse geocoding failed: $error");
      }
    }

    // Photon allows browser cross-origin requests, unlike the Nominatim call
    // that failed in Flutter Web with "ClientException: Failed to fetch".
    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': position.latitude.toString(),
      'lon': position.longitude.toString(),
      'lang': 'en',
    });
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Reverse geocoder returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid reverse geocoder response');
    }
    final features = decoded['features'];
    if (features is! List || features.isEmpty || features.first is! Map) {
      throw const FormatException('No address found for these coordinates');
    }
    final feature = features.first as Map;
    final properties = feature['properties'];
    if (properties is! Map) {
      throw const FormatException('Reverse geocoder returned no address');
    }
    final address = Map<String, dynamic>.from(properties);
    var area = _firstAddressValue(address, [
      'suburb',
      'neighbourhood',
      'village',
      'hamlet',
      'quarter',
      'locality',
      'town',
      'city',
    ]);
    final placeType = address['osm_value']?.toString().toLowerCase();
    if (area == null &&
        address['osm_key']?.toString().toLowerCase() == 'place' &&
        const {
          'city',
          'town',
          'village',
          'hamlet',
          'suburb',
          'neighbourhood',
          'quarter',
          'locality',
        }.contains(placeType)) {
      area = _firstAddressValue(address, ['name']);
    }
    final district = _firstAddressValue(address, [
      'district',
      'county',
      'city',
      'state',
    ]);
    if (area == null && district == null) {
      throw const FormatException('Reverse geocoder returned no area name');
    }
    return {'area': area, 'district': district};
  }

  void _updateDetectedVillage(String village) {
    final currentValue = _villageController.text.trim();
    if (currentValue.isNotEmpty && currentValue != _autoDetectedVillage) return;

    _autoDetectedVillage = village;
    _villageController.value = TextEditingValue(
      text: village,
      selection: TextSelection.collapsed(offset: village.length),
    );
  }

  String? _firstAddressValue(Map<String, dynamic> address, List<String> keys) =>
      _firstNonEmpty(keys.map((key) => address[key]?.toString()));

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Future<void> _fetchProximityStations(
    double lat,
    double lon,
    String district,
  ) async {
    if (mounted) {
      setState(() {
        _isLoadingStations = true;
        _stationLoadError = null;
      });
    }
    try {
      final supabase = Supabase.instance.client;

      List<Map<String, dynamic>> stations;
      try {
        final data = await supabase.rpc(
          'find_nearest_stations',
          params: {
            'user_lat': lat,
            'user_lon': lon,
            'detected_district': district.isEmpty ? null : district,
          },
        );
        stations = _sortStationsByDistance(
          List<Map<String, dynamic>>.from(data),
          lat,
          lon,
        );
      } catch (error) {
        debugPrint(
          "Proximity RPC failed; calculating distance locally: $error",
        );
        stations = await _loadAndSortStations(lat, lon);
      }

      if (stations.isEmpty) {
        stations = await _loadAndSortStations(lat, lon);
      }
      if (mounted) {
        setState(() {
          _policeStations = stations;
          _selectedPoliceStationId = stations.isEmpty
              ? null
              : stations.first['id']?.toString();
          _selectedPoliceStationName = stations.isEmpty
              ? null
              : stations.first['name']?.toString();
          if (stations.isEmpty) {
            _stationLoadError =
                "No police stations with coordinates are available.";
          }
        });
      }
    } catch (e) {
      debugPrint("Proximity search error: $e");
      if (mounted) {
        setState(() {
          _policeStations = [];
          _selectedPoliceStationId = null;
          _selectedPoliceStationName = null;
          _stationLoadError = "Could not load nearby police stations.";
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingStations = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadAndSortStations(
    double lat,
    double lon,
  ) async {
    final data = await Supabase.instance.client
        .from('police_stations')
        .select();
    return _sortStationsByDistance(
      List<Map<String, dynamic>>.from(data),
      lat,
      lon,
    );
  }

  List<Map<String, dynamic>> _sortStationsByDistance(
    List<Map<String, dynamic>> stations,
    double lat,
    double lon,
  ) {
    final withDistance = <Map<String, dynamic>>[];
    for (final station in stations) {
      final stationLat = _stationCoordinate(station, ['latitude', 'lat']);
      final stationLon = _stationCoordinate(station, [
        'longitude',
        'lng',
        'lon',
        'long',
      ]);
      final suppliedDistance = _stationCoordinate(station, ['distance_km']);
      double? distanceKm;
      if (stationLat != null &&
          stationLon != null &&
          stationLat >= -90 &&
          stationLat <= 90 &&
          stationLon >= -180 &&
          stationLon <= 180) {
        distanceKm =
            Geolocator.distanceBetween(lat, lon, stationLat, stationLon) / 1000;
      } else if (suppliedDistance != null &&
          suppliedDistance.isFinite &&
          suppliedDistance >= 0) {
        distanceKm = suppliedDistance;
      }
      if (distanceKm == null || !distanceKm.isFinite || station['id'] == null) {
        continue;
      }
      withDistance.add({...station, 'distance_km': distanceKm});
    }
    withDistance.sort(
      (first, second) => (first['distance_km'] as double).compareTo(
        second['distance_km'] as double,
      ),
    );
    return withDistance;
  }

  double? _stationCoordinate(Map<String, dynamic> station, List<String> keys) {
    for (final key in keys) {
      final value = station[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
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
    if (_isLocating || _isLoadingStations) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please wait while your location and nearest station are being determined.",
          ),
        ),
      );
      return;
    }

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
      final villageName = _villageController.text.trim();
      final additionalLocation = _additionalLocationController.text.trim();
      final reportedAddress = [
        if (villageName.isNotEmpty) 'Village: $villageName',
        if (additionalLocation.isNotEmpty) additionalLocation,
        _locationAddress,
      ].join(' | ');
      final response = await supabase.from('incidents').insert({
        'user_id': user.id,
        'incident_type': _selectedIncidentType,
        'description': _descriptionController.text.trim(),
        'incident_date': _selectedDate?.toIso8601String(),
        'incident_time': _selectedTime?.format(context),

        'latitude': _capturedPosition!.latitude,
        'longitude': _capturedPosition!.longitude.toString(),

        // --- FIXED THIS LINE ---
        // If the user typed specific details, use those.
        // Otherwise, use the automatically detected address (e.g., Bwerenga, Entebbe City)
        'location_address': reportedAddress,

        'landmark': _landmarkController.text.trim(),
        'police_station_id': _selectedPoliceStationId,
        'police_station_name': _selectedPoliceStationName,
        'evidence_urls': uploadedUrls,
        'status': 'Pending',
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
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Location Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 1. CAPTURE STATUS BOX
            Container(
              width: double.infinity,
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
                  Text(
                    hasLocation
                        ? "Mapped address: $_locationAddress"
                        : _locationAddress,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      _capturedPosition!.accuracy > 100
                          ? "Approximate location (±${_capturedPosition!.accuracy.round()} m). Enable precise location for this site in your browser/device settings, then recapture. Confirm the village below."
                          : _capturedPosition!.accuracy <= 25
                          ? "GPS accuracy about ±${_capturedPosition!.accuracy.round()} m"
                          : "GPS accuracy about ±${_capturedPosition!.accuracy.round()} m — recapture outdoors for better precision",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: _capturedPosition!.accuracy <= 25
                            ? Colors.black54
                            : Colors.deepOrange.shade700,
                      ),
                    ),
                    Text(
                      "${_capturedPosition!.latitude.toStringAsFixed(6)}, ${_capturedPosition!.longitude.toStringAsFixed(6)}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                    const Text(
                      "Area names follow mapped boundaries and may be approximate.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                  if (hasLocation)
                    const Text(
                      "Area data © OpenStreetMap contributors",
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: _isLocating ? null : _captureLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            hasLocation ? Icons.refresh : Icons.gps_fixed,
                            size: 18,
                          ),
                    label: Text(
                      _isLocating
                          ? "Locating..."
                          : hasLocation
                          ? "Recapture Location"
                          : "Capture Location",
                    ),
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
              "Forward to Police Station",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // 2. SMART PROXIMITY DROPDOWN (Name + Distance + Phone)
            _isLoadingStations
                ? const LinearProgressIndicator(color: Color(0xFF003366))
                : DropdownButtonFormField<String>(
                    isExpanded: true,
                    // 1. Give the dropdown plenty of height to override the 24px constraint
                    itemHeight: 80,
                    value: _selectedPoliceStationId,
                    decoration: InputDecoration(
                      labelText: "Nearest Police Station",
                      labelStyle: const TextStyle(
                        color: Color(0xFF003366),
                        fontWeight: FontWeight.bold,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.local_police,
                        color: Color(0xFF003366),
                      ),
                      // 2. Reduce internal padding to nearly zero to stop the "squeezing" effect
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    hint: const Text("Select nearest station"),
                    items: _policeStations.map((station) {
                      final phone =
                          station['phone_number']?.toString() ?? "No contact";
                      final distance = _stationCoordinate(station, [
                        'distance_km',
                      ]);
                      final distanceLabel = distance == null
                          ? "Distance unavailable"
                          : "${distance.toStringAsFixed(1)} km";

                      return DropdownMenuItem<String>(
                        value: station['id'].toString(),
                        child: Text(
                          "${station['name']} ($distanceLabel)\nContact: $phone",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
            if (_stationLoadError != null) ...[
              const SizedBox(height: 8),
              Text(
                _stationLoadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 20),

            // 3. EXTRA FIELDS
            _buildField(
              _villageController,
              "Village / Local Area Name (confirm or correct)",
              Icons.home_work,
              hint: "Check the detected village or enter the correct one",
            ),
            _buildField(
              _landmarkController,
              "Landmark Reference",
              Icons.location_city,
              hint: "e.g. Near the mosque",
            ),

            const SizedBox(height: 30),

            // 4. NAVIGATION BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text("Back"),
                ),
                ElevatedButton(
                  onPressed: hasLocation
                      ? () => setState(() => _currentStep = 3)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(120, 45),
                  ),
                  child: const Text("Next"),
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
