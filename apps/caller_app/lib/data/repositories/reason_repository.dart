import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reason_model.dart';

class ReasonRepository {
  final SupabaseClient _supabase;
  List<ReasonModel>? _cachedReasons;

  ReasonRepository(this._supabase);

  Future<List<ReasonModel>> fetchActiveReasons() async {
    if (_cachedReasons != null && _cachedReasons!.isNotEmpty) {
      return _cachedReasons!;
    }

    final response = await _supabase
        .from('reasons')
        .select('*')
        .eq('is_active', true)
        .order('display_order', ascending: true);

    final List<dynamic> list = response as List<dynamic>;
    _cachedReasons = list
        .map((item) => ReasonModel.fromJson(item as Map<String, dynamic>))
        .toList();

    return _cachedReasons!;
  }

  List<ReasonModel> filterByCategory(List<ReasonModel> all, String category) {
    return all.where((r) => r.category == category).toList();
  }
}
