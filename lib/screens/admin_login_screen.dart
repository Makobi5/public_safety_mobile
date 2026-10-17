import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_service.dart';
import '../core/admin_role.dart';
import '../core/error_handler.dart';
import 'admin_dashboard.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleAdminLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorSnackBar("Please enter both email and password.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Attempt Sign In
      await AuthService().signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      // 2. Check Role
      final role = await AuthService().getUserRole();

      final adminRole = AdminRole.fromDatabase(role);
      if (adminRole?.canAccessAdminPortal == true) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
          );
        }
      } else {
        // Wrong account type: Log them out immediately
        await AuthService().signOut();
        _showErrorSnackBar(
          role == null
              ? "Unable to verify your account role. Confirm that the admin hierarchy migration has been applied."
              : "Access Denied: This account does not have Admin privileges.",
        );
      }
    } catch (e) {
      String message;
      if (e is PostgrestException) {
        message =
            "Signed in, but couldn't verify the account role. "
            "Check that the latest Supabase migration is applied. "
            "Database error: ${e.message}";
      } else {
        message = ErrorHandler.getFriendlyErrorMessage(e);
      }
      _showErrorSnackBar(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Admin Login"),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              "Admin Access",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const Text(
              "Login with administrator credentials",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF90CAF9)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1976D2)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Note: Only authorized administrators can access this area. New admin accounts must be created by existing administrators.",
                      style: TextStyle(color: Color(0xFF1565C0), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Email",
                prefixIcon: Icon(Icons.email, color: Color(0xFF003366)),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: "Password",
                prefixIcon: const Icon(Icons.lock, color: Color(0xFF003366)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text("Forgot Password?"),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleAdminLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3F51B5),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                      "Admin Login",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
            ),
            const SizedBox(height: 40),
            const Text(
              "For admin account requests, please contact an existing administrator.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
} // Class closes correctly here at the very end
