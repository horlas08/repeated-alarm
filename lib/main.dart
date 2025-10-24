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
import 'package:get/get.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
bool _ringLaunchInProgress = false;
final DateTime _appStartTime = DateTime.now();

void _onNotificationResponse(NotificationResponse response) {
  final nav = _navKey.currentState;
  if (nav == null) return;
  final payload = response.payload ?? '';
  // Bring app to foreground and navigate to Home (Alarm tab is inside Home)
  if (payload == 'next_alarm' || payload == 'ring_heads_up') {
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

  // Channel for heads-up alarm (silent, high priority, no fullScreenIntent)
  const AndroidNotificationChannel headsUpChannel = AndroidNotificationChannel(
    'alarm_heads_up',
    'Alarms (Heads-up Silent)'
    , description: 'Heads-up alarm alert without fullscreen',
    importance: Importance.high,
    playSound: false,
    showBadge: false,
  );
  await _fln
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(headsUpChannel);
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

Future<void> _showHeadsUpAlarmNotification(int id, String? title, String? body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'alarm_heads_up',
    'Alarms (Heads-up Silent)',
    channelDescription: 'Heads-up alarm alert without fullscreen',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    autoCancel: false,
    ongoing: true,
    playSound: false,
    sound: null,
    enableVibration: false,
    onlyAlertOnce: true,
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  await _fln.show(id, title ?? 'Alarm', body ?? 'Alarm is ringing', details, payload: 'ring_heads_up');
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
      // Grace window: avoid touching alarms within the last 5 minutes so we don't stop an active ring
      final delta = now.difference(s.dateTime);
      if (delta < const Duration(minutes: 5)) {
        continue;
      }
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
      // App not in memory: avoid launching UI/notifications to keep audio looping reliably while sleeping
      return;
    }
    // App is active: avoid immediate UI push right after cold start to protect looping
    final sinceStart = DateTime.now().difference(_appStartTime);
    if (sinceStart < const Duration(seconds: 5)) {
      // Within suppression window; keep looping without UI
      return;
    }
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

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en_US': {
          'alarm': 'Alarm',
          'add_alarms': 'Add Alarms',
          'label_optional': 'Label (optional)',
          'pick_time': 'Pick time',
          'how_many_alarms': 'How many alarms',
          'interval_minutes': 'Interval (minutes)',
          'cancel': 'Cancel',
          'create': 'Create',
          'save': 'Save',
          'open_settings': 'Open Settings',
          'no_alarms_yet': 'No alarms yet',
          'notifications_are_disabled_alarms_may_not_alert_visibly': 'Notifications are disabled, alarms may not alert visibly',
          'am': 'AM',
          'pm': 'PM',
          'edit_alarm': 'Edit Alarm',
          'repeat_every_day': 'Repeat every day',
          'label': 'Label',
          'hour': 'Hour',
          'minute': 'Minute',
          'loop_alarm_audio': 'Loop alarm audio',
          'vibrate': 'Vibrate',
          'custom_volume': 'Custom volume',
          'fade_duration': 'Fade duration',
          'no_fade': 'No fade',
          'staircase_fade': 'Staircase fade',
          'sound': 'Sound',
          'marimba': 'Marimba',
          'mozart': 'Mozart',
          'nokia': 'Nokia',
          'one_piece': 'One Piece',
          'star_wars': 'Star Wars',
          'today': 'Today',
          'tomorrow': 'Tomorrow',
          'after_tomorrow': 'After tomorrow',
          'in_days': 'In @n days',
          // Stopwatch
          'stopwatch_title': 'Stopwatch',
          'lap': 'Lap',
          'your_alarm': 'Your alarm',
          'is_scheduled': 'is scheduled',
          'label_optional': 'Label (optional)',
          'start': 'Start',
          'stop': 'Stop',
          'reset': 'Reset',
          'no_laps_yet': 'No laps yet',
          // Timer
          'add_timer': 'Add Timer',
          'name': 'Name',
          'minutes': 'Minutes',
          'seconds': 'Seconds',
          'timer_tip': 'Tip: Use minutes and seconds to set duration.',
          'add': 'Add',
          'no_timers_yet': 'No timers yet. Tap + to add.',
          'timer_finished': '@name finished',
          'delete': 'Delete',
          'pause': 'Pause',
          // Clock
          'label_city': 'Label (City)',
          'utc_offset_hint': 'UTC offset (hours). e.g. -5, 1, 5.5',
          'clock_tip': 'Tip: For local time use label "Local" and offset 0 (already added).',
          'clock_n': 'Clock @n',
          'clock_removed': '@label removed',
          'local_device_time': 'Local device time',
          // Bottom nav and quick actions
          'nav_alarm': 'Alarm',
          'nav_clock': 'Clock',
          'nav_timer': 'Timer',
          'repeat_alarm': 'Repeat Alarm',
          'nav_stopwatch': 'Stopwatch',
          'no_quick_action': 'No quick action available',
          'switch_to_clock_or_timer': 'Switch to Clock or Timer to add new items.',
        },
        'ar_EG': {
          'alarm': 'منبه',
          'add_alarms': 'إضافة منبهات',
          'label_optional': 'العنوان (اختياري)',
          'pick_time': 'اختر الوقت',
          'how_many_alarms': 'عدد المنبهات',
          'interval_minutes': 'الفاصل (دقائق)',
          'cancel': 'إلغاء',
          'create': 'إنشاء',
          'save': 'حفظ',
          'is_scheduled': 'ومن المقرر',
          'label_optional': 'التسمية (اختياري)',
          'your_alarm': 'المنبه الخاص بك',
          'open_settings': 'افتح الإعدادات',
          'no_alarms_yet': 'لا توجد منبهات بعد',
          'notifications_are_disabled_alarms_may_not_alert_visibly': 'الإشعارات معطّلة، قد لا يظهر تنبيه المنبه بوضوح',
          'am': 'ص',
          'pm': 'م',
          'edit_alarm': 'تعديل المنبه',
          'repeat_every_day': 'تكرار كل يوم',
          'label': 'العنوان',
          'hour': 'ساعة',
          'minute': 'دقيقة',
          'loop_alarm_audio': 'تكرار صوت المنبه',
          'vibrate': 'اهتزاز',
          'custom_volume': 'مستوى صوت مخصص',
          'fade_duration': 'مدة التلاشي',
          'no_fade': 'بدون تلاشي',
          'staircase_fade': 'تلاشي متدرج',
          'sound': 'النغمة',
          'marimba': 'ماريمبا',
          'mozart': 'موزارت',
          'nokia': 'نوكيا',
          'one_piece': 'ون بيس',
          'star_wars': 'حرب النجوم',
          'today': 'اليوم',
          'tomorrow': 'غداً',
          'after_tomorrow': 'بعد غد',
          'in_days': 'بعد @n يوم',
          // Stopwatch
          'stopwatch_title': 'ساعة الإيقاف',
          'lap': 'لفة',
          'start': 'بدء',
          'stop': 'إيقاف',
          'reset': 'إعادة تعيين',
          'no_laps_yet': 'لا توجد لفات بعد',
          // Timer
          'add_timer': 'إضافة مؤقت',
          'name': 'الاسم',
          'minutes': 'الدقائق',
          'seconds': 'الثواني',
          'timer_tip': 'نصيحة: استخدم الدقائق والثواني لتحديد المدة.',
          'add': 'إضافة',
          'no_timers_yet': 'لا توجد مؤقتات بعد. اضغط + للإضافة.',
          'timer_finished': 'انتهى @name',
          'delete': 'حذف',
          'pause': 'إيقاف مؤقت',
          // Clock
          'label_city': 'التسمية (المدينة)',
          'utc_offset_hint': 'فرق التوقيت عن UTC (ساعات). مثال: -5، 1، 5.5',
          'clock_tip': 'نصيحة: للوقت المحلي استخدم التسمية "محلي" والإزاحة 0 (مضافة مسبقًا).',
          'clock_n': 'الساعة @n',
          'clock_removed': 'تمت إزالة @label',
          'local_device_time': 'وقت الجهاز المحلي',
          // Bottom nav and quick actions
          'nav_alarm': 'منبه',
          'nav_clock': 'ساعة',
          'nav_timer': 'مؤقت',
          'repeat_alarm': 'كرر التنبيه',
          'nav_stopwatch': 'ساعة الإيقاف',
          'no_quick_action': 'لا يوجد إجراء سريع متاح',
          'switch_to_clock_or_timer': 'انتقل إلى صفحة الساعة أو المؤقت لإضافة عناصر جديدة.',
        },
      };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'repeat_alarm'.tr,
      debugShowCheckedModeBanner: false,
      color: AppColor.primaryColor,
      navigatorKey: _navKey,
      translations: AppTranslations(),
      locale: Get.deviceLocale ?? const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      
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

