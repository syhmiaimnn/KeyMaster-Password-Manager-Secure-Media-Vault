import 'dart:typed_data';

import 'package:client/crypto_service.dart';
import 'package:client/recovery_phrase.dart';
import 'package:client/recovery_words.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List filled(int value) => Uint8List.fromList(List<int>.filled(16, value));

void main() {
  final crypto = CryptoService();
  final phrase = RecoveryPhrase(crypto);

  group('word list', () {
    test('has 2048 different lower-case words in order', () {
      expect(kRecoveryWords.length, 2048);
      expect(kRecoveryWords.toSet().length, 2048);
      expect(kRecoveryWords.first, 'abandon');
      expect(kRecoveryWords.last, 'zoo');
      final sorted = [...kRecoveryWords]..sort();
      expect(kRecoveryWords, sorted);
      for (final word in kRecoveryWords) {
        expect(RegExp(r'^[a-z]+$').hasMatch(word), isTrue, reason: word);
      }
    });
  });

  group('split', () {
    test('ignores capitals, numbers, commas and line breaks', () {
      expect(
        RecoveryPhrase.split('1. Abandon, 2. ABILITY\n3) able  about'),
        ['abandon', 'ability', 'able', 'about'],
      );
    });

    test('gives an empty list for empty text', () {
      expect(RecoveryPhrase.split('  \n 123 '), isEmpty);
    });
  });

  group('words from bytes (official BIP-39 test vectors)', () {
    test('all zero bytes', () async {
      final words = await phrase.wordsFromEntropy(filled(0x00));
      expect(
        words.join(' '),
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about',
      );
    });

    test('all 0x7f bytes', () async {
      final words = await phrase.wordsFromEntropy(filled(0x7f));
      expect(
        words.join(' '),
        'legal winner thank year wave sausage worth useful legal winner '
        'thank yellow',
      );
    });

    test('all 0x80 bytes', () async {
      final words = await phrase.wordsFromEntropy(filled(0x80));
      expect(
        words.join(' '),
        'letter advice cage absurd amount doctor acoustic avoid letter '
        'advice cage above',
      );
    });

    test('all 0xff bytes', () async {
      final words = await phrase.wordsFromEntropy(filled(0xff));
      expect(
        words.join(' '),
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
      );
    });

    test('refuses a wrong number of bytes', () async {
      await expectLater(
        () => phrase.wordsFromEntropy(Uint8List(15)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('check', () {
    test('accepts a valid phrase and returns the original bytes', () async {
      final result = await phrase.check(
        'legal winner thank year wave sausage worth useful legal winner '
        'thank yellow',
      );
      expect(result.isValid, isTrue);
      expect(result.problem, isNull);
      expect(result.words.length, 12);
      expect(result.entropy, filled(0x7f));
    });

    test('accepts capitals, numbering and line breaks', () async {
      final result = await phrase.check(
        '1. LEGAL winner\nthank, year wave sausage worth useful legal '
        'winner thank YELLOW',
      );
      expect(result.isValid, isTrue);
    });

    test('random phrases survive the round trip', () async {
      for (var i = 0; i < 25; i++) {
        final bytes = crypto.randomBytes(RecoveryPhrase.entropyBytes);
        final words = await phrase.wordsFromEntropy(bytes);
        expect(words.length, RecoveryPhrase.wordCount);
        final result = await phrase.check(words.join(' '));
        expect(result.isValid, isTrue);
        expect(result.entropy, bytes);
      }
    });

    test('rejects the wrong number of words', () async {
      final result = await phrase.check('abandon abandon abandon');
      expect(result.isValid, isFalse);
      expect(result.problem, PhraseProblem.wrongCount);
      expect(result.words.length, 3);
    });

    test('rejects a word that is not in the list and says where', () async {
      final result = await phrase.check(
        'legal winner thank year wave sausage worth usefull legal winner '
        'thank yellow',
      );
      expect(result.isValid, isFalse);
      expect(result.problem, PhraseProblem.unknownWord);
      expect(result.badIndex, 7);
    });

    test('rejects two swapped words with a bad checksum', () async {
      // "winner" and "thank" swapped in an otherwise valid phrase.
      final result = await phrase.check(
        'legal thank winner year wave sausage worth useful legal winner '
        'thank yellow',
      );
      expect(result.isValid, isFalse);
      expect(result.problem, PhraseProblem.badChecksum);
    });
  });
}