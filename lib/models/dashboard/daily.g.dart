// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DailyItemAdapter extends TypeAdapter<DailyItem> {
  @override
  final int typeId = 0;

  @override
  DailyItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyItem(
      title: fields[0] as String,
      hour: fields[1] as int?,
      minute: fields[2] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, DailyItem obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.hour)
      ..writeByte(2)
      ..write(obj.minute);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
