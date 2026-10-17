import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../../core/config/app_config.dart';

const String kBackgroundSyncTaskKey = 'com.orvyqmedia.caller_app.sync_task';
const String _kPendingSyncQueueKey = 'pending_unsubmitted_sync_queue';

/// Top-level callback dispatcher required by WorkManager (§5.2)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList(_kPendingSyncQueueKey) ?? [];

      if (queueJson.isEmpty) {
        return Future.value(true);
      }

      // Initialize Supabase in background isolate
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      final supabase = Supabase.instance.client;

      final remainingItems = <String>[];

      for (final itemStr in queueJson) {
        try {
          final Map<String, dynamic> item = jsonDecode(itemStr);
          // Upload via submit_call_dialog RPC
          await supabase.rpc('submit_call_dialog', params: item);
        } catch (_) {
          // Keep item in queue if upload failed (e.g. network lost)
          remainingItems.add(itemStr);
        }
      }

      await prefs.setStringList(_kPendingSyncQueueKey, remainingItems);
      return Future.value(true);
    } catch (_) {
      return Future.value(false);
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
    queue.add(jsonEncode(payload));
    await prefs.setStringList(_kPendingSyncQueueKey, queue);

    // Trigger an immediate one-off sync task
    try {
      await Workmanager().registerOneOffTask(
        'immediate-sync-${DateTime.now().millisecondsSinceEpoch}',
        kBackgroundSyncTaskKey,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  /// Returns count of pending items waiting for background sync
  static Future<int> getPendingSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_kPendingSyncQueueKey) ?? [];
    return queue.length;
  }
}
