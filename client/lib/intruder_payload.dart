import 'dart:convert';
import 'dart:typed_data';

/// What is locked inside one intruder photo file: a small header (when it was
/// taken and how many wrong PINs came before it) followed by the JPEG.
///
/// Layout: 4 bytes header length (big endian) + header JSON + JPEG bytes.
/// The time is inside the locked data on purpose, so the file name tells
/// nothing.
class IntruderPayload {
  final DateTime time;

  /// Wrong PINs counted when the photo was taken. 0 for a test photo.
  final int failedCount;
  final Uint8List jpeg;

  const IntruderPayload({
    required this.time,
    required this.failedCount,
    required this.jpeg,
  });

  bool get isTest => failedCount == 0;

  static const int _maxHeaderBytes = 1024;

  Uint8List pack() {
    final header = utf8.encode(
      jsonEncode({'t': time.millisecondsSinceEpoch, 'n': failedCount}),
    );
    final length = ByteData(4)..setUint32(0, header.length, Endian.big);
    final out = BytesBuilder(copy: false)
      ..add(length.buffer.asUint8List())
      ..add(header)
      ..add(jpeg);
    return out.takeBytes();
  }

  /// Throws [FormatException] if [data] was not made by [pack].
  static IntruderPayload unpack(Uint8List data) {
    if (data.length < 4) {
      throw const FormatException('The photo data is too short.');
    }
    final length = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.big);
    if (length == 0 || length > _maxHeaderBytes || data.length < 4 + length) {
      throw const FormatException('The photo header is not valid.');
    }

    Object? header;
    try {
      header = jsonDecode(utf8.decode(data.sublist(4, 4 + length)));
    } on FormatException {
      throw const FormatException('The photo header is not valid.');
    }
    if (header is! Map<String, dynamic>) {
      throw const FormatException('The photo header is not valid.');
    }
    final t = header['t'];
    final n = header['n'];
    if (t is! int || n is! int) {
      throw const FormatException('The photo header is not valid.');
    }

    return IntruderPayload(
      time: DateTime.fromMillisecondsSinceEpoch(t),
      failedCount: n,
      jpeg: Uint8List.sublistView(data, 4 + length),
    );
  }
}
