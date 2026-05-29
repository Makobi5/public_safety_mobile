import 'package:flutter/material.dart';
import '../core/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fNameController = TextEditingController();
  final _lNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedRegion;
  String? _selectedDistrict;
  String? _selectedVillage; // Changed to match dropdown logic
  bool _isAgreed = false;
  bool _isLoading = false;
  bool _obscurePass = true;

  // 1. STATE VARIABLES (NOT FINAL)
  List<String> _districts = [];
  List<String> _villages = [];

  // 2. DATA SOURCE
  final Map<String, Map<String, List<String>>> _locationData = {
    "Western": {
      "Kabale": [
        "Central Division",
        "Northern Division",
        "Southern Division",
        "Kyanamira",
        "Maziba",
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
        "Nakawa",
        "Makindye",
        "Kawempe",
        "Rubaga",
      ],
      "Wakiso": [
        "Entebbe Municipality",
        "Kira Municipality",
        "Nansana",
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

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please agree to the Terms and Conditions"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        firstName: _fNameController.text.trim(),
        lastName: _lNameController.text.trim(),
        region: _selectedRegion!,
        district: _selectedDistrict!,
        village: _selectedVillage!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Registration Successful! Please Login."),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Create Account"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: Color(0xFFD1E3FF),
                child: Icon(Icons.shield, size: 40, color: Color(0xFF003366)),
              ),
              const SizedBox(height: 16),
              const Text(
                "Public Safety Reporting App",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003366),
                ),
              ),
              const Text(
                "Create Your Account",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              _buildField(_fNameController, "First Name", Icons.person),
              _buildField(_lNameController, "Last Name", Icons.person),

              // 1. REGION DROPDOWN
              _buildDropdown(
                "Select Region",
                Icons.map,
                _locationData.keys.toList(),
                (val) {
                  if (val == null)
                    return; // Don't do anything if selection is null

                  setState(() {
                    _selectedRegion = val;
                    // Reset dependent fields
                    _selectedDistrict = null;
                    _selectedVillage = null;

                    // SAFE LOOKUP: Use ? and ?? to prevent the crash you saw
                    _districts = _locationData[val]?.keys.toList() ?? [];
                    _villages = [];
                  });
                },
                _selectedRegion,
              ),

              // 2. DISTRICT
              _buildDropdown(
                "Select District",
                Icons.location_city,
                _districts,
                (val) {
                  setState(() {
                    _selectedDistrict = val;
                    _selectedVillage = null;
                    _villages = _locationData[_selectedRegion]![val]!;
                  });
                },
                _selectedDistrict,
                enabled: _selectedRegion != null,
              ),

              // 3. VILLAGE/AREA
              _buildDropdown(
                "Select Village/Area",
                Icons.location_on,
                _villages,
                (val) => setState(() => _selectedVillage = val),
                _selectedVillage,
                enabled: _selectedDistrict != null,
              ),

              _buildField(_emailController, "Email Address", Icons.email),
              _buildField(
                _passwordController,
                "Password",
                Icons.lock,
                isPass: true,
              ),
              _buildField(
                _confirmPasswordController,
                "Confirm Password",
                Icons.lock,
                isPass: true,
                isConfirm: true,
              ),

              Row(
                children: [
                  Checkbox(
                    value: _isAgreed,
                    onChanged: (val) => setState(() => _isAgreed = val!),
                  ),
                  const Expanded(
                    child: Text(
                      "I agree to the Terms and Conditions",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Create Account",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPass = false,
    bool isConfirm = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: isPass ? _obscurePass : false,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF003366)),
          border: const OutlineInputBorder(),
          suffixIcon: isPass
              ? IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                )
              : null,
        ),
        validator: (val) {
          if (val == null || val.isEmpty) return "Required";
          if (isConfirm && val != _passwordController.text)
            return "Passwords do not match";
          return null;
        },
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: currentValue,
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
