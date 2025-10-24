import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:alarm_khamsat/common/color.dart';
import 'package:get/get.dart';
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
  // Separate inputs for time
  final TextEditingController hourCtrl = TextEditingController();
  final TextEditingController minuteCtrl = TextEditingController();
  bool isAm = true;

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
    final h12 = DateFormat('h');
    final m2 = DateFormat('mm');
    hourCtrl.text = h12.format(selectedDateTime);
    minuteCtrl.text = m2.format(selectedDateTime);
    isAm = selectedDateTime.hour < 12;
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
        // Sync separate inputs with selected time
        final h12 = DateFormat('h');
        final m2 = DateFormat('mm');
        hourCtrl.text = h12.format(selectedDateTime);
        minuteCtrl.text = m2.format(selectedDateTime);
        isAm = selectedDateTime.hour < 12;
      });
    }
  }

  bool _applySeparateInputs() {
    final now = DateTime.now();
    final hh = int.tryParse(hourCtrl.text.trim());
    final mm = int.tryParse(minuteCtrl.text.trim());
    if (hh == null || mm == null) return false;
    if (hh < 1 || hh > 12) return false;
    if (mm < 0 || mm > 59) return false;
    int hour24 = hh % 12; // 12 AM -> 0, 12 PM -> 12
    if (!isAm) hour24 += 12;
    var candidate = now.copyWith(hour: hour24, minute: mm, second: 0, millisecond: 0, microsecond: 0);
    if (candidate.isBefore(now)) candidate = candidate.add(const Duration(days: 1));
    setState(() => selectedDateTime = candidate);
    return true;
  }

  String getDayLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = selectedDateTime.difference(today).inDays;
    if (difference == 0) return 'today'.tr;
    if (difference == 1) return 'tomorrow'.tr;
    if (difference == 2) return 'after_tomorrow'.tr;
    return 'in_days'.trParams({'n': '$difference'});
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
              Text('edit_alarm'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            title: Text('repeat_every_day'.tr, style: const TextStyle(
                color: Colors.white
            ),),
            value: repeatEveryday,
            onChanged: (v) => setState(() => repeatEveryday = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: labelCtrl,
            decoration: InputDecoration(labelText: 'label'.tr),
          ),
          const SizedBox(height: 12),
          Text(getDayLabel(), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              // Hour input
              SizedBox(
                width: 72,
                child: TextField(
                  controller: hourCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  decoration: InputDecoration(labelText: 'hour'.tr),
                  onChanged: (_) => _applySeparateInputs(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              // Minute input
              SizedBox(
                width: 80,
                child: TextField(
                  controller: minuteCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  decoration: InputDecoration(labelText: 'minute'.tr),
                  onChanged: (_) => _applySeparateInputs(),
                ),
              ),
              const SizedBox(width: 8),
              // AM/PM toggle
              ToggleButtons(
                isSelected: [isAm, !isAm],
                onPressed: (index) {
                  setState(() => isAm = index == 0);
                  _applySeparateInputs();
                },
                direction: Axis.vertical,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white70,
                selectedColor: Colors.white,
                fillColor: AppColor.primaryColor,
                borderColor: AppColor.primaryColor,
                selectedBorderColor: AppColor.primaryColor,
                children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('am'.tr)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('pm'.tr)),
                ],
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: pickTime,
                style: ButtonStyle(side: WidgetStatePropertyAll(BorderSide(color: AppColor.primaryColor))),
                child: Text('pick_time'.tr, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(time, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('loop_alarm_audio'.tr, style: const TextStyle(
                color: Colors.white
            ),),
            value: loopAudio,
            onChanged: (v) => setState(() => loopAudio = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('vibrate'.tr,style: const TextStyle(
                color: Colors.white
            ),),
            value: vibrate,
            onChanged: (v) => setState(() => vibrate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('custom_volume'.tr, style: const TextStyle(
                color: Colors.white
            ),),
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
                    decoration: InputDecoration(labelText: 'fade_duration'.tr),
                    value: fadeDuration,
                    items: [
                      DropdownMenuItem(value: null, child: Text('no_fade'.tr)),
                      const DropdownMenuItem(value: Duration(seconds: 10), child: Text('10s')),
                      const DropdownMenuItem(value: Duration(seconds: 30), child: Text('30s')),
                      const DropdownMenuItem(value: Duration(minutes: 1), child: Text('1m')),
                    ],
                    onChanged: (val) => setState(() => fadeDuration = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('staircase_fade'.tr),
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
            decoration: InputDecoration(labelText: 'sound'.tr),
            items: [
              DropdownMenuItem(value: 'assets/mp3/marimba.mp3', child: Text('marimba'.tr, style: const TextStyle(color: Colors.black),)),
              DropdownMenuItem(value: 'assets/mp3/mozart.mp3', child: Text('mozart'.tr, style: const TextStyle(color: Colors.black))),
              DropdownMenuItem(value: 'assets/mp3/nokia.mp3', child: Text('nokia'.tr, style: const TextStyle(color: Colors.black))),
              DropdownMenuItem(value: 'assets/mp3/one_piece.mp3', child: Text('one_piece'.tr, style: const TextStyle(color: Colors.black))),
              DropdownMenuItem(value: 'assets/mp3/star_wars.mp3', child: Text('star_wars'.tr, style: const TextStyle(color: Colors.black))),
            ],
            onChanged: (val) => setState(() => assetAudio = val ?? assetAudio),
          ),
          const SizedBox(height: 8),
          // Row(
          //   children: [
          //     Expanded(
          //       child: Text(
          //         deviceAudioPath == null
          //             ? 'Device sound: none'
          //             : 'Device sound: ${deviceAudioPath!.split('/').last}',
          //         overflow: TextOverflow.ellipsis,
          //       ),
          //     ),
          //     const SizedBox(width: 8),
          //     OutlinedButton(
          //       onPressed: () async {
          //         final res = await FilePicker.platform.pickFiles(
          //           type: FileType.custom,
          //           allowedExtensions: const ['mp3', 'm4a', 'wav', 'ogg', 'aac'],
          //         );
          //         if (res != null && res.files.single.path != null) {
          //           setState(() => deviceAudioPath = res.files.single.path);
          //         }
          //       },
          //       child: const Text('Pick from device'),
          //     ),
          //   ],
          // ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(context, false),
                child: Text('cancel'.tr),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: loading ? null : save,
                child: Text(creating ? 'create'.tr : 'save'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
