import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<void> ensureNotificationsPermission(BuildContext context) async {
    // Android 13+ and iOS require runtime notification permission.
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return;

    final req = await Permission.notification.request();
    if (!req.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications are disabled. Some alarm alerts may be silent.')),
        );
      }
    }
  }

  static Future<void> openAppSettingsIfDenied() async {
    await openAppSettings();
  }

  static Future<bool> isNotificationsGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited;
  }
}
