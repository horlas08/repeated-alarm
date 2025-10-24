// Flutter single-file app implementing:
// - Customizable Timer page (create multiple timers, start/pause/reset)
// - Stopwatch page (start/stop/lap/reset)
// - Clocks page (add many clocks with custom UTC offsets / city names)
//
// Usage: create a new Flutter project and replace lib/main.dart with this file.

import 'dart:async';
import 'package:alarm_khamsat/common/color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../model/clock_model.dart';

class StopwatchPage extends StatefulWidget {
  const StopwatchPage({super.key});

  @override
  State<StopwatchPage> createState() => _StopwatchPageState();
}

class _StopwatchPageState extends State<StopwatchPage> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final List<Duration> _laps = [];

  void _start() {
    if (_stopwatch.isRunning) return;
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) => setState(() {}));
  }

  void _stop() {
    _stopwatch.stop();
    _ticker?.cancel();
    setState(() {});
  }

  void _reset() {
    _stopwatch.reset();
    _laps.clear();
    _ticker?.cancel();
    setState(() {});
  }

  void _lap() {
    if (!_stopwatch.isRunning) return;
    _laps.insert(0, _stopwatch.elapsed);
    setState(() {});
  }

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = ((d.inMilliseconds.remainder(1000)) ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text('stopwatch_title'.tr)
              ],
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_format(elapsed), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(Colors.purple[100])
                        ),
                        onPressed: _stopwatch.isRunning ? _lap : null,
                        child: Text('lap'.tr),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(AppColor.primaryColor)
                        ),
                        onPressed: _stopwatch.isRunning ? _stop : _start,
                        child: Text(_stopwatch.isRunning ? 'stop'.tr : 'start'.tr),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(Colors.white)
                        ),
                        onPressed: _reset,
                        child:  Text('reset'.tr),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _laps.isEmpty
                  ? Center(child: Text('no_laps_yet'.tr))
                  : ListView.builder(
                itemCount: _laps.length,
                itemBuilder: (context, i) {
                  final lap = _laps[i];
                  return ListTile(
                    leading: Text('#${_laps.length - i}', style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold
                    ),),
                    title: Text(_format(lap),  style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold
                    ),),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}