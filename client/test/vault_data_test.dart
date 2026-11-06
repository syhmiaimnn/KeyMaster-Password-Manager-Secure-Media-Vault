import 'dart:convert';

import 'package:client/photo_folder.dart';
import 'package:client/vault_data.dart';
import 'package:client/vault_item.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime day = DateTime.utc(2026, 11, 6, 12);

PhotoFolder folder(
  String id,
  String name, {
  bool requiresPin = false,
  int colorIndex = 0,
}) {
  return PhotoFolder(
    id: id,
    name: name,
    key: base64Encode(List<int>.filled(32, 7)),
    requiresPin: requiresPin,
    colorIndex: colorIndex,
    createdAt: day,
  );
}

VaultItem login(String id, String title) {
  return VaultItem(
    id: id,
    type: 'Password',
    title: title,
    username: 'luqman',
    password: 'Correct-Horse-9',
    createdAt: day,
  );
}

VaultItem photo(String id, String folderId) {
  return VaultItem(
    id: id,
    type: 'Media',
    title: 'Photo',
    mediaPath: '$id.enc',
    mimeType: 'image/jpeg',
    sizeBytes: 1234,
    fileKey: 'k2.abc',
    folderId: folderId,
    createdAt: day,
  );
}

void main() {
  group('VaultData', () {
    test('empty text is an empty vault', () {
      final data = VaultData.deserialize('');
      expect(data.items, isEmpty);
      expect(data.folders, isEmpty);
    });

    test('items and folders survive a round trip', () {
      final original = VaultData(
        [login('a', 'Mail'), photo('p1', 'f1')],
        [folder('f1', 'Holiday', requiresPin: true, colorIndex: 4)],
      );

      final back = VaultData.deserialize(original.serialize());

      expect(back.items.length, 2);
      expect(back.items.first.title, 'Mail');
      expect(back.items.last.folderId, 'f1');
      expect(back.items.last.fileKey, 'k2.abc');
      expect(back.folders.length, 1);
      expect(back.folders.first.id, 'f1');
      expect(back.folders.first.name, 'Holiday');
      expect(back.folders.first.requiresPin, isTrue);
      expect(back.folders.first.colorIndex, 4);
      expect(back.folders.first.key, original.folders.first.key);
      expect(back.folders.first.createdAt, day);
    });

    test('the saved text is marked as version 2', () {
      final decoded =
          jsonDecode(VaultData(const [], const []).serialize()) as Map<String, dynamic>;
      expect(decoded['v'], 2);
      expect(decoded['items'], isEmpty);
      expect(decoded['folders'], isEmpty);
    });

    test('a vault saved by Phase 5 (a plain list) still opens', () {
      final legacy = VaultItem.serializeList([login('a', 'Mail'), login('b', 'Bank')]);

      final data = VaultData.deserialize(legacy);

      expect(data.items.map((item) => item.title), ['Mail', 'Bank']);
      expect(data.folders, isEmpty);
    });

    test('a map without folders still opens', () {
      final text = jsonEncode({
        'v': 2,
        'items': [login('a', 'Mail').toJson()],
      });

      final data = VaultData.deserialize(text);

      expect(data.items.length, 1);
      expect(data.folders, isEmpty);
    });

    test('an unknown format is refused', () {
      expect(() => VaultData.deserialize('"hello"'), throwsFormatException);
      expect(() => VaultData.deserialize('42'), throwsFormatException);
    });
  });

  group('PhotoFolder', () {
    test('keeps its values through JSON', () {
      final original = folder('f1', 'Family', requiresPin: true, colorIndex: 2);
      final back = PhotoFolder.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(back.id, 'f1');
      expect(back.name, 'Family');
      expect(back.requiresPin, isTrue);
      expect(back.colorIndex, 2);
      expect(back.keyBytes.length, 32);
    });

    test('a colour number outside the range is brought back into it', () {
      for (final number in [99, -1, 6, 1000]) {
        final json = folder('f1', 'A').toJson()..['colorIndex'] = number;
        final colour = PhotoFolder.fromJson(json).colorIndex;
        expect(colour, inInclusiveRange(0, PhotoFolder.colorCount - 1), reason: '$number');
      }
    });

    test('copyWith changes only what it is told to', () {
      final original = folder('f1', 'A');
      final changed = original.copyWith(name: 'B', requiresPin: true, colorIndex: 5);

      expect(changed.id, original.id);
      expect(changed.key, original.key);
      expect(changed.createdAt, original.createdAt);
      expect(changed.name, 'B');
      expect(changed.requiresPin, isTrue);
      expect(changed.colorIndex, 5);
    });

    test('validateName', () {
      final others = [folder('f1', 'Holiday')];

      expect(PhotoFolder.validateName('', others), 'Give the folder a name.');
      expect(PhotoFolder.validateName('   ', others), 'Give the folder a name.');
      expect(
        PhotoFolder.validateName('x' * (PhotoFolder.maxNameLength + 1), others),
        'Use at most ${PhotoFolder.maxNameLength} characters.',
      );
      expect(
        PhotoFolder.validateName('holiday', others),
        'A folder with this name already exists.',
      );
      expect(
        PhotoFolder.validateName('  HOLIDAY  ', others),
        'A folder with this name already exists.',
      );
      expect(PhotoFolder.validateName('Work', others), isNull);
      expect(
        PhotoFolder.validateName('x' * PhotoFolder.maxNameLength, others),
        isNull,
      );
      expect(PhotoFolder.validateName('Holiday', const <PhotoFolder>[]), isNull);
    });
  });

  group('VaultItem folderId', () {
    test('a record saved before Phase 6 has no folder', () {
      final json = photo('p1', 'f1').toJson()..remove('folderId');
      expect(VaultItem.fromJson(json).folderId, '');
    });

    test('copyWith can set the folder and the key', () {
      final moved = photo('p1', 'f1').copyWith(folderId: 'f2', fileKey: 'k2.xyz');
      expect(moved.folderId, 'f2');
      expect(moved.fileKey, 'k2.xyz');
      expect(moved.id, 'p1');
    });
  });
}
