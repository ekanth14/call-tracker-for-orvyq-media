import 'package:permission_handler/permission_handler.dart';

class PermissionStatusReport {
  final bool phoneGranted;
  final bool notificationsGranted;
  final bool batteryOptimizationIgnored;

  PermissionStatusReport({
    required this.phoneGranted,
    required this.notificationsGranted,
    required this.batteryOptimizationIgnored,
  });

  bool get allEssentialGranted => phoneGranted;
}

class PermissionService {
  Future<PermissionStatusReport> checkPermissions() async {
    final phone = await Permission.phone.isGranted;
    final notifications = await Permission.notification.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;

    return PermissionStatusReport(
      phoneGranted: phone,
      notificationsGranted: notifications,
      batteryOptimizationIgnored: battery,
    );
  }

  Future<bool> requestPhonePermission() async {
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> requestBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }
}
