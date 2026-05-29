import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Sign in with Email and Password
  Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String region,
    required String district,
    required String village,
  }) async {
    // 1. Sign up the user in Supabase Auth
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (res.user != null) {
      // 2. Save profile details to user_profiles table
      await _supabase.from('user_profiles').insert({
        'user_id': res.user!.id,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'region': region,
        'district': district,
        'village_area': village,
        'role': 'member',
      });
    }
  }

  // Get current user role
  Future<String?> getUserRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final data = await _supabase
        .from('user_profiles')
        .select('role')
        .eq('user_id', user.id)
        .maybeSingle(); // Using maybeSingle to avoid crashes if no profile exists

    return data?['role'] as String?;
  }

  // Sign Out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
