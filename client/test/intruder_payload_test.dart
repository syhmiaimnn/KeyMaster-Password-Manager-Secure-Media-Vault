import 'dart:convert';
import 'dart:typed_data';

import 'package:client/intruder_payload.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime moment = DateTime.fromMillisecondsSinceEpoch(1793000000000);

Uint8List jpegLike(int length) {
  // Starts like a JPEG, then bytes of every value.
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    ...List<int>.generate(length, (i) => i % 256),
  ]);
}

void main() {
  group('pack and unpack', () {
    test('the time, the count and the picture survive', () {
      final original = IntruderPayload(
        time: moment,
        failedCount: 6,
        jpeg: jpegLike(5000),
      );

      final back = IntruderPayload.unpack(original.pack());

      expect(back.time, moment);
      expect(back.failedCount, 6);
      expect(back.jpeg, original.jpeg);
      expect(back.isTest, isFalse);
    });

    test('a count of 0 is a test photo', () {
      final back = IntruderPayload.unpack(
        IntruderPayload(time: moment, failedCount: 0, jpeg: jpegLike(10)).pack(),
      );
      expect(back.isTest, isTrue);
    });

    test('an empty picture is kept as empty', () {
      final back = IntruderPayload.unpack(
        IntruderPayload(time: moment, failedCount: 5, jpeg: Uint8List(0)).pack(),
      );
      expect(back.jpeg, isEmpty);
      expect(back.failedCount, 5);
    });

    test('the first four bytes tell how long the header is', () {
      final packed =
          IntruderPayload(time: moment, failedCount: 5, jpeg: jpegLike(3)).pack();
      final headerLength = ByteData.sublistView(packed, 0, 4).getUint32(0);

      final header = jsonDecode(utf8.decode(packed.sublist(4, 4 + headerLength)))
          as Map<String, dynamic>;
      expect(header['t'], moment.millisecondsSinceEpoch);
      expect(header['n'], 5);
      expect(packed.length, 4 + headerLength + 3 + 3);
    });
  });

  group('damaged data is refused', () {
    test('too short', () {
      expect(
        () => IntruderPayload.unpack(Uint8List.fromList([0, 0, 0])),
        throwsFormatException,
      );
    });

    test('a header length of zero', () {
      expect(
        () => IntruderPayload.unpack(Uint8List.fromList([0, 0, 0, 0, 1, 2, 3])),
        throwsFormatException,
      );
    });

    test('a header that claims to be longer than the data', () {
      expect(
        () => IntruderPayload.unpack(Uint8List.fromList([0, 0, 0, 50, 1, 2])),
        throwsFormatException,
      );
    });

    test('a header that is far too long', () {
      final data = Uint8List(5000);
      ByteData.sublistView(data, 0, 4).setUint32(0, 4000);
      expect(() => IntruderPayload.unpack(data), throwsFormatException);
    });

    test('a header that is not JSON', () {
      final text = utf8.encode('not json at all');
      final data = Uint8List.fromList([0, 0, 0, text.length, ...text, 1, 2, 3]);
      expect(() => IntruderPayload.unpack(data), throwsFormatException);
    });

    test('a header with the wrong fields', () {
      final text = utf8.encode(jsonEncode({'t': 'yesterday', 'n': 5}));
      final data = Uint8List.fromList([0, 0, 0, text.length, ...text, 1]);
      expect(() => IntruderPayload.unpack(data), throwsFormatException);

      final list = utf8.encode('[1,2,3]');
      final data2 = Uint8List.fromList([0, 0, 0, list.length, ...list, 1]);
      expect(() => IntruderPayload.unpack(data2), throwsFormatException);
    });
  });
}
