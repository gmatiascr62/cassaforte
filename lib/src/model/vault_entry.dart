import 'dart:convert';

import '../crypto/kdf.dart';

/// Campo adicional de una cuenta (p. ej., «Código de cliente»), entre el
/// usuario y la contraseña.
class CustomField {
  const CustomField({
    required this.label,
    required this.value,
    this.hidden = false,
  });

  final String label;
  final String value;

  /// Se muestra oculto como una contraseña (p. ej., un PIN).
  final bool hidden;

  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    'hidden': hidden,
  };

  factory CustomField.fromJson(Object? json) {
    if (json is Map<String, Object?> &&
        json['label'] is String &&
        json['value'] is String) {
      return CustomField(
        label: json['label']! as String,
        value: json['value']! as String,
        hidden: json['hidden'] == true,
      );
    }
    throw const FormatException('Campo adicional no válido');
  }

  @override
  bool operator ==(Object other) =>
      other is CustomField &&
      other.label == label &&
      other.value == value &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(label, value, hidden);
}

/// Una cuenta guardada en la bóveda. Todos sus campos se guardan cifrados.
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.title,
    required this.url,
    required this.username,
    required this.password,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.fields = const [],
  });

  factory VaultEntry.create({
    required String title,
    String url = '',
    String username = '',
    required String password,
    String notes = '',
    List<CustomField> fields = const [],
    DateTime? now,
  }) {
    final time = (now ?? DateTime.now()).toUtc();
    return VaultEntry(
      id: newEntryId(),
      title: title,
      url: url,
      username: username,
      password: password,
      notes: notes,
      createdAt: time,
      updatedAt: time,
      fields: List.unmodifiable(fields),
    );
  }

  /// Nombre de la página o servicio.
  final String title;
  final String id;
  final String url;

  /// Usuario o correo.
  final String username;
  final String password;
  final String notes;

  /// Campos adicionales, en orden (van entre el usuario y la contraseña).
  final List<CustomField> fields;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultEntry copyWith({
    String? title,
    String? url,
    String? username,
    String? password,
    String? notes,
    List<CustomField>? fields,
    DateTime? updatedAt,
  }) {
    return VaultEntry(
      id: id,
      title: title ?? this.title,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      notes: notes ?? this.notes,
      fields: fields == null ? this.fields : List.unmodifiable(fields),
      createdAt: createdAt,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Coincidencia de búsqueda sin distinguir mayúsculas. No busca en la
  /// contraseña.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        url.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        notes.toLowerCase().contains(q) ||
        fields.any(
          (f) =>
              f.label.toLowerCase().contains(q) ||
              (!f.hidden && f.value.toLowerCase().contains(q)),
        );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'username': username,
    'password': password,
    'notes': notes,
    'fields': [for (final f in fields) f.toJson()],
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    String str(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('Campo "$key" no válido');
    }

    DateTime time(String key) {
      final value = json[key];
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      throw FormatException('Campo "$key" no válido');
    }

    return VaultEntry(
      id: str('id'),
      title: str('title'),
      url: str('url'),
      username: str('username'),
      password: str('password'),
      notes: str('notes'),
      createdAt: time('createdAt'),
      updatedAt: time('updatedAt'),
      fields: switch (json['fields']) {
        null => const [],
        final List<Object?> list => List.unmodifiable(
          list.map(CustomField.fromJson),
        ),
        _ => throw const FormatException('Campo "fields" no válido'),
      },
    );
  }

  static String newEntryId() =>
      randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Serialización del contenido (en claro) de la bóveda, antes de cifrarlo.
class VaultContents {
  static const int schemaVersion = 1;

  static List<int> encode(List<VaultEntry> entries) => utf8.encode(
    jsonEncode({
      'schema': schemaVersion,
      'entries': [for (final e in entries) e.toJson()],
    }),
  );

  static List<VaultEntry> decode(List<int> bytes) {
    final doc = jsonDecode(utf8.decode(bytes));
    if (doc is! Map<String, Object?> || doc['schema'] != schemaVersion) {
      throw const FormatException('Contenido no válido');
    }
    final list = doc['entries'];
    if (list is! List<Object?>) {
      throw const FormatException('Contenido no válido');
    }
    return [
      for (final item in list)
        if (item is Map<String, Object?>)
          VaultEntry.fromJson(item)
        else
          throw const FormatException('Entrada no válida'),
    ];
  }
}

/// Resultado de combinar las cuentas de una copia con las actuales.
class MergeResult {
  const MergeResult(this.entries, {required this.added, required this.updated});

  final List<VaultEntry> entries;
  final int added;
  final int updated;
}

/// Fusiona [incoming] en [current]: añade las cuentas que faltan y, si una
/// cuenta (mismo id) está en ambas, conserva la modificada más recientemente.
MergeResult mergeEntries(List<VaultEntry> current, List<VaultEntry> incoming) {
  final byId = {for (final e in current) e.id: e};
  var added = 0;
  var updated = 0;
  for (final e in incoming) {
    final existing = byId[e.id];
    if (existing == null) {
      byId[e.id] = e;
      added++;
    } else if (e.updatedAt.isAfter(existing.updatedAt)) {
      byId[e.id] = e;
      updated++;
    }
  }
  return MergeResult(byId.values.toList(), added: added, updated: updated);
}
