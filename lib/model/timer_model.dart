import 'dart:async';

class TimerModel {
  String id;
  String name;
  Duration total;
  Duration remaining;
  bool isRunning;
  Timer? _ticker;

  TimerModel({
    required this.id,
    required this.name,
    required this.total,
  })  : remaining = total,
        isRunning = false;

  void start(Function onTick, Function onDone) {
    if (isRunning) return;
    isRunning = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remaining.inSeconds <= 0) {
        stop();
        onDone();
      } else {
        remaining = remaining - const Duration(seconds: 1);
        onTick();
      }
    });
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    isRunning = false;
  }

  void reset() {
    pause();
    remaining = total;
  }

  void stop() => pause();

  void dispose() => _ticker?.cancel();
}
