import 'package:cassaforte/src/security/password_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final generator = PasswordGenerator();

  test('respeta la longitud pedida', () {
    for (final length in [8, 12, 20, 33, 64]) {
      expect(
        generator.generate(PasswordOptions(length: length)),
        hasLength(length),
      );
    }
  });

  test('incluye al menos un carácter de cada tipo elegido', () {
    for (var i = 0; i < 200; i++) {
      final p = generator.generate(const PasswordOptions(length: 8));
      expect(p, matches(RegExp('[a-z]')));
      expect(p, matches(RegExp('[A-Z]')));
      expect(p, matches(RegExp('[0-9]')));
      expect(p.split('').any(PasswordGenerator.symbolChars.contains), isTrue);
    }
  });

  test('solo usa los tipos de carácter elegidos', () {
    const onlyDigits = PasswordOptions(
      length: 30,
      lowercase: false,
      uppercase: false,
      symbols: false,
    );
    expect(generator.generate(onlyDigits), matches(RegExp(r'^[0-9]{30}$')));

    const lettersOnly = PasswordOptions(
      length: 30,
      digits: false,
      symbols: false,
    );
    expect(generator.generate(lettersOnly), matches(RegExp(r'^[a-zA-Z]{30}$')));
  });

  test('puede evitar caracteres ambiguos', () {
    const options = PasswordOptions(length: 64, avoidAmbiguous: true);
    for (var i = 0; i < 100; i++) {
      final p = generator.generate(options);
      for (final c in PasswordGenerator.ambiguousChars.split('')) {
        expect(p.contains(c), isFalse);
      }
    }
  });

  test('rechaza opciones no válidas', () {
    expect(
      () => generator.generate(const PasswordOptions(length: 7)),
      throwsArgumentError,
    );
    expect(
      () => generator.generate(const PasswordOptions(length: 65)),
      throwsArgumentError,
    );
    expect(
      () => generator.generate(
        const PasswordOptions(
          lowercase: false,
          uppercase: false,
          digits: false,
          symbols: false,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('no repite contraseñas y reparte los caracteres', () {
    const options = PasswordOptions(length: 32);
    final seen = <String>{};
    final counts = <String, int>{};
    for (var i = 0; i < 2000; i++) {
      final p = generator.generate(options);
      expect(seen.add(p), isTrue);
      for (final c in p.split('')) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final alphabet = PasswordGenerator.charsetsFor(options).join();
    // Con 64 000 caracteres, todos los del alfabeto deben aparecer y
    // ninguno debe estar muy por encima de la media.
    expect(counts.keys.toSet(), alphabet.split('').toSet());
    final mean = 64000 / alphabet.length;
    for (final n in counts.values) {
      expect(n, lessThan(mean * 1.5));
      expect(n, greaterThan(mean * 0.5));
    }
  });

  test('estima la entropía', () {
    expect(
      PasswordGenerator.estimateEntropyBits(
        const PasswordOptions(
          length: 10,
          lowercase: false,
          uppercase: false,
          symbols: false,
        ),
      ),
      closeTo(33.2, 0.1),
    );
  });
}
