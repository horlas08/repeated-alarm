import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:alarm_khamsat/common/color.dart';
import 'package:alarm_khamsat/common/widget/alarm_card.dart';
import 'package:alarm_khamsat/screen/alarm/edit_alarm_sheet.dart';
import 'package:alarm_khamsat/screen/alarm/ring.dart';
import 'package:alarm_khamsat/screen/alarm/alarm_store.dart';
import 'package:alarm_khamsat/screen/alarm/alarm_serialization.dart';
import 'package:alarm_khamsat/common/helper/permission_helper.dart';
import 'package:flutter/material.dart';
import 'package:easy_admob_ads_flutter/easy_admob_ads_flutter.dart';

class AlarmPage extends StatefulWidget {
  final ValueChanged<VoidCallback>? onRegisterAddHandler;
  const AlarmPage({super.key, this.onRegisterAddHandler});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmItem {
  final AlarmSettings settings;
  final bool enabled;
  _AlarmItem(this.settings, this.enabled);
}

class _AlarmPageState extends State<AlarmPage> {
  List<_AlarmItem> _alarms = [];
  StreamSubscription<AlarmSet>? _ringSub;
  StreamSubscription<AlarmSet>? _scheduledSub;
  bool _notifGranted = true;
  int _idSeed = 0;

  @override
  void initState() {
    super.initState();
    widget.onRegisterAddHandler?.call(_showAddMultipleBottomSheet);
    // Request notifications permission on Android 13+ and iOS
    PermissionHelper.ensureNotificationsPermission(context);
    _refreshNotifStatus();
    _loadAlarms();
    _ringSub = Alarm.ringing.listen(_onRingingChanged);
    _scheduledSub = Alarm.scheduled.listen((_) => _loadAlarms());
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    _scheduledSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAlarms() async {
    final scheduled = await Alarm.getAlarms();
    final scheduledById = {for (final a in scheduled) a.id: a};
    final storedRaw = await AlarmStore.getAllRaw();

    final Map<int, _AlarmItem> merged = {};
    for (final raw in storedRaw) {
      final id = raw['id'] as int;
      final settings = alarmSettingsFromMap(raw);
      final enabled = scheduledById.containsKey(id);
      merged[id] = _AlarmItem(settings, enabled);
    }
    for (final a in scheduled) {
      if (!merged.containsKey(a.id)) {
        merged[a.id] = _AlarmItem(a, true);
        await AlarmStore.upsert(a, enabled: true, repeatEveryday: false);
      }
    }

    final list = merged.values.toList()
      ..sort((a, b) => a.settings.dateTime.compareTo(b.settings.dateTime));
    if (!mounted) return;
    setState(() => _alarms = list);
  }

  Future<void> _refreshNotifStatus() async {
    final granted = await PermissionHelper.isNotificationsGranted();
    if (mounted) setState(() => _notifGranted = granted);
  }

  Future<int> _generateUniqueId() async {
    // Collect existing IDs from scheduled alarms and store
    final scheduled = await Alarm.getAlarms();
    final storedRaw = await AlarmStore.getAllRaw();
    final existing = <int>{
      ...scheduled.map((e) => e.id),
      ...storedRaw.map((e) => e['id'] as int),
    };
    // Keep within 32-bit signed int range required by plugin
    const int maxInt32 = 2147483647;
    int base = DateTime.now().millisecondsSinceEpoch % maxInt32;
    // Spread candidates by adding a small seed offset
    int candidate = (base + (_idSeed++ % 100000)) % maxInt32;
    if (candidate <= 0) candidate = 1;
    // Ensure uniqueness by linear probing with wraparound
    while (existing.contains(candidate)) {
      candidate = (candidate + 1) % maxInt32;
      if (candidate == 0) candidate = 1;
    }
    return candidate;
  }

  Future<void> _onRingingChanged(AlarmSet alarms) async {
    if (!mounted) return;
    if (alarms.alarms.isEmpty) return;
    final ringing = alarms.alarms.first;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlarmRingScreen(alarmSettings: ringing)),
    );
    unawaited(_loadAlarms());
  }

  Future<void> _toggleAlarm(AlarmSettings s, bool enable) async {
    if (enable) {
      // Use a copied settings instance to avoid any unintended shared references
      await Alarm.set(alarmSettings: s.copyWith(dateTime: s.dateTime));
      await AlarmStore.setEnabled(s.id, true);
    } else {
      await Alarm.stop(s.id);
      await AlarmStore.setEnabled(s.id, false);
    }
    await _loadAlarms();
  }

  Future<void> _deleteAlarm(AlarmSettings s) async {
    await Alarm.stop(s.id);
    await AlarmStore.remove(s.id);
    await _loadAlarms();
  }

  Future<void> _editAlarm(AlarmSettings? s) async {
    final res = await showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.bottomBgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: EditAlarmSheet(alarmSettings: s),
      ),
    );
    if (res == true) unawaited(_loadAlarms());
  }

  void _showAddMultipleBottomSheet() {
    final labelCtrl = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 7, minute: 0);
    final countCtrl = TextEditingController(text: '1');
    final intervalCtrl = TextEditingController(text: '5');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.bottomBgColor,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Alarms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                style: const TextStyle(color: Colors.black),
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedTime.format(ctx),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                      if (picked != null) {
                        selectedTime = picked;
                        (context as Element).markNeedsBuild();
                      }
                    },
                    child: const Text('Pick Time'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: countCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(labelText: 'How many alarms'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: intervalCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(labelText: 'Interval (minutes)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFFF0F757))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final first = now.copyWith(
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        second: 0,
                        millisecond: 0,
                        microsecond: 0,
                      );
                      final n = int.tryParse(countCtrl.text.trim()) ?? 1;
                      final interval = int.tryParse(intervalCtrl.text.trim()) ?? 5;
                      DateTime dt = first.isBefore(now) ? first.add(const Duration(days: 1)) : first;
                      for (int i = 0; i < n; i++) {
                        final id = await _generateUniqueId();
                        final s = AlarmSettings(
                          id: id,
                          dateTime: dt,
                          loopAudio: true,
                          vibrate: true,
                          assetAudioPath: 'assets/mp3/marimba.mp3',
                          volumeSettings: const VolumeSettings.fixed(),
                          notificationSettings: NotificationSettings(
                            title: labelCtrl.text.isEmpty ? 'Alarm' : labelCtrl.text,
                            body: 'Your alarm "${labelCtrl.text.isEmpty ? 'Alarm' : labelCtrl.text}" is scheduled',
                            stopButton: 'Stop',
                            icon: 'notification_icon',
                          ),
                          allowAlarmOverlap: true,
                        );
                        await Alarm.set(alarmSettings: s);
                        await AlarmStore.upsert(s, enabled: true, repeatEveryday: false);
                        dt = dt.add(Duration(minutes: interval));
                      }
                      if (context.mounted) Navigator.pop(ctx);
                      await _loadAlarms();
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Alarm', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          if (!_notifGranted)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications are disabled. Alarms may not alert visibly.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await PermissionHelper.openAppSettingsIfDenied();
                      await _refreshNotifStatus();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          const AdmobBannerAd(collapsible: true, height: 60),
          const SizedBox(height: 12),
          _alarms.isEmpty
              ? const Center(child: Text('No alarms yet'))
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _alarms.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.1,
                  ),
                  itemBuilder: (context, index) {
                    final item = _alarms[index];
                    final s = item.settings;
                    return Dismissible(
                      key: Key('alarm_${s.id}'),
                      direction: DismissDirection.horizontal,
                      background: Container(color: Colors.red.withOpacity(0.2)),
                      secondaryBackground: Container(color: Colors.red.withOpacity(0.2)),
                      onDismissed: (_) => _deleteAlarm(s),
                      child: AlarmCard(
                        key: ValueKey('card_${s.id}'),
                        settings: s,
                        enabled: item.enabled,
                        onToggle: (v) => _toggleAlarm(s, v),
                        onTap: () => _editAlarm(s),
                      ),
                    );
                  },
                ),

        ],
      ),
    );
  }
}
