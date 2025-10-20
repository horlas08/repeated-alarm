import 'package:alarm_khamsat/common/color.dart';
import 'package:flutter/material.dart';
import 'package:easy_admob_ads_flutter/easy_admob_ads_flutter.dart';

import '../../model/timer_model.dart';

class TimerPage extends StatefulWidget {
  final ValueChanged<VoidCallback>? onRegisterAddHandler;
  const TimerPage({super.key, this.onRegisterAddHandler});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  final List<TimerModel> _timers = [];

  @override
  void initState() {
    super.initState();
    // Provide Home with a function to open this page's add dialog
    widget.onRegisterAddHandler?.call(_addTimerDialog);
  }

  @override
  void dispose() {
    for (var t in _timers) t.dispose();
    super.dispose();
  }

  void _addTimerDialog() async {
    final nameController = TextEditingController(text: 'Timer ${_timers.length + 1}');
    int minutes = 0;
    int seconds = 30;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: TextStyle(
                    color: Colors.black
                ),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '0',
                      style: TextStyle(
                          color: Colors.black
                      ),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                      onChanged: (v) => minutes = int.tryParse(v) ?? 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: '30',
                      style: TextStyle(
                        color: Colors.black
                      ),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Seconds'),
                      onChanged: (v) => seconds = int.tryParse(v) ?? 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Tip: Use minutes and seconds to set duration.'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(
                      color: Color(0xFFF0F757)
                    ),),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final total = Duration(minutes: minutes, seconds: seconds);
                      if (total.inSeconds <= 0) return; // ignore
                      final model = TimerModel(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        total: total,
                      );
                      setState(() => _timers.add(model));
                      Navigator.pop(context);
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours.toString().padLeft(2, '0');
    return d.inHours > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: _timers.isEmpty
          ? const Center(child: Text('No timers yet. Tap + to add.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _timers.length,
              itemBuilder: (context, i) {
                final t = _timers[i];
                return Card(
                  color: AppColor.bottomBgColor,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(t.name, style: TextStyle(
                      color: Colors.white
                    ),),
                    subtitle: Text(_formatDuration(t.remaining),  style: TextStyle(
                        color: Color(0xFFF0F757)
                    ),),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: t.isRunning ? 'Pause' : 'Start',
                        icon: Icon(t.isRunning ? Icons.pause : Icons.play_arrow,color: Colors.white,),
                        onPressed: () {
                          setState(() {
                            if (t.isRunning) {
                              t.pause();
                            } else {
                              t.start(() => setState(() {}), () {
                                // On done
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${t.name} finished')),
                                );
                              });
                            }
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Reset',
                        icon: const Icon(Icons.replay, color: Color(0xFFF0F757),),
                        onPressed: () => setState(() => t.reset()),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') {
                            t.dispose();
                            setState(() => _timers.removeAt(i));
                          }
                        },
                        color: Colors.white,
                        iconColor: Colors.white,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ]),
                  ),
                );
              },
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
}
