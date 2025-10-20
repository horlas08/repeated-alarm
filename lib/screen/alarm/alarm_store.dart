import 'package:hive/hive.dart';

import 'alarm_serialization.dart';
import 'package:alarm/alarm.dart';

class AlarmStore {
  static const String _boxName = 'alarms_store';

  static Future<Box> _box() async {
    return await Hive.openBox(_boxName);
  }

  static Future<void> upsert(AlarmSettings s, {required bool enabled, bool repeatEveryday = false}) async {
    final box = await _box();
    await box.put(s.id.toString(), alarmSettingsToMap(s, enabled: enabled, repeatEveryday: repeatEveryday));
  }

  static Future<void> setEnabled(int id, bool enabled) async {
    final box = await _box();
    final existing = Map<String, dynamic>.from(box.get(id.toString()) ?? {});
    if (existing.isEmpty) return;
    existing['enabled'] = enabled;
    await box.put(id.toString(), existing);
  }

  static Future<void> remove(int id) async {
    final box = await _box();
    await box.delete(id.toString());
  }

  static Future<List<Map<String, dynamic>>> getAllRaw() async {
    final box = await _box();
    return box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>?> getRawById(int id) async {
    final box = await _box();
    final data = box.get(id.toString());
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<bool> getRepeatEveryday(int id) async {
    final raw = await getRawById(id);
    return (raw?['repeatEveryday'] as bool?) ?? false;
  }
}
