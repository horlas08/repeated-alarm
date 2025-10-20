// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clock_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClockModelAdapter extends TypeAdapter<ClockModel> {
  @override
  final int typeId = 1;

  @override
  ClockModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ClockModel(
      id: fields[0] as String,
      label: fields[1] as String,
      utcOffset: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ClockModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.utcOffset);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
