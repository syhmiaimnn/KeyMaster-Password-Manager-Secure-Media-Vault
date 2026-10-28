import 'package:client/password_tools.dart';
import 'package:client/vault_item.dart';
import 'package:flutter_test/flutter_test.dart';

VaultItem login(String id, String password, {DateTime? updatedAt}) {
  return VaultItem(
    id: id,
    type: 'Password',
    title: 'Site $id',
    password: password,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('PasswordTools.evaluate', () {
    test('an empty password is very weak', () {
      final result = PasswordTools.evaluate('');
      expect(result.level, StrengthLevel.veryWeak);
      expect(result.bits, 0);
    });

    test('common passwords are weak, even with digits or symbols added', () {
      expect(PasswordTools.evaluate('password').isWeak, isTrue);
      expect(PasswordTools.evaluate('Password123!').isWeak, isTrue);
      expect(PasswordTools.evaluate('qwerty').isWeak, isTrue);
    });

    test('sequences and repeats are weak', () {
      expect(PasswordTools.evaluate('123456').isWeak, isTrue);
      expect(PasswordTools.evaluate('aaaaaaaaaaaa').isWeak, isTrue);
    });

    test('a long random password is strong', () {
      final result = PasswordTools.evaluate('k9#Vq2!Lm8@Zx5\$Rt7');
      expect(result.isWeak, isFalse);
      expect(result.level, StrengthLevel.veryStrong);
    });

    test('a longer password scores higher than a short one', () {
      final short = PasswordTools.evaluate('Xk3!pQ');
      final long = PasswordTools.evaluate('Xk3!pQ9#vL2@');
      expect(long.bits, greaterThan(short.bits));
    });

    test('tips explain what to improve', () {
      final result = PasswordTools.evaluate('abc');
      expect(result.tips, isNotEmpty);
    });
  });

  group('SecurityReport', () {
    final now = DateTime(2026, 10, 28, 12);

    SecurityReport analyze(
      List<VaultItem> items, {
      bool biometricOn = true,
      int autoLockSeconds = 0,
      bool screenshotsBlocked = true,
      int clipboardSeconds = 30,
    }) {
      return SecurityReport.analyze(
        items,
        biometricOn: biometricOn,
        autoLockSeconds: autoLockSeconds,
        screenshotsBlocked: screenshotsBlocked,
        clipboardSeconds: clipboardSeconds,
        now: now,
      );
    }

    test('an empty vault with the best settings scores 100', () {
      final report = analyze(const []);
      expect(report.score, 100);
      expect(report.verdict, 'Excellent');
      expect(report.deviceIssues, 0);
      expect(report.issueCount, 0);
    });

    test('finds weak, reused and old passwords', () {
      final fresh = now.subtract(const Duration(days: 5));
      final stale = now.subtract(const Duration(days: 200));
      final items = [
        login('weak', 'password', updatedAt: fresh),
        login('same1', 'Xk3!pQ9#vL2@', updatedAt: fresh),
        login('same2', 'Xk3!pQ9#vL2@', updatedAt: fresh),
        login('old', 'k9#Vq2!Lm8@Zx5\$Rt7', updatedAt: stale),
        login('good', 'Hy7&nW3^bT1*cD6%', updatedAt: fresh),
      ];

      final report = analyze(items);

      expect(report.passwordCount, 5);
      expect(report.weak.map((item) => item.id), ['weak']);
      expect(report.reused.map((item) => item.id).toSet(), {'same1', 'same2'});
      expect(report.old.map((item) => item.id), ['old']);
      expect(report.issueCount, 4);
      expect(report.score, lessThan(100));
      expect(report.score, inInclusiveRange(78, 86));
    });

    test('notes and photos are not counted as passwords', () {
      final items = [
        VaultItem(id: 'n1', type: 'Note', title: 'Note', note: 'hello'),
        VaultItem(
          id: 'm1',
          type: 'Media',
          title: 'Photo',
          mimeType: 'image/jpeg',
        ),
      ];
      expect(analyze(items).passwordCount, 0);
    });

    test('weak device settings lower the score and show in the checklist', () {
      final report = analyze(
        const [],
        biometricOn: false,
        autoLockSeconds: 300,
        screenshotsBlocked: false,
        clipboardSeconds: 60,
      );
      expect(report.deviceIssues, 4);
      expect(report.score, inInclusiveRange(77, 78));
      expect(report.verdict, 'Good');
    });

    test('more problems never give a higher score', () {
      final fresh = now.subtract(const Duration(days: 5));
      final good = analyze([login('a', 'Hy7&nW3^bT1*cD6%', updatedAt: fresh)]);
      final bad = analyze([login('a', 'password', updatedAt: fresh)]);
      expect(bad.score, lessThan(good.score));
    });
  });

  group('PinPolicy', () {
    test('accepts a normal PIN', () {
      expect(PinPolicy.validate('493817'), isNull);
      expect(PinPolicy.validate('846201'), isNull);
    });

    test('rejects the wrong length or non-digits', () {
      expect(PinPolicy.validate('12345'), isNotNull);
      expect(PinPolicy.validate('1234567'), isNotNull);
      expect(PinPolicy.validate('12345a'), isNotNull);
    });

    test('rejects easy PINs', () {
      expect(PinPolicy.validate('111111'), isNotNull);
      expect(PinPolicy.validate('123456'), isNotNull);
      expect(PinPolicy.validate('654321'), isNotNull);
      expect(PinPolicy.validate('121212'), isNotNull);
      expect(PinPolicy.validate('282828'), isNotNull);
    });
  });
}
