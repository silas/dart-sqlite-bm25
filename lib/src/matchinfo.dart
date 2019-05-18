import 'dart:typed_data';

class Matchinfo {
  static Uint32List decode(Uint8List encoded, {Endian endian}) {
    if (encoded == null) throw ArgumentError.notNull('encodeded');
    if (endian == null) endian = Endian.host;

    final byteData = ByteData.view(
        encoded.buffer, encoded.offsetInBytes, encoded.lengthInBytes);

    if (byteData.lengthInBytes % 4 != 0) {
      throw ArgumentError('Must be divisible by 4: ${byteData.lengthInBytes}');
    }

    final length = byteData.lengthInBytes ~/ 4;
    final decoded = Uint32List(length);
    for (var i = 0; i < length; i++) {
      decoded[i] = byteData.getUint32(i * 4, endian);
    }

    return decoded;
  }

  static Uint8List encode(Uint32List decoded, {Endian endian}) {
    if (decoded == null) throw ArgumentError.notNull('decoded');
    if (endian == null) endian = Endian.host;

    final encoded = ByteData(decoded.length * 4);

    for (var i = 0; i < decoded.length; i++) {
      encoded.setUint32(i * 4, decoded[i], endian);
    }

    return Uint8List.view(encoded.buffer);
  }
}
