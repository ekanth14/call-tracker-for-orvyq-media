import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

const String kBackgroundSyncTaskKey = 'com.orvyqmedia.caller_app.sync_task';
const String _kPendingSyncQueueKey = 'pending_unsubmitted_sync_queue';

/// Represents a queued offline call proof awaiting background sync
class SyncItem {
  final String id;
  final Map<String, dynamic> payload;
  String status; // 'pending' | 'failed'
  int retryCount;
  String? lastError;
  final DateTime createdAt;
  DateTime? lastAttemptedAt;

  SyncItem({
    required this.id,
    required this.payload,
    this.status = 'pending',
    this.retryCount = 0,
    this.lastError,
    required this.createdAt,
    this.lastAttemptedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'payload': payload,
        'status': status,
        'retry_count': retryCount,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
        'last_attempted_at': lastAttemptedAt?.toIso8601String(),
      };

  factory SyncItem.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('payload')) {
      return SyncItem(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        status: json['status'] as String? ?? 'pending',
        retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
        lastAttemptedAt: json['last_attempted_at'] != null
            ? DateTime.tryParse(json['last_attempted_at'] as String)
            : null,
      );
    } else {
      // Backward-compatibility: legacy flat payload
      return SyncItem(
        id: json['p_dial_attempt_id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        payload: Map<String, dynamic>.from(json),
        status: 'pending',
        retryCount: 0,
        createdAt: DateTime.now(),
      );
    }
  }

  static bool isPermanentError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('not authorized') ||
        lower.contains('permission denied') ||
        lower.contains('violates foreign key') ||
        lower.contains('p0001') ||
        lower.contains('invalid_duration') ||
        lower.contains('attempt already closed') ||
        lower.contains('call_locked') ||
        lower.contains('column') ||
        lower.contains('does not exist');
  }
}

/// Top-level callback dispatcher required by WorkManager (§5.2)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await BackgroundSyncService.processSyncQueue();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundSyncService {
  /// Initializes WorkManager and registers a periodic sync job (§5.2)
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );

      // Register periodic background sync every 15 minutes
      await Workmanager().registerPeriodicTask(
        'periodic-call-sync-id',
        kBackgroundSyncTaskKey,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
      );
    } catch (_) {
      // Workmanager initialization error (e.g. running on non-Android platform)
    }
  }

  /// Saves an un-synced call dialog payload into local queue for background upload
  static Future<void> enqueuePendingSync(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];

    final item = SyncItem(
      id: payload['p_dial_attempt_id'] as String? ??
          'sync_${DateTime.now().millisecondsSinceEpoch}',
      payload: payload,
      status: 'pending',
      retryCount: 0,
      createdAt: DateTime.now(),
    );

    // Prevent exact duplicates in queue
    final filtered = queue.where((s) {
      try {
        final decoded = jsonDecode(s);
        final existingId = decoded['id'] ?? decoded['p_dial_attempt_id'];
        return existingId != item.id;
      } catch (_) {
        return true;
      }
    }).toList();

    filtered.add(jsonEncode(item.toJson()));
    await prefs.setStringList(_kPendingSyncQueueKey, filtered);

    // Trigger an immediate one-off sync task
    try {
      await Workmanager().registerOneOffTask(
        'immediate-sync-${DateTime.now().millisecondsSinceEpoch}',
        kBackgroundSyncTaskKey,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  /// Processes the local sync queue. Removes successful items.
  /// Categorizes transient network errors as pending retry, and permanent errors
  /// or max retries as 'failed' so they remain visible and are not silently lost.
  static Future<Map<String, int>> processSyncQueue({
    SupabaseClient? client,
    SharedPreferences? testPrefs,
  }) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_kPendingSyncQueueKey) ?? [];

    if (queueJson.isEmpty) {
      return {'succeeded': 0, 'pending': 0, 'failed': 0};
    }

    SupabaseClient supabase;
    if (client != null) {
      supabase = client;
    } else {
      supabase = Supabase.instance.client;
    }

    final updatedItems = <SyncItem>[];
    int succeeded = 0;

    for (final itemStr in queueJson) {
      SyncItem item;
      try {
        final decoded = jsonDecode(itemStr);
        item = SyncItem.fromJson(Map<String, dynamic>.from(decoded as Map));
      } catch (_) {
        continue;
      }

      if (item.status == 'failed') {
        // Keep failed items visible without retrying automatically
        updatedItems.add(item);
        continue;
      }

      try {
        try {
          await supabase.rpc('submit_call_dialog', params: item.payload);
        } catch (e) {
          final errStr = e.toString();
          if ((errStr.contains('p_evidence_source') ||
                  errStr.contains('PGRST202') ||
                  errStr.contains('schema cache')) &&
              item.payload.containsKey('p_evidence_source')) {
            final fallbackPayload = Map<String, dynamic>.from(item.payload)
              ..remove('p_evidence_source');
            await supabase.rpc('submit_call_dialog', params: fallbackPayload);
          } else {
            rethrow;
          }
        }
        succeeded++;
        // Successfully submitted: removed from queue
      } catch (e) {
        final errMsg = e.toString();
        item.lastAttemptedAt = DateTime.now();
        item.retryCount += 1;
        item.lastError = errMsg;

        if (SyncItem.isPermanentError(errMsg) || item.retryCount >= 5) {
          // Permanent failure or max retries exhausted: keep visible as failed
          item.status = 'failed';
        } else {
          item.status = 'pending';
        }
        updatedItems.add(item);
      }
    }

    await prefs.setStringList(
      _kPendingSyncQueueKey,
      updatedItems.map((i) => jsonEncode(i.toJson())).toList(),
    );

    final pendingCount =
        updatedItems.where((i) => i.status == 'pending').length;
    final failedCount =
        updatedItems.where((i) => i.status == 'failed').length;

    return {
      'succeeded': succeeded,
      'pending': pendingCount,
      'failed': failedCount,
    };
  }

  /// Returns count of pending items waiting for background sync
  static Future<int> getPendingSyncCount({SharedPreferences? testPrefs}) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    int count = 0;
    for (final itemStr in queue) {
      try {
        final decoded = jsonDecode(itemStr);
        final item = SyncItem.fromJson(Map<String, dynamic>.from(decoded as Map));
        if (item.status == 'pending') count++;
      } catch (_) {}
    }
    return count;
  }

  /// Returns count of failed sync items requiring attention
  static Future<int> getFailedSyncCount({SharedPreferences? testPrefs}) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    int count = 0;
    for (final itemStr in queue) {
      try {
        final decoded = jsonDecode(itemStr);
        final item = SyncItem.fromJson(Map<String, dynamic>.from(decoded as Map));
        if (item.status == 'failed') count++;
      } catch (_) {}
    }
    return count;
  }

  /// Returns all failed sync items so they can be shown in UI
  static Future<List<SyncItem>> getFailedSyncItems({
    SharedPreferences? testPrefs,
  }) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    final failed = <SyncItem>[];
    for (final itemStr in queue) {
      try {
        final decoded = jsonDecode(itemStr);
        final item = SyncItem.fromJson(Map<String, dynamic>.from(decoded as Map));
        if (item.status == 'failed') failed.add(item);
      } catch (_) {}
    }
    return failed;
  }

  /// Retries a single failed item
  static Future<void> retryFailedItem(
    String id, {
    SupabaseClient? client,
    SharedPreferences? testPrefs,
  }) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    final updated = <String>[];

    for (final itemStr in queue) {
      try {
        final decoded = jsonDecode(itemStr);
        final item = SyncItem.fromJson(Map<String, dynamic>.from(decoded as Map));
        if (item.id == id) {
          item.status = 'pending';
          item.retryCount = 0;
          item.lastError = null;
          updated.add(jsonEncode(item.toJson()));
        } else {
          updated.add(itemStr);
        }
      } catch (_) {
        updated.add(itemStr);
      }
    }

    await prefs.setStringList(_kPendingSyncQueueKey, updated);
    await processSyncQueue(client: client, testPrefs: prefs);
  }

  /// Dismisses or removes a failed sync item from queue
  static Future<void> removeSyncItem(
    String id, {
    SharedPreferences? testPrefs,
  }) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    final updated = queue.where((s) {
      try {
        final decoded = jsonDecode(s);
        final itemId = decoded['id'] ?? decoded['p_dial_attempt_id'];
        return itemId != id;
      } catch (_) {
        return true;
      }
    }).toList();

    await prefs.setStringList(_kPendingSyncQueueKey, updated);
  }
}
