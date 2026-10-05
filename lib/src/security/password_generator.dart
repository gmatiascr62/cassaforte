import 'dart:math';

/// Opciones del generador de contraseñas.
class PasswordOptions {
  const PasswordOptions({
    this.length = 20,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = false,
  });

  static const int minLength = 8;
  static const int maxLength = 64;

  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;

  /// Excluye caracteres fáciles de confundir (0/O, 1/l/I…).
  final bool avoidAmbiguous;

  PasswordOptions copyWith({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? avoidAmbiguous,
  }) {
    return PasswordOptions(
      length: length ?? this.length,
      lowercase: lowercase ?? this.lowercase,
      uppercase: uppercase ?? this.uppercase,
      digits: digits ?? this.digits,
      symbols: symbols ?? this.symbols,
      avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
    );
  }

  bool get hasAnySet => lowercase || uppercase || digits || symbols;
}

/// Generador de contraseñas basado en [Random.secure], que usa el generador
/// criptográficamente seguro del sistema operativo.
class PasswordGenerator {
  PasswordGenerator([Random? random]) : _random = random ?? Random.secure();

  static const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
  static const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String digitChars = '0123456789';
  static const String symbolChars = r'!#$%&*+-=?@^_~.,:;()[]{}<>/|';
  static const String ambiguousChars = 'O0oIl1|';

  final Random _random;

  /// Conjuntos de caracteres activos según [options].
  static List<String> charsetsFor(PasswordOptions options) {
    String filter(String s) => options.avoidAmbiguous
        ? s.split('').where((c) => !ambiguousChars.contains(c)).join()
        : s;
    return [
      if (options.lowercase) filter(lowercaseChars),
      if (options.uppercase) filter(uppercaseChars),
      if (options.digits) filter(digitChars),
      if (options.symbols) filter(symbolChars),
    ];
  }

  /// Genera una contraseña que contiene al menos un carácter de cada
  /// conjunto seleccionado. Cada carácter se elige de manera uniforme
  /// ([Random.nextInt] no tiene sesgo de módulo).
  String generate(PasswordOptions options) {
    if (options.length < PasswordOptions.minLength ||
        options.length > PasswordOptions.maxLength) {
      throw ArgumentError.value(options.length, 'length');
    }
    final sets = charsetsFor(options);
    if (sets.isEmpty) {
      throw ArgumentError('Selecciona al menos un tipo de carácter');
    }
    final all = sets.join();
    final chars = <String>[
      for (final set in sets) set[_random.nextInt(set.length)],
      for (var i = sets.length; i < options.length; i++)
        all[_random.nextInt(all.length)],
    ];
    // Mezcla de Fisher-Yates para que los caracteres obligatorios no queden
    // siempre al principio.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }

  /// Entropía aproximada en bits (cota superior, por carácter uniforme).
  static double estimateEntropyBits(PasswordOptions options) {
    final size = charsetsFor(options).join().length;
    if (size == 0) return 0;
    return options.length * log(size) / ln2;
  }
}
