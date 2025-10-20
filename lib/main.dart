import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:alarm_khamsat/screen/alarm/ring.dart';
import 'package:alarm_khamsat/common/color.dart';
import 'package:alarm_khamsat/screen/home.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/adapters.dart';
import 'model/clock_model.dart';
import 'package:easy_admob_ads_flutter/easy_admob_ads_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:alarm_khamsat/screen/alarm/alarm_store.dart';
import 'package:alarm_khamsat/screen/alarm/alarm_serialization.dart';
import 'package:hive/hive.dart';
import 'package:flutter/services.dart' as services;

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
bool _ringLaunchInProgress = false;

void _onNotificationResponse(NotificationResponse response) {
  final nav = _navKey.currentState;
  if (nav == null) return;
  final payload = response.payload ?? '';
  // Bring app to foreground and navigate to Home (Alarm tab is inside Home)
  if (payload == 'next_alarm') {
    // Just ensure we land on Home; user can see alarms page within the app UI
    if (nav.mounted) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Home()),
        (route) => route.isFirst,
      );
    }
  }
}

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidInit = AndroidInitializationSettings('notification_icon');
  final InitializationSettings init = const InitializationSettings(android: androidInit);
  await _fln.initialize(
    init,
    onDidReceiveNotificationResponse: _onNotificationResponse,
  );

  // Create a SILENT channel for full-screen intents so it won't play a one-shot sound
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'alarm_fullscreen_silent',
    'Alarms (Silent Fullscreen)',
    description: 'Alarm alerts (silent channel for full-screen UI)',
    importance: Importance.max,
    playSound: false,
    showBadge: true,
  );
  await _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Channel for persistent next-alarm notification (silent, ongoing)
  const AndroidNotificationChannel nextChannel = AndroidNotificationChannel(
    'next_alarm_ongoing',
    'Next Alarm',
    description: 'Shows the upcoming alarm',
    importance: Importance.defaultImportance,
    playSound: false,
    showBadge: false,
  );
  await _fln
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(nextChannel);
}

Future<void> _showFullScreenAlarmNotification(int id, String? title, String? body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'alarm_fullscreen_silent',
    'Alarms (Silent Fullscreen)',
    channelDescription: 'Alarm alerts (silent channel for full-screen UI)',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    autoCancel: false,
    ongoing: true,
    playSound: false,
    sound: null,
    enableVibration: false,
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  await _fln.show(id, title ?? 'Alarm', body ?? 'Alarm is ringing', details, payload: 'ringing');
}

Future<void> _showNextAlarmOngoingNotification(AlarmSettings s) async {
  final title = 'Next alarm';
  final body = '${s.notificationSettings.title ?? 'Alarm'} • ${DateFormat('h:mm a').format(s.dateTime)}';
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'next_alarm_ongoing',
    'Next Alarm',
    channelDescription: 'Shows the upcoming alarm',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    autoCancel: false,
    ongoing: true,
    onlyAlertOnce: true,
    playSound: false,
    enableVibration: false,
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  await _fln.show(999999, title, body, details, payload: 'next_alarm');
}

Future<void> _cancelNextAlarmOngoingNotification() async {
  await _fln.cancel(999999);
}

Future<void> _updateNextAlarmOngoingNotification() async {
  final stored = await AlarmStore.getAllRaw();
  final now = DateTime.now();
  final enabled = stored.where((e) => (e['enabled'] as bool?) ?? false);
  final future = enabled.map((e) => alarmSettingsFromMap(e)).where((s) => s.dateTime.isAfter(now)).toList();
  future.sort((a, b) => a.dateTime.compareTo(b.dateTime));
  if (future.isEmpty) {
    await _cancelNextAlarmOngoingNotification();
  } else {
    await _showNextAlarmOngoingNotification(future.first);
  }
}

Future<void> _maybePromptIgnoreBatteryOptimizations() async {
  try {
    final box = await Hive.openBox('app_prefs');
    final shown = box.get('battery_prompted') == true;
    if (shown) return;
    if (_navKey.currentContext == null) return;
    final ok = await showDialog<bool>(
      context: _navKey.currentContext!,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow background alarms'),
        content: const Text('To ensure alarms ring on time, allow the app to ignore battery optimizations.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (ok == true) {
      const method = services.MethodChannel('app.settings');
      await method.invokeMethod('requestIgnoreBatteryOptimizations');
    }
    await box.put('battery_prompted', true);
  } catch (_) {}
}

Future<void> _handleMissedAlarmsOnStartup() async {
  final now = DateTime.now();
  final stored = await AlarmStore.getAllRaw();
  for (final raw in stored) {
    final s = alarmSettingsFromMap(raw);
    final enabled = (raw['enabled'] as bool?) ?? false;
    final repeat = (raw['repeatEveryday'] as bool?) ?? false;
    if (!enabled) continue;
    if (s.dateTime.isBefore(now)) {
      if (repeat) {
        final target = now.copyWith(hour: s.dateTime.hour, minute: s.dateTime.minute, second: 0, millisecond: 0, microsecond: 0);
        final next = target.isAfter(now) ? target : target.add(const Duration(days: 1));
        final nextSettings = s.copyWith(dateTime: next);
        await Alarm.set(alarmSettings: nextSettings);
        await AlarmStore.upsert(nextSettings, enabled: true, repeatEveryday: true);
      } else {
        await AlarmStore.setEnabled(s.id, false);
      }
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();
  // Register Hive adapters
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(ClockModelAdapter());
  }
  AdHelper.setupAdLogging();
  AdIdRegistry.initialize(
    android: {
      AdType.banner: 'ca-app-pub-8878811467055102/1667252189',
    },
    ios: {
      AdType.banner: 'ca-app-pub-8878811467055102/1667252189',
    },
  );
  AdHelper.showAds = true;
  // Disable GDPR consent simulation to avoid triggering UMP on unsupported setups
  AdHelper.showConstentGDPR = false;
  try {
    await AdmobService().initialize();
  } catch (e) {
    // Continue without ads initialization if plugin is missing or not registered yet
    debugPrint('Admob init skipped: $e');
  }
  await Alarm.init();
  await _initLocalNotifications();
  // Listen globally for ringing to ensure UI opens regardless of current route
  Alarm.ringing.listen((AlarmSet set) async {
    if (set.alarms.isEmpty) return;
    final ringing = set.alarms.first;
    final nav = _navKey.currentState;
    if (nav == null) {
      // App not in memory: debounce and slightly delay to avoid keyguard race
      if (_ringLaunchInProgress) return;
      _ringLaunchInProgress = true;
      await Future.delayed(const Duration(milliseconds: 700));
      await _showFullScreenAlarmNotification(
        ringing.id,
        ringing.notificationSettings.title,
        ringing.notificationSettings.body,
      );
      // allow subsequent rings later
      Future.delayed(const Duration(seconds: 2), () => _ringLaunchInProgress = false);
      return;
    }
    // App is active: navigate directly, skip notification to avoid audio focus issues
    if (nav.mounted) {
      nav.push(
        MaterialPageRoute(builder: (_) => AlarmRingScreen(alarmSettings: ringing)),
      );
    }
  });
  // Update next-alarm ongoing notification whenever schedule changes
  Alarm.scheduled.listen((_) async {
    await _updateNextAlarmOngoingNotification();
  });
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  runApp(const MyApp());
  // Defer heavy tasks to after first frame to avoid slow cold start from notification tap
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _handleMissedAlarmsOnStartup();
    await _updateNextAlarmOngoingNotification();
    await _maybePromptIgnoreBatteryOptimizations();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      color: AppColor.primaryColor,
      navigatorKey: _navKey,
      
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColor.scafoldBgColor,
        primaryColor: Color(0xFFF0F757),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColor.bottomBgColor
        ),
        inputDecorationTheme: InputDecorationThemeData(
          fillColor: AppColor.offWhiteColor,
          filled: true,

          helperStyle: TextStyle(color: Colors.black),

          labelStyle: TextStyle(color: Colors.black),
          hintStyle:  TextStyle(color: Colors.black),
          counterStyle: TextStyle(
            color: Colors.black
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          border: OutlineInputBorder(borderRadius:  BorderRadius.circular(10),borderSide: BorderSide.none),
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: AppColor.primaryColor),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColor.bottomBgColor
        )
      ),
      home: Home(),
    );
  }
}

