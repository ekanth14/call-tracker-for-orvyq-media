import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/calling_repository.dart';
import 'data/repositories/lead_repository.dart';
import 'data/repositories/reason_repository.dart';
import 'data/services/background_sync_service.dart';
import 'data/services/call_launcher_service.dart';
import 'data/services/call_log_service.dart';
import 'data/services/storage_service.dart';
import 'ui/router/app_router.dart';
import 'ui/view_models/auth_view_model.dart';
import 'ui/view_models/calling_view_model.dart';
import 'ui/view_models/queue_view_model.dart';
import 'ui/view_models/stats_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Supabase Client
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  final supabase = Supabase.instance.client;

  // Initialize Local Storage & Background Services
  final storageService = await StorageService.init();
  final callLauncherService = CallLauncherService();
  final callLogService = CallLogService();

  // Initialize WorkManager background sync (§5.2)
  await BackgroundSyncService.initialize();

  // Initialize Repositories
  final authRepository = AuthRepository(supabase, storageService);
  final leadRepository = LeadRepository(supabase);
  final callingRepository = CallingRepository(supabase, storageService);
  final reasonRepository = ReasonRepository(supabase);

  // Initialize ViewModels
  final authViewModel = AuthViewModel(authRepository);
  final queueViewModel = QueueViewModel(leadRepository);
  final callingViewModel = CallingViewModel(
    callingRepository,
    leadRepository,
    reasonRepository,
    callLauncherService,
    callLogService,
  );
  final statsViewModel = StatsViewModel(callingRepository);

  final appRouter = AppRouter(authViewModel);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authViewModel),
        ChangeNotifierProvider.value(value: queueViewModel),
        ChangeNotifierProvider.value(value: callingViewModel),
        ChangeNotifierProvider.value(value: statsViewModel),
      ],
      child: OrvyqCallerApp(router: appRouter),
    ),
  );
}

class OrvyqCallerApp extends StatelessWidget {
  final AppRouter router;

  const OrvyqCallerApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router.router,
    );
  }
}
