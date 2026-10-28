import 'dart:math';

import 'package:client/password_generator.dart';
import 'package:flutter_test/flutter_test.dart';

bool hasMatch(String pattern, String text) => RegExp(pattern).hasMatch(text);

void main() {
  test('has the requested length', () {
    expect(PasswordGenerator.generate(length: 8).length, 8);
    expect(PasswordGenerator.generate(length: 16).length, 16);
    expect(PasswordGenerator.generate(length: 32).length, 32);
  });

  test('always contains lowercase, uppercase, a digit and a symbol', () {
    for (var i = 0; i < 300; i++) {
      final password = PasswordGenerator.generate(length: 8);
      expect(hasMatch(r'[a-z]', password), isTrue);
      expect(hasMatch(r'[A-Z]', password), isTrue);
      expect(hasMatch(r'[0-9]', password), isTrue);
      expect(hasMatch(r'[^a-zA-Z0-9]', password), isTrue);
    }
  });

  test('has no symbols when symbols are switched off', () {
    for (var i = 0; i < 300; i++) {
      final password = PasswordGenerator.generate(length: 12, useSymbols: false);
      expect(hasMatch(r'[^a-zA-Z0-9]', password), isFalse);
    }
  });

  test('two passwords are different', () {
    expect(PasswordGenerator.generate(), isNot(PasswordGenerator.generate()));
  });

  test('digits only when everything else is switched off', () {
    for (var i = 0; i < 100; i++) {
      final password = PasswordGenerator.generate(
        length: 10,
        useSymbols: false,
        useUppercase: false,
        useLowercase: false,
      );
      expect(hasMatch(r'^[0-9]{10}$', password), isTrue);
    }
  });

  test('look-alike characters are left out when asked', () {
    for (var i = 0; i < 300; i++) {
      final password = PasswordGenerator.generate(
        length: 24,
        avoidLookAlikes: true,
      );
      expect(hasMatch('[Il1O0o]', password), isFalse);
    }
  });

  test('never returns an empty password', () {
    final password = PasswordGenerator.generate(
      length: 12,
      useSymbols: false,
      useUppercase: false,
      useLowercase: false,
      useDigits: false,
    );
    expect(password.length, 12);
  });

  test('a fixed seed gives a repeatable result (used only in tests)', () {
    final a = PasswordGenerator.generate(random: Random(7));
    final b = PasswordGenerator.generate(random: Random(7));
    expect(a, b);
  });
}
