import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UserCaseDetailScreen extends StatelessWidget {
  final Map<String, dynamic> incident;
  const UserCaseDetailScreen({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(incident['created_at']);
    final String status = incident['status'] ?? 'Pending';
    final List<dynamic> evidence = incident['evidence_urls'] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Details"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Timeline Card
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
                          "Current Status: ${status.toUpperCase()}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003366),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Your report is being reviewed by the local police unit.",
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // Police Feedback Section
            const Text(
              "Official Response",
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
                incident['police_notes'] ??
                    "No message from the police yet. Please stay safe.",
                style: TextStyle(
                  color: incident['police_notes'] == null
                      ? Colors.grey
                      : Colors.black87,
                ),
              ),
            ),

            const SizedBox(height: 25),

            // Original Report
            const Text(
              "My Report Details",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text("Type: ${incident['incident_type']}"),
            Text("Date: ${DateFormat('MMM d, yyyy').format(date)}"),
            const Divider(height: 30),
            Text(
              incident['description'] ?? "",
              style: const TextStyle(height: 1.5),
            ),

            const SizedBox(height: 25),

            // Evidence
            if (evidence.isNotEmpty) ...[
              const Text(
                "Evidence Sent",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: evidence.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        evidence[index],
                        width: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
