import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lead_model.dart';

class LeadRepository {
  final SupabaseClient _supabase;

  LeadRepository(this._supabase);

  Future<List<LeadModel>> fetchAssignedLeads() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated.');
    }

    final response = await _supabase
        .from('leads')
        .select('*')
        .eq('assigned_to', userId)
        .neq('status', 'do_not_call')
        .order('next_follow_up_at', ascending: true, nullsFirst: false)
        .order('created_at', ascending: false);

    final List<dynamic> list = response as List<dynamic>;
    return list.map((item) => LeadModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<LeadModel?> getLeadById(String id) async {
    final response = await _supabase
        .from('leads')
        .select('*')
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return LeadModel.fromJson(response);
  }
}
