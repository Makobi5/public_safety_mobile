import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  // Define the client inside the class
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. Sign in with Email and Password
  Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // 2. Sign Up logic (Perform Auth + Create Profile)
  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String region,
    required String district,
    required String subCounty,
    required String village,
  }) async {
    // Perform the actual Auth Sign Up
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    // If auth was successful, insert the profile data
    if (res.user != null) {
      await _supabase.from('user_profiles').insert({
        'user_id': res.user!.id,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'region': region,
        'district': district,
        'sub_county': subCounty,
        'village_area': village,
        'role': 'standard_user',
      });
    }
  }

  // 3. Get current user role
  Future<String?> getUserRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final data = await _supabase
        .from('user_profiles')
        .select('role')
        .eq('user_id', user.id)
        .maybeSingle();

    return data?['role'] as String?;
  }

  // 4. Sign Out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
} // Class finally ends here
