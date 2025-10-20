import 'package:alarm/alarm.dart';

Map<String, dynamic> alarmSettingsToMap(AlarmSettings s, {bool enabled = true, bool repeatEveryday = false}) {
  return {
    'id': s.id,
    'dateTime': s.dateTime.millisecondsSinceEpoch,
    'loopAudio': s.loopAudio,
    'vibrate': s.vibrate,
    'assetAudioPath': s.assetAudioPath,
    'volume': s.volumeSettings.volume,
    'fadeDurationMs': s.volumeSettings.fadeDuration?.inMilliseconds,
    'fadeSteps': s.volumeSettings.fadeSteps
        .map((e) => {'ms': e.time.inMilliseconds, 'vol': e.volume})
        .toList(),
    'title': s.notificationSettings.title,
    'body': s.notificationSettings.body,
    'stopButton': s.notificationSettings.stopButton,
    'icon': s.notificationSettings.icon,
    'allowAlarmOverlap': s.allowAlarmOverlap,
    'enabled': enabled,
    'repeatEveryday': repeatEveryday,
  };
}

AlarmSettings alarmSettingsFromMap(Map map) {
  final List<dynamic> stepsRaw = (map['fadeSteps'] as List?) ?? const [];
  final steps = stepsRaw
      .map((e) => VolumeFadeStep(Duration(milliseconds: (e['ms'] as int)), (e['vol'] as num).toDouble()))
      .toList();

  final double? volume = (map['volume'] as num?)?.toDouble();
  final int? fadeMs = map['fadeDurationMs'] as int?;

  final VolumeSettings vs = steps.isNotEmpty
      ? VolumeSettings.staircaseFade(volume: volume, fadeSteps: steps)
      : (fadeMs != null
          ? VolumeSettings.fade(volume: volume, fadeDuration: Duration(milliseconds: fadeMs))
          : VolumeSettings.fixed(volume: volume));

  return AlarmSettings(
    id: map['id'] as int,
    dateTime: DateTime.fromMillisecondsSinceEpoch(map['dateTime'] as int),
    loopAudio: map['loopAudio'] as bool? ?? true,
    vibrate: map['vibrate'] as bool? ?? true,
    assetAudioPath: map['assetAudioPath'] as String,
    volumeSettings: vs,
    notificationSettings: NotificationSettings(
      title: (map['title'] as String?) ?? 'Alarm',
      body: (map['body'] as String?) ?? '',
      stopButton: (map['stopButton'] as String?) ?? 'Stop',
      icon: (map['icon'] as String?) ?? 'notification_icon',
    ),
    allowAlarmOverlap: map['allowAlarmOverlap'] as bool? ?? true,
  );
}
