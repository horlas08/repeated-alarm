import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_admob_ads_flutter/easy_admob_ads_flutter.dart';
import 'package:hive/hive.dart';

import '../../model/clock_model.dart';
import '../../common/color.dart';

class ClocksPage extends StatefulWidget {
  final ValueChanged<VoidCallback>? onRegisterAddHandler;
  const ClocksPage({super.key, this.onRegisterAddHandler});

  @override
  State<ClocksPage> createState() => _ClocksPageState();
}

class _ClocksPageState extends State<ClocksPage> {
  final List<ClockModel> _clocks = [];
  Timer? _ticker;
  late Box<ClockModel> _clockBox;

  static const String _boxName = 'clocks';
  static const String _localId = 'local';

  @override
  void initState() {
    super.initState();
    _openAndLoad();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Provide Home with a function to open this page's add dialog
    widget.onRegisterAddHandler?.call(_addClockDialog);
  }

  Future<void> _openAndLoad() async {
    // Box should already be opened in main.dart, but be safe:
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<ClockModel>(_boxName);
    }
    _clockBox = Hive.box<ClockModel>(_boxName);
    _loadClocksFromBox();
  }

  void _loadClocksFromBox() {
    final saved = _clockBox.values.toList();

    _clocks.clear();
    _clocks.addAll(saved);

    // Ensure first clock is always the local clock (non-deletable).
    // If local clock doesn't exist, insert it at index 0.
    final systemOffset = DateTime.now().timeZoneOffset.inHours.toDouble();
    if (_clocks.isEmpty || _clocks.first.id != _localId) {
      final localClock = ClockModel(
        id: _localId,
        label: 'Local',
        utcOffset: systemOffset,
      );

      // If there is an existing item with id 'local' somewhere else, remove it first.
      _clocks.removeWhere((c) => c.id == _localId);

      _clocks.insert(0, localClock);
      _saveClocksToBox();
    } else {
      // Update local clock's offset to match current system timezone (keeps local accurate)
      _clocks[0].utcOffset = systemOffset;
      _saveClocksToBox();
    }

    setState(() {});
  }

  void _saveClocksToBox() {
    // Simple strategy: clear and re-add in order to preserve list order.
    _clockBox.clear();
    for (final c in _clocks) {
      _clockBox.add(c);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime _nowFor(ClockModel c) {
    if (c.id == _localId) return DateTime.now();
    final utc = DateTime.now().toUtc();
    final hours = c.utcOffset.truncate();
    final minutes = ((c.utcOffset - hours) * 60).round();
    return utc.add(Duration(hours: hours, minutes: minutes));
  }

  String _formatTime(DateTime dt, {bool showSec = false}) {
    final h = dt.hourOf12().toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return showSec ? '$h:$m:$s' : '$h:$m';
  }

  String _amPm(DateTime dt) => dt.hour >= 12 ? 'PM' : 'AM';

  void _addClockDialog() {
    final labelCtrl = TextEditingController();
    final offsetCtrl = TextEditingController(text: '0');
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) {
        final labelCtrl = TextEditingController();
        final offsetCtrl = TextEditingController(text: '0');

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
          height: 300,
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                style: TextStyle(
                    color: Colors.black
                ),
                decoration: const InputDecoration(labelText: 'Label (City)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: offsetCtrl,
                style: TextStyle(
                    color: Colors.black
                ),
                decoration: const InputDecoration(
                  labelText: 'UTC offset (hours). e.g. -5, 1, 5.5',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: For local time use label "Local" and offset 0 (already added).',
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  final label = labelCtrl.text.isEmpty ? 'Clock ${_clocks.length + 1}' : labelCtrl.text;
                  final offset = double.tryParse(offsetCtrl.text) ?? 0.0;
                  final model = ClockModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    label: label,
                    utcOffset: offset,
                  );
                  setState(() {
                    _clocks.add(model);
                    _saveClocksToBox();
                  });
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: true,
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView.builder(
          itemCount: _clocks.length,
          itemBuilder: (context, i) {
            final c = _clocks[i];
            final now = _nowFor(c);

            // First item (index 0) is Local clock and must not be dismissible
            if (i == 0) {
              return _buildClockCard(c, now, isLocal: true);
            }

            // Other clocks are dismissible
            return Dismissible(
              key: Key(c.id),
              direction: DismissDirection.horizontal,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (direction) {
                setState(() {
                  _clocks.removeAt(i);
                  _saveClocksToBox();
                });
                ScaffoldMessenger.of(context).removeCurrentSnackBar();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${c.label} removed')));
              },
              child: _buildClockCard(c, now),
            );
          },
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: AdmobBannerAd(collapsible: true, height: 60),
        ),
      ),
    );
  }

  Widget _buildClockCard(ClockModel c, DateTime now, {bool isLocal = false}) {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColor.bottomBgColor,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                c.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isLocal
                    ? 'Local device time'
                    : 'UTC ${c.utcOffset >= 0 ? '+' : ''}${c.utcOffset}',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(now, showSec: false),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 36,
                ),
              ),
              const SizedBox(height: 2),
              Text(_amPm(now), style: const TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

}

extension _HourOf12 on DateTime {
  /// Convert 0..23 to 1..12 (12-hour clock with 12 for midnight/noon)
  int hourOf12() {
    final h = this.hour % 12;
    return h == 0 ? 12 : h;
  }
}
