import 'package:alarm/alarm.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';

import '../color.dart';

class AlarmCard extends StatelessWidget {
  const AlarmCard({
    super.key,
    required this.settings,
    required this.enabled,
    required this.onToggle,
    required this.onTap,
  });

  final AlarmSettings settings;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  String _formatTime(BuildContext context) {
    final t = TimeOfDay.fromDateTime(settings.dateTime);
    return t.format(context);
  }

  String _label() {
    final title = settings.notificationSettings.title;
    return title.isNotEmpty ? title : 'Alarm';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
        height: 177,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColor.bottomBgColor,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoSizeText(_label(), maxLines: 1,),
            const SizedBox(height: 10),
            AutoSizeText(
              _formatTime(context),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 36,
              ),
              maxLines: 1,
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                height: 24,
                width: 40,
                child: FlutterSwitch(
                  value: enabled,
                  activeColor: AppColor.primaryColor,
                  borderRadius: 20.5,
                  showOnOff: false,
                  onToggle: onToggle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
