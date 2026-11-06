import 'package:client/decoy_seed.dart';
import 'package:client/vault_data.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime.utc(2026, 11, 6, 12);

void main() {
  group('decoy seed', () {
    test('has passwords and notes, but no photos and no folders', () {
      final data = DecoySeed.build(now: today);

      expect(data.items.where((i) => i.isPassword).length, greaterThanOrEqualTo(5));
      expect(data.items.where((i) => i.isNote).length, greaterThanOrEqualTo(2));
      expect(data.items.where((i) => i.isPhoto), isEmpty);
      expect(data.folders, isEmpty);
    });

    test('every entry has its own id and a title', () {
      final data = DecoySeed.build(now: today);
      final ids = data.items.map((i) => i.id).toSet();

      expect(ids.length, data.items.length);
      for (final item in data.items) {
        expect(item.title.trim(), isNotEmpty);
      }
    });

    test('every password entry has a user name and a password', () {
      final data = DecoySeed.build(now: today);
      for (final item in data.items.where((i) => i.isPassword)) {
        expect(item.username, isNotEmpty, reason: item.title);
        expect(item.password, isNotEmpty, reason: item.title);
      }
    });

    test('every note has some text', () {
      final data = DecoySeed.build(now: today);
      for (final item in data.items.where((i) => i.isNote)) {
        expect(item.note.trim(), isNotEmpty, reason: item.title);
      }
    });

    test('web addresses belong to the reserved example domains', () {
      final data = DecoySeed.build(now: today);
      for (final item in data.items.where((i) => i.website.isNotEmpty)) {
        final host = Uri.parse(item.website).host;
        final reserved = RegExp(r'(^|\.)example\.(com|net|org)$');
        expect(reserved.hasMatch(host), isTrue, reason: item.website);
      }
    });

    test('entries are dated in the past and spread over time', () {
      final data = DecoySeed.build(now: today);
      final days = data.items.map((i) => i.createdAt).toSet();

      for (final item in data.items) {
        expect(item.createdAt.isBefore(today), isTrue, reason: item.title);
        expect(item.updatedAt, item.createdAt);
      }
      expect(days.length, greaterThan(4));
    });

    test('it saves and opens like any vault data', () {
      final data = DecoySeed.build(now: today);
      final back = VaultData.deserialize(data.serialize());

      expect(back.items.length, data.items.length);
      expect(back.items.first.title, data.items.first.title);
      expect(back.folders, isEmpty);
    });
  });
}
