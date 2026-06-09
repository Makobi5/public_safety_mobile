import 'package:flutter/material.dart';
import '../core/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fName = TextEditingController();
  final _lName = TextEditingController();
  final _village = TextEditingController();

  bool _isLoading = false;

  // Location State
  String? _selectedRegion;
  String? _selectedDistrict;
  String? _selectedSubCounty;
  List<String> _districts = [];
  List<String> _subCounties = [];

  // Reusing the same realistic Uganda data
  final Map<String, Map<String, List<String>>> _locationData = {
    "Western": {
      "Kabale": [
        "Central Division",
        "Northern Division",
        "Southern Division",
        "Kyanamira",
        "Maziba",
        "Butanda",
        "Kitumba",
      ],
      "Mbarara": [
        "Mbarara City North",
        "Mbarara City South",
        "Biharwe",
        "Kakiika",
      ],
      "Rubanda": ["Hamurwa", "Muko", "Bubare", "Nyamweru"],
      "Rukiga": ["Mparo", "Kashambya", "Kamwezi", "Muhanga"],
    },
    "Central": {
      "Kampala": [
        "Central Division (CBD)",
        "Nakawa Division",
        "Makindye Division",
        "Kawempe Division",
        "Rubaga Division",
      ],
      "Wakiso": [
        "Kira Municipality",
        "Nansana Municipality",
        "Entebbe Municipality",
        "Kyengera",
      ],
    },
    "Eastern": {
      "Jinja": ["Jinja City North", "Jinja City South", "Bugembe"],
      "Mbale": ["Industrial Division", "Northern Division"],
    },
    "Northern": {
      "Gulu": ["Pece-Laroo Division", "Bardege-Layibi Division"],
      "Lira": ["Lira City East", "Lira City West"],
    },
  };

  @override
  void initState() {
    super.initState();
    // 1. Pre-fill text controllers
    _fName.text = widget.userData['first_name'] ?? "";
    _lName.text = widget.userData['last_name'] ?? "";
    _village.text = widget.userData['village_area'] ?? "";

    // 2. SAFE LOCATION FETCHING
    String? dbRegion = widget.userData['region'];
    String? dbDistrict = widget.userData['district'];
    String? dbSubCounty = widget.userData['sub_county'];

    // Check if the Region from the database actually exists in our Map
    if (dbRegion != null && _locationData.containsKey(dbRegion)) {
      _selectedRegion = dbRegion;
      _districts = _locationData[dbRegion]!.keys.toList();

      // Check if the District exists within that Region
      if (dbDistrict != null &&
          _locationData[dbRegion]!.containsKey(dbDistrict)) {
        _selectedDistrict = dbDistrict;
        _subCounties = _locationData[dbRegion]![dbDistrict]!;

        // Check if the Sub-County exists within that District
        if (dbSubCounty != null && _subCounties.contains(dbSubCounty)) {
          _selectedSubCounty = dbSubCounty;
        }
      }
    } else {
      // If data is "System Assigned" or unknown, reset to null so user can pick
      _selectedRegion = null;
      _selectedDistrict = null;
      _selectedSubCounty = null;
    }
  }

  Future<void> _handleUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService().updateProfile(
        firstName: _fName.text.trim(),
        lastName: _lName.text.trim(),
        region: _selectedRegion!,
        district: _selectedDistrict!,
        subCounty: _selectedSubCounty!,
        village: _village.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile updated successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Edit Details"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 1. Personal Names
              _buildTextField(_fName, "First Name", Icons.person),
              _buildTextField(_lName, "Last Name", Icons.person),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(thickness: 1),
              ),

              // 2. REGION DROPDOWN (With the requested safe logic)
              _buildDropdown("Region", Icons.map, _locationData.keys.toList(), (
                val,
              ) {
                if (val == null) return;
                setState(() {
                  _selectedRegion = val;
                  _selectedDistrict = null;
                  _selectedSubCounty = null;

                  // SAFE LOOKUP: Using ? and ?? [] to prevent Web crashes
                  _districts = _locationData[val]?.keys.toList() ?? [];
                  _subCounties = [];
                });
              }, _selectedRegion),

              // 3. DISTRICT DROPDOWN
              _buildDropdown(
                "District",
                Icons.location_city,
                _districts,
                (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedDistrict = val;
                    _selectedSubCounty = null;

                    // SAFE LOOKUP: Filter sub-counties based on Region and District
                    _subCounties = _locationData[_selectedRegion]?[val] ?? [];
                  });
                },
                _selectedDistrict,
                enabled: _selectedRegion != null,
              ),

              // 4. SUB-COUNTY / DIVISION DROPDOWN
              _buildDropdown(
                "Sub-County / Division",
                Icons.layers,
                _subCounties,
                (val) {
                  setState(() => _selectedSubCounty = val);
                },
                _selectedSubCounty,
                enabled: _selectedDistrict != null,
              ),

              // 5. VILLAGE TEXT FIELD
              _buildTextField(
                _village,
                "Village / Local Area",
                Icons.home_work,
              ),

              const SizedBox(height: 50),

              // 6. ACTION BUTTONS (Save & Cancel)
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF003366))
              else
                Row(
                  children: [
                    // CANCEL BUTTON
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 55),
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    // SAVE BUTTON
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003366),
                          minimumSize: const Size(0, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          "Save Changes",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF003366)),
          border: const OutlineInputBorder(),
        ),
        validator: (val) => val!.isEmpty ? "Required" : null,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    IconData icon,
    List<String> items,
    Function(String?) onChanged,
    String? currentValue, {
    bool enabled = true,
  }) {
    // SAFETY CHECK: Ensure currentValue is actually in the items list
    // If not, we set it to null to prevent the "Assertion failed" crash
    String? safeValue = items.contains(currentValue) ? currentValue : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: safeValue, // Use the safe value here
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF003366)),
          border: const OutlineInputBorder(),
          filled: !enabled,
          fillColor: enabled ? Colors.transparent : Colors.grey.shade100,
        ),
        items: enabled
            ? items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList()
            : [],
        onChanged: enabled ? onChanged : null,
        validator: (val) => val == null ? "Required" : null,
      ),
    );
  }
}
