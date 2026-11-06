import 'dart:convert';
import 'dart:typed_data';

import 'package:client/crypto_service.dart';
import 'package:client/key_tree.dart';
import 'package:client/photo_folder.dart';
import 'package:client/vault_item.dart';
import 'package:flutter_test/flutter_test.dart';

VaultItem photoRecord(String id, {String fileKey = '', String folderId = ''}) {
  return VaultItem(
    id: id,
    type: 'Media',
    title: 'Photo',
    mediaPath: '$id.enc',
    mimeType: 'image/jpeg',
    sizeBytes: 10,
    fileKey: fileKey,
    folderId: folderId,
  );
}

void main() {
  final crypto = CryptoService();
  final tree = KeyTree(crypto);

  group('new folder', () {
    test('has a 32-byte key and a 16-character id', () {
      final folder = tree.newFolder('Holiday');
      expect(folder.keyBytes.length, 32);
      expect(folder.id.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(folder.id), isTrue);
    });

    test('two folders never share an id or a key', () {
      final folders = List.generate(40, (i) => tree.newFolder('Folder $i'));
      expect(folders.map((f) => f.id).toSet().length, 40);
      expect(folders.map((f) => f.key).toSet().length, 40);
    });

    test('trims the name and keeps the options', () {
      final folder = tree.newFolder('  Private  ', requiresPin: true, colorIndex: 3);
      expect(folder.name, 'Private');
      expect(folder.requiresPin, isTrue);
      expect(folder.colorIndex, 3);
    });
  });

  group('wrap and unwrap a photo key', () {
    test('a wrapped key comes back exactly', () async {
      final folder = tree.newFolder('A');
      final fileKey = tree.newKey();

      final wrapped = await tree.wrapFileKey(fileKey, folder, 'p1');
      expect(wrapped.startsWith(KeyTree.wrappedPrefix), isTrue);
      expect(KeyTree.isWrapped(wrapped), isTrue);

      final photo = photoRecord('p1', fileKey: wrapped, folderId: folder.id);
      expect(await tree.unwrapFileKey(photo, folder), fileKey);
    });

    test('the wrapped text does not contain the plain key', () async {
      final folder = tree.newFolder('A');
      final fileKey = tree.newKey();
      final wrapped = await tree.wrapFileKey(fileKey, folder, 'p1');
      expect(wrapped.contains(base64Encode(fileKey)), isFalse);
    });

    test('wrapping the same key twice gives different text', () async {
      final folder = tree.newFolder('A');
      final fileKey = tree.newKey();
      final one = await tree.wrapFileKey(fileKey, folder, 'p1');
      final two = await tree.wrapFileKey(fileKey, folder, 'p1');
      expect(one, isNot(two));
    });

    test('another folder cannot open the key', () async {
      final folder = tree.newFolder('A');
      final other = tree.newFolder('B');
      final wrapped = await tree.wrapFileKey(tree.newKey(), folder, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: folder.id);

      await expectLater(
        tree.unwrapFileKey(photo, other),
        throwsA(isA<StateError>()),
      );
    });

    test('a folder with the same id but a different key cannot open it', () async {
      final folder = tree.newFolder('A');
      final impostor = PhotoFolder(
        id: folder.id,
        name: 'A',
        key: base64Encode(tree.newKey()),
      );
      final wrapped = await tree.wrapFileKey(tree.newKey(), folder, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: folder.id);

      await expectLater(tree.unwrapFileKey(photo, impostor), throwsA(anything));
    });

    test('a missing folder cannot open a wrapped key', () async {
      final folder = tree.newFolder('A');
      final wrapped = await tree.wrapFileKey(tree.newKey(), folder, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: folder.id);

      await expectLater(
        tree.unwrapFileKey(photo, null),
        throwsA(isA<StateError>()),
      );
    });

    test('a wrapped key copied onto another photo does not open', () async {
      final folder = tree.newFolder('A');
      final wrapped = await tree.wrapFileKey(tree.newKey(), folder, 'p1');
      // Same folder, but the record belongs to photo p2.
      final stolen = photoRecord('p2', fileKey: wrapped, folderId: folder.id);

      await expectLater(tree.unwrapFileKey(stolen, folder), throwsA(anything));
    });

    test('a changed wrapped key does not open', () async {
      final folder = tree.newFolder('A');
      final wrapped = await tree.wrapFileKey(tree.newKey(), folder, 'p1');

      final bytes = base64Decode(wrapped.substring(KeyTree.wrappedPrefix.length));
      bytes[bytes.length ~/ 2] ^= 0x01;
      final changed = '${KeyTree.wrappedPrefix}${base64Encode(bytes)}';
      final photo = photoRecord('p1', fileKey: changed, folderId: folder.id);

      await expectLater(tree.unwrapFileKey(photo, folder), throwsA(anything));
    });

    test('a key of the wrong length is refused', () async {
      final folder = tree.newFolder('A');
      final short = Uint8List(16);
      final wrapped = await tree.wrapFileKey(short, folder, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: folder.id);

      await expectLater(
        tree.unwrapFileKey(photo, folder),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('photos saved before Phase 6', () {
    test('a plain key still opens, even without a folder', () async {
      final fileKey = tree.newKey();
      final photo = photoRecord('old', fileKey: base64Encode(fileKey));

      expect(KeyTree.isWrapped(photo.fileKey), isFalse);
      expect(await tree.unwrapFileKey(photo, null), fileKey);
    });

    test('adopt locks the key with the folder and keeps it the same', () async {
      final folder = tree.newFolder('My photos');
      final fileKey = tree.newKey();
      final old = photoRecord('old', fileKey: base64Encode(fileKey));

      final adopted = await tree.adopt(old, folder);
      expect(adopted.folderId, folder.id);
      expect(KeyTree.isWrapped(adopted.fileKey), isTrue);
      expect(adopted.id, old.id);
      expect(adopted.mediaPath, old.mediaPath);
      expect(await tree.unwrapFileKey(adopted, folder), fileKey);
    });
  });

  group('move to another folder', () {
    test('only the key is locked again', () async {
      final a = tree.newFolder('A');
      final b = tree.newFolder('B');
      final fileKey = tree.newKey();
      final wrapped = await tree.wrapFileKey(fileKey, a, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: a.id);

      final moved = await tree.moveToFolder(photo, a, b);

      expect(moved.folderId, b.id);
      expect(moved.fileKey, isNot(photo.fileKey));
      expect(moved.id, photo.id);
      expect(moved.mediaPath, photo.mediaPath);
      expect(moved.sizeBytes, photo.sizeBytes);
      expect(await tree.unwrapFileKey(moved, b), fileKey);
    });

    test('the old folder can no longer open the moved photo', () async {
      final a = tree.newFolder('A');
      final b = tree.newFolder('B');
      final wrapped = await tree.wrapFileKey(tree.newKey(), a, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: a.id);

      final moved = await tree.moveToFolder(photo, a, b);

      await expectLater(
        tree.unwrapFileKey(moved, a),
        throwsA(isA<StateError>()),
      );
    });

    test('a photo saved before Phase 6 can be moved too', () async {
      final b = tree.newFolder('B');
      final fileKey = tree.newKey();
      final old = photoRecord('old', fileKey: base64Encode(fileKey));

      final moved = await tree.moveToFolder(old, null, b);

      expect(moved.folderId, b.id);
      expect(await tree.unwrapFileKey(moved, b), fileKey);
    });

    test('moving with the wrong source folder fails and changes nothing', () async {
      final a = tree.newFolder('A');
      final b = tree.newFolder('B');
      final c = tree.newFolder('C');
      final wrapped = await tree.wrapFileKey(tree.newKey(), a, 'p1');
      final photo = photoRecord('p1', fileKey: wrapped, folderId: a.id);

      await expectLater(tree.moveToFolder(photo, c, b), throwsA(anything));
      expect(photo.folderId, a.id);
    });
  });
}
