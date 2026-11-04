import 'dart:typed_data';

import 'crypto_service.dart';
import 'recovery_words.dart';

/// Why a typed recovery phrase was refused.
enum PhraseProblem {
  /// There are not exactly 12 words.
  wrongCount,

  /// One word is not in the word list (see [PhraseCheck.badIndex]).
  unknownWord,

  /// All words exist, but together they are not a valid phrase. Usually two
  /// words are swapped or one word was replaced by a similar one.
  badChecksum,
}

/// The result of [RecoveryPhrase.check].
class PhraseCheck {
  /// The words found in the text, lower case.
  final List<String> words;

  /// The 16 bytes behind the phrase. Only set when the phrase is valid.
  final Uint8List? entropy;

  /// Null when the phrase is valid.
  final PhraseProblem? problem;

  /// For [PhraseProblem.unknownWord]: the position of the bad word, from 0.
  final int badIndex;

  const PhraseCheck._({
    required this.words,
    this.entropy,
    this.problem,
    this.badIndex = -1,
  });

  bool get isValid => problem == null;
}

/// A recovery phrase: 12 easy words that stand for 128 random bits.
///
/// The format is the one used by BIP-39. 128 random bits plus a 4-bit checksum
/// make 132 bits, which are cut into twelve groups of 11 bits. Each group picks
/// one word from the list of 2048 words. The checksum is the first 4 bits of
/// SHA-256 of the 128 bits, so a typing mistake is caught at once.
///
/// This class only converts between bytes and words. The hash comes from
/// CryptoService, so all cryptography still lives in one place.
class RecoveryPhrase {
  RecoveryPhrase(this._crypto);

  static const int wordCount = 12;
  static const int entropyBytes = 16; // 128 bits
  static const int _bitsPerWord = 11; // 2048 words = 2^11
  static const int _checksumBits = 4;

  final CryptoService _crypto;

  static final Map<String, int> _indexOf = {
    for (var i = 0; i < kRecoveryWords.length; i++) kRecoveryWords[i]: i,
  };

  /// Pulls the words out of typed or pasted text. It ignores capital letters,
  /// spaces, commas, line breaks and numbers, so "1. Abandon, 2. ability"
  /// gives ["abandon", "ability"].
  static List<String> split(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  /// Turns 16 random bytes into the 12 words.
  Future<List<String>> wordsFromEntropy(Uint8List entropy) async {
    if (entropy.length != entropyBytes) {
      throw ArgumentError('A recovery phrase needs exactly 16 bytes');
    }
    final hash = await _crypto.sha256(entropy);

    // 128 data bits, then the first 4 bits of the hash.
    final bits = <int>[];
    for (final byte in entropy) {
      for (var shift = 7; shift >= 0; shift--) {
        bits.add((byte >> shift) & 1);
      }
    }
    for (var shift = 7; shift >= 8 - _checksumBits; shift--) {
      bits.add((hash[0] >> shift) & 1);
    }

    final words = <String>[];
    for (var w = 0; w < wordCount; w++) {
      var index = 0;
      for (var b = 0; b < _bitsPerWord; b++) {
        index = (index << 1) | bits[w * _bitsPerWord + b];
      }
      words.add(kRecoveryWords[index]);
    }
    return words;
  }

  /// Reads typed text and says whether it is a valid phrase.
  Future<PhraseCheck> check(String text) async {
    final words = split(text);
    if (words.length != wordCount) {
      return PhraseCheck._(words: words, problem: PhraseProblem.wrongCount);
    }

    final bits = <int>[];
    for (var i = 0; i < words.length; i++) {
      final index = _indexOf[words[i]];
      if (index == null) {
        return PhraseCheck._(
          words: words,
          problem: PhraseProblem.unknownWord,
          badIndex: i,
        );
      }
      for (var shift = _bitsPerWord - 1; shift >= 0; shift--) {
        bits.add((index >> shift) & 1);
      }
    }

    // The first 128 bits are the data, the last 4 are the checksum.
    final entropy = Uint8List(entropyBytes);
    for (var i = 0; i < entropyBytes * 8; i++) {
      entropy[i ~/ 8] = (entropy[i ~/ 8] << 1) | bits[i];
    }
    var checksum = 0;
    for (var i = 0; i < _checksumBits; i++) {
      checksum = (checksum << 1) | bits[entropyBytes * 8 + i];
    }

    final hash = await _crypto.sha256(entropy);
    if ((hash[0] >> (8 - _checksumBits)) != checksum) {
      return PhraseCheck._(words: words, problem: PhraseProblem.badChecksum);
    }
    return PhraseCheck._(words: words, entropy: entropy);
  }
}
