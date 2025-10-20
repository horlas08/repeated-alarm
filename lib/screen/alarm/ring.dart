import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:alarm_khamsat/screen/alarm/alarm_store.dart';
import 'package:flutter/material.dart';

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({super.key, required this.alarmSettings});

  final AlarmSettings alarmSettings;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  StreamSubscription<AlarmSet>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Alarm.ringing.listen((alarms) {
      if (alarms.containsId(widget.alarmSettings.id)) return;
      _subscription?.cancel();
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(widget.alarmSettings.dateTime).format(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  const Text('Alarm ringing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(time, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(widget.alarmSettings.notificationSettings.title ?? 'Alarm'),
                ],
              ),
              const Text('🔔', style: TextStyle(fontSize: 64)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await Alarm.set(
                        alarmSettings: widget.alarmSettings.copyWith(
                          dateTime: DateTime.now().add(const Duration(minutes: 1)),
                        ),
                      );
                    },
                    child: const Text('Snooze'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final id = widget.alarmSettings.id;
                      final repeat = await AlarmStore.getRepeatEveryday(id);
                      await Alarm.stop(id);
                      if (repeat) {
                        final now = DateTime.now();
                        final target = now.copyWith(
                          hour: widget.alarmSettings.dateTime.hour,
                          minute: widget.alarmSettings.dateTime.minute,
                          second: 0,
                          millisecond: 0,
                          microsecond: 0,
                        );
                        final next = target.isAfter(now) ? target : target.add(const Duration(days: 1));
                        final nextSettings = widget.alarmSettings.copyWith(dateTime: next);
                        await Alarm.set(alarmSettings: nextSettings);
                        await AlarmStore.upsert(nextSettings, enabled: true, repeatEveryday: true);
                      }
                    },
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
