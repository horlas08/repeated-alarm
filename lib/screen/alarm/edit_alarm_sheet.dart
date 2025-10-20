import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'alarm_store.dart';

class EditAlarmSheet extends StatefulWidget {
  const EditAlarmSheet({super.key, this.alarmSettings});

  final AlarmSettings? alarmSettings;

  @override
  State<EditAlarmSheet> createState() => _EditAlarmSheetState();
}

class _EditAlarmSheetState extends State<EditAlarmSheet> {
  bool loading = false;

  late bool creating;
  late DateTime selectedDateTime;
  late bool loopAudio;
  late bool vibrate;
  double? volume;
  Duration? fadeDuration;
  bool staircaseFade = false;
  late String assetAudio;
  String? deviceAudioPath;
  final TextEditingController labelCtrl = TextEditingController();
  bool repeatEveryday = false;

  @override
  void initState() {
    super.initState();
    creating = widget.alarmSettings == null;

    if (creating) {
      final now = DateTime.now().add(const Duration(minutes: 1));
      selectedDateTime = now.copyWith(second: 0, millisecond: 0, microsecond: 0);
      loopAudio = true;
      vibrate = true;
      volume = null; // custom volume off
      fadeDuration = null;
      staircaseFade = false;
      assetAudio = 'assets/mp3/marimba.mp3';
      labelCtrl.text = 'Alarm';
      repeatEveryday = false;
    } else {
      final s = widget.alarmSettings!;
      selectedDateTime = s.dateTime;
      loopAudio = s.loopAudio;
      vibrate = s.vibrate;
      volume = s.volumeSettings.volume;
      fadeDuration = s.volumeSettings.fadeDuration;
      staircaseFade = s.volumeSettings.fadeSteps.isNotEmpty;
      assetAudio = s.assetAudioPath;
      deviceAudioPath = null;
      labelCtrl.text = s.notificationSettings.title ?? 'Alarm';
      // Load persisted repeat flag
      // Note: this is async, but we can best-effort refresh after build using AlarmStore
      () async {
        final raw = await AlarmStore.getRawById(s.id);
        if (mounted && raw != null) {
          setState(() => repeatEveryday = (raw['repeatEveryday'] as bool?) ?? false);
        }
      }();
    }
  }

  Future<void> pickTime() async {
    final res = await showTimePicker(
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      context: context,
    );
    if (res != null) {
      setState(() {
        final now = DateTime.now();
        selectedDateTime = now.copyWith(
          hour: res.hour,
          minute: res.minute,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );
        if (selectedDateTime.isBefore(now)) {
          selectedDateTime = selectedDateTime.add(const Duration(days: 1));
        }
      });
    }
  }

  String getDayLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = selectedDateTime.difference(today).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference == 2) return 'After tomorrow';
    return 'In $difference days';
  }

  AlarmSettings buildSettings() {
    final id = creating ? DateTime.now().millisecondsSinceEpoch % 100000 + 1 : widget.alarmSettings!.id;

    final VolumeSettings volumeSettings;
    if (staircaseFade) {
      volumeSettings = VolumeSettings.staircaseFade(
        volume: volume,
        fadeSteps:  [
          VolumeFadeStep(Duration.zero, 0),
          VolumeFadeStep(Duration(seconds: 15), 0.1),
          VolumeFadeStep(Duration(seconds: 30), 0.5),
          VolumeFadeStep(Duration(seconds: 45), 1.0),
        ],
      );
    } else if (fadeDuration != null) {
      volumeSettings = VolumeSettings.fade(volume: volume, fadeDuration: fadeDuration!);
    } else {
      volumeSettings = VolumeSettings.fixed(volume: volume);
    }

    // Note: plugin version may only support assetAudioPath.
    // We fallback to assetAudio if a device file was chosen.
    return AlarmSettings(
      id: id,
      dateTime: selectedDateTime,
      loopAudio: loopAudio,
      vibrate: vibrate,
      assetAudioPath: assetAudio,
      volumeSettings: volumeSettings,
      allowAlarmOverlap: true,
      notificationSettings: NotificationSettings(
        title: labelCtrl.text.trim().isEmpty ? 'Alarm' : labelCtrl.text.trim(),
        body: 'Your alarm "${labelCtrl.text.trim().isEmpty ? 'Alarm' : labelCtrl.text.trim()}" is scheduled',
        stopButton: 'Stop the alarm',
        icon: 'notification_icon',
      ),
    );
  }

  Future<void> save() async {
    if (loading) return;
    setState(() => loading = true);
    final settings = buildSettings();
    if (deviceAudioPath != null) {
      // Graceful fallback notice: using assets until plugin supports file paths.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Using asset sound. Device file sounds depend on plugin support.')),
        );
      }
    }
    final ok = await Alarm.set(alarmSettings: settings);
    if (ok) {
      await AlarmStore.upsert(settings, enabled: true, repeatEveryday: repeatEveryday);
    }
    if (mounted) {
      setState(() => loading = false);
      if (ok) Navigator.pop(context, true);
    }
  }

  Future<void> delete() async {
    if (widget.alarmSettings == null) return;
    final id = widget.alarmSettings!.id;
    final ok = await Alarm.stop(id);
    await AlarmStore.remove(id);
    if (mounted && ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(selectedDateTime).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Edit Alarm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (!creating)
                IconButton(
                  onPressed: loading ? null : delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat every day'),
            value: repeatEveryday,
            onChanged: (v) => setState(() => repeatEveryday = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(getDayLabel(), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(time, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              ElevatedButton(onPressed: pickTime, child: const Text('Pick Time')),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Loop alarm audio'),
            value: loopAudio,
            onChanged: (v) => setState(() => loopAudio = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibrate'),
            value: vibrate,
            onChanged: (v) => setState(() => vibrate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom volume'),
            value: volume != null,
            onChanged: (v) => setState(() => volume = v ? 1.0 : null),
          ),
          if (volume != null) ...[
            Slider(
              value: volume!.clamp(0, 1),
              min: 0,
              max: 1,
              divisions: 10,
              label: (volume ?? 0).toStringAsFixed(2),
              onChanged: (val) => setState(() => volume = val),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Duration?>(
                    decoration: const InputDecoration(labelText: 'Fade duration'),
                    value: fadeDuration,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('No fade')),
                      DropdownMenuItem(value: Duration(seconds: 10), child: Text('10s')),
                      DropdownMenuItem(value: Duration(seconds: 30), child: Text('30s')),
                      DropdownMenuItem(value: Duration(minutes: 1), child: Text('1m')),
                    ],
                    onChanged: (val) => setState(() => fadeDuration = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Staircase fade'),
                    value: staircaseFade,
                    onChanged: (v) => setState(() => staircaseFade = v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: assetAudio,
            decoration: const InputDecoration(labelText: 'Sound'),
            items: const [
              DropdownMenuItem(value: 'assets/mp3/marimba.mp3', child: Text('Marimba')),
              DropdownMenuItem(value: 'assets/mp3/mozart.mp3', child: Text('Mozart')),
              DropdownMenuItem(value: 'assets/mp3/nokia.mp3', child: Text('Nokia')),
              DropdownMenuItem(value: 'assets/mp3/one_piece.mp3', child: Text('One Piece')),
              DropdownMenuItem(value: 'assets/mp3/star_wars.mp3', child: Text('Star Wars')),
            ],
            onChanged: (val) => setState(() => assetAudio = val ?? assetAudio),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  deviceAudioPath == null
                      ? 'Device sound: none'
                      : 'Device sound: ${deviceAudioPath!.split('/').last}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['mp3', 'm4a', 'wav', 'ogg', 'aac'],
                  );
                  if (res != null && res.files.single.path != null) {
                    setState(() => deviceAudioPath = res.files.single.path);
                  }
                },
                child: const Text('Pick from device'),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: loading ? null : save,
                child: Text(creating ? 'Create' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
