import 'package:flutter/foundation.dart';
import '../../data/models/stats_model.dart';
import '../../data/repositories/calling_repository.dart';

class StatsViewModel extends ChangeNotifier {
  final CallingRepository _callingRepository;

  StatsViewModel(this._callingRepository);

  StatsModel _stats = StatsModel();
  bool _isLoading = false;

  StatsModel get stats => _stats;
  bool get isLoading => _isLoading;

  Future<void> loadTodayStats() async {
    _isLoading = true;
    notifyListeners();

    try {
      _stats = await _callingRepository.getTodayStats();
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      _isLoading = false;
      notifyListeners();
    }
  }
}
