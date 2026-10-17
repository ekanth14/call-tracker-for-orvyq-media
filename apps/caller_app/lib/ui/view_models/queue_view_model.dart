import 'package:flutter/foundation.dart';
import '../../data/models/lead_model.dart';
import '../../data/repositories/lead_repository.dart';

enum QueueFilter { all, pending, followUp, completed }

class QueueViewModel extends ChangeNotifier {
  final LeadRepository _leadRepository;

  QueueViewModel(this._leadRepository);

  List<LeadModel> _allLeads = [];
  bool _isLoading = false;
  String? _errorMessage;
  QueueFilter _currentFilter = QueueFilter.all;
  String _searchQuery = '';

  List<LeadModel> get allLeads => _allLeads;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  QueueFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;

  List<LeadModel> get filteredLeads {
    return _allLeads.where((lead) {
      // 1. Text filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = lead.name.toLowerCase().contains(query);
        final matchesCompany = lead.company?.toLowerCase().contains(query) ?? false;
        final matchesPhone = lead.phoneE164.contains(query);
        final matchesCity = lead.city?.toLowerCase().contains(query) ?? false;
        if (!matchesName && !matchesCompany && !matchesPhone && !matchesCity) {
          return false;
        }
      }

      // 2. Status filter
      switch (_currentFilter) {
        case QueueFilter.pending:
          return lead.status == 'new' ||
              lead.status == 'assigned' ||
              lead.status == 'in_progress';
        case QueueFilter.followUp:
          return lead.status == 'follow_up' || lead.nextFollowUpAt != null;
        case QueueFilter.completed:
          return lead.status == 'interested' ||
              lead.status == 'not_interested' ||
              lead.status == 'called';
        case QueueFilter.all:
          return true;
      }
    }).toList();
  }

  Future<void> loadLeads({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      _allLeads = await _leadRepository.fetchAssignedLeads();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      _isLoading = false;
      notifyListeners();
    }
  }

  void setFilter(QueueFilter filter) {
    _currentFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}
