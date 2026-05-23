// GENERATED CODE - DO NOT MODIFY BY HAND
// This is a stub file. Run `flutter packages pub run build_runner build`
// to generate the real adapter from fabric_item.dart.

part of 'fabric_item.dart';

class FabricItemAdapter extends TypeAdapter<FabricItem> {
  @override
  final int typeId = 0;

  @override
  FabricItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FabricItem(
      id: fields[0] as String,
      name: fields[1] as String,
      categoryKey: fields[2] as String,
      material: fields[3] as String,
      sku: fields[4] as String,
      isPublished: fields[5] as bool,
      isUserUploaded: fields[6] as bool,
      assetPath: fields[7] as String?,
      imageBytes: (fields[8] as List?)?.cast<int>(),
      colorTags: (fields[9] as List).cast<int>(),
      aiCompatScore: fields[10] as int,
      origin: fields[11] as String?,
      weaveType: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FabricItem obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.categoryKey)
      ..writeByte(3)
      ..write(obj.material)
      ..writeByte(4)
      ..write(obj.sku)
      ..writeByte(5)
      ..write(obj.isPublished)
      ..writeByte(6)
      ..write(obj.isUserUploaded)
      ..writeByte(7)
      ..write(obj.assetPath)
      ..writeByte(8)
      ..write(obj.imageBytes)
      ..writeByte(9)
      ..write(obj.colorTags)
      ..writeByte(10)
      ..write(obj.aiCompatScore)
      ..writeByte(11)
      ..write(obj.origin)
      ..writeByte(12)
      ..write(obj.weaveType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FabricItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
