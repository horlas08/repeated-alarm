import 'package:hive/hive.dart';

part 'clock_model.g.dart';

@HiveType(typeId: 1)
class ClockModel {
  @HiveField(0)
  String id;

  @HiveField(1)
  String label;

  @HiveField(2)
  double utcOffset;

  ClockModel({required this.id, required this.label, required this.utcOffset});
}