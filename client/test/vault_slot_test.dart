import 'dart:convert';
import 'dart:typed_data';

import 'package:client/crypto_service.dart';
import 'package:client/vault_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final crypto = CryptoService();
  final wrapAad = utf8.encode('keymaster:v1:wrapped-vault-key');

  /// A wrapped key exactly as the app makes it for a real vault.
  Future<String> realWrap() async {
    final salt = crypto.randomBytes(WrapFormat.saltBytes);
    final wrapped = await crypto.encrypt(
      crypto.randomBytes(32),
      crypto.randomBytes(32),
      aad: wrapAad,
    );
    return WrapFormat.encode(salt, wrapped);
  }

  group('slot names', () {
    test('the real vault keeps the names earlier phases used', () {
      expect(VaultSlot.real.wrapKey, 'vault_wrapped_key');
      expect(VaultSlot.real.itemsKey, 'vault_items_encrypted');
      expect(VaultSlot.real.mediaDir, 'media_vault');
    });

    test('the decoy vault has its own names', () {
      expect(VaultSlot.decoy.wrapKey, 'vault2_wrapped_key');
      expect(VaultSlot.decoy.itemsKey, 'vault2_items_encrypted');
      expect(VaultSlot.decoy.mediaDir, 'media_vault_2');
    });

    test('no name is shared between the two vaults', () {
      final names = [
        for (final slot in VaultSlot.values) ...[
          slot.wrapKey,
          slot.itemsKey,
          slot.mediaDir,
        ],
      ];
      expect(names.toSet().length, names.length);
    });

    test('only the decoy slot says it is the decoy', () {
      expect(VaultSlot.real.isDecoy, isFalse);
      expect(VaultSlot.decoy.isDecoy, isTrue);
    });
  });

  group('wrap format', () {
    test('encode and decode agree', () {
      final salt = crypto.randomBytes(16);
      final text = WrapFormat.encode(salt, 'abc123');
      final back = WrapFormat.decode(text);

      expect(text.startsWith('v2.'), isTrue);
      expect(back, isNotNull);
      expect(back!.salt, salt);
      expect(back.wrapped, 'abc123');
    });

    test('text in the old format is not read as the new one', () {
      final legacy = base64Encode(crypto.randomBytes(60));
      expect(WrapFormat.decode(legacy), isNull);
    });

    test('damaged text gives null, not an error', () {
      expect(WrapFormat.decode('v2.onlyonepart'), isNull);
      expect(WrapFormat.decode('v2.a.b.c'), isNull);
      expect(WrapFormat.decode('v2.!!!notbase64!!!.xyz'), isNull);
      expect(WrapFormat.decode(''), isNull);
    });
  });

  group('filler looks like a real slot', () {
    test('a filler wrap has the same shape as a real one', () async {
      final real = await realWrap();
      final filler = SlotFiller.wrap(crypto.randomBytes);

      final realParts = real.split('.');
      final fillerParts = filler.split('.');

      expect(fillerParts.length, realParts.length);
      expect(fillerParts[0], realParts[0]);
      expect(fillerParts[1].length, realParts[1].length);
      expect(fillerParts[2].length, realParts[2].length);
      expect(filler.length, real.length);
    });

    test('a filler wrap reads in the real format, with the real sizes', () {
      final decoded = WrapFormat.decode(SlotFiller.wrap(crypto.randomBytes));

      expect(decoded, isNotNull);
      expect(decoded!.salt.length, WrapFormat.saltBytes);
      expect(base64Decode(decoded.wrapped).length, WrapFormat.wrappedBytes);
    });

    test('a real wrap is exactly the size the filler assumes', () async {
      final real = WrapFormat.decode(await realWrap())!;
      expect(base64Decode(real.wrapped).length, WrapFormat.wrappedBytes);
    });

    test('no PIN opens a filler wrap', () async {
      final filler = WrapFormat.decode(SlotFiller.wrap(crypto.randomBytes))!;
      await expectLater(
        crypto.decrypt(filler.wrapped, crypto.randomBytes(32), aad: wrapAad),
        throwsA(anything),
      );
    });

    test('two filler wraps differ', () {
      expect(
        SlotFiller.wrap(crypto.randomBytes),
        isNot(SlotFiller.wrap(crypto.randomBytes)),
      );
    });

    test('filler items are base64 and in the expected size range', () {
      for (var i = 0; i < 30; i++) {
        final text = SlotFiller.items(crypto.randomBytes);
        final length = base64Decode(text).length;
        expect(length, greaterThanOrEqualTo(SlotFiller.minItemsBytes));
        expect(
          length,
          lessThan(SlotFiller.minItemsBytes + SlotFiller.itemsSpread),
        );
      }
    });

    test('filler items are never the same twice', () {
      expect(
        SlotFiller.items(crypto.randomBytes),
        isNot(SlotFiller.items(crypto.randomBytes)),
      );
    });

    test('no key opens filler items', () async {
      final itemsAad = utf8.encode('keymaster:v1:vault-items');
      await expectLater(
        crypto.decrypt(
          SlotFiller.items(crypto.randomBytes),
          crypto.randomBytes(32),
          aad: itemsAad,
        ),
        throwsA(anything),
      );
    });
  });

  group('slot flags', () {
    test('an on value and an off value have the same length', () {
      final on = SlotFlags(true, crypto.randomBytes(32)).serialize();
      final off = SlotFlags(false, crypto.randomBytes(32)).serialize();
      expect(on.length, off.length);
    });

    test('they survive a round trip', () {
      final key = crypto.randomBytes(32);
      final back = SlotFlags.parse(SlotFlags(true, key).serialize());
      expect(back.decoyOn, isTrue);
      expect(back.decoyKey, key);

      final off = SlotFlags.parse(SlotFlags(false, key).serialize());
      expect(off.decoyOn, isFalse);
    });

    test('a key of the wrong size or other junk is refused', () {
      final short = jsonEncode({'d': 1, 'k': base64Encode(Uint8List(16))});
      expect(() => SlotFlags.parse(short), throwsFormatException);
      expect(() => SlotFlags.parse('[1,2]'), throwsFormatException);
      expect(
        () => SlotFlags.parse(jsonEncode({'d': 'yes', 'k': 'AA=='})),
        throwsFormatException,
      );
      expect(() => SlotFlags.parse('{"d":1}'), throwsFormatException);
    });
  });
}
