import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class IncidentReportScreen extends StatefulWidget {
  @override
  _IncidentReportScreenState createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  final _descController = TextEditingController();
  List<File> _selectedFiles = [];

  // MOBILE FILE PICKING
  Future<void> _pickMobileFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _selectedFiles = result.paths.map((path) => File(path!)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Submit Report (Mobile)")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _descController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "What happened? (Our AI will triage this)",
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pickMobileFiles,
              icon: Icon(Icons.attach_file),
              label: Text("Attach Evidence (${_selectedFiles.length})"),
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () {
                /* We will add Supabase logic here next */
              },
              child: Text("SUBMIT TO AGENT"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
