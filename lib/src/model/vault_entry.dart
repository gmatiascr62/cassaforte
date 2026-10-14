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

/// Cómo se escribe un dato propio de un tipo (para elegir el teclado).
enum DetailKind { text, number, phone, email, address, expiry }

/// Un dato propio de un tipo de elemento (p. ej., el número de una tarjeta).
class DetailSpec {
  const DetailSpec(
    this.key,
    this.label, {
    this.hidden = false,
    this.required = false,
    this.kind = DetailKind.text,
    this.hint,
  });

  /// Clave con la que se guarda (no cambiar: está en las bóvedas y copias).
  final String key;
  final String label;

  /// Se muestra oculto como una contraseña.
  final bool hidden;
  final bool required;
  final DetailKind kind;
  final String? hint;
}

/// Qué se guarda en un elemento de la bóveda.
enum EntryType {
  /// Usuario y contraseña de una página o app (lo que había antes).
  login('login', 'Sesión'),
  card('card', 'Tarjeta'),
  contact('contact', 'Contacto');

  const EntryType(this.id, this.label);

  /// Identificador que se guarda (no cambiar).
  final String id;
  final String label;

  static EntryType fromId(String id) => values.firstWhere(
    (t) => t.id == id,
    orElse: () => throw FormatException('Tipo "$id" no válido'),
  );

  /// Datos propios del tipo, en orden. Las sesiones usan los campos de
  /// siempre (usuario y contraseña).
  List<DetailSpec> get details => switch (this) {
    EntryType.login => const [],
    EntryType.card => const [
      DetailSpec(
        'number',
        'Número de tarjeta',
        hidden: true,
        required: true,
        kind: DetailKind.number,
      ),
      DetailSpec(
        'expiry',
        'Vencimiento',
        kind: DetailKind.expiry,
        hint: 'MM/AA',
      ),
      DetailSpec('holder', 'Nombre del titular'),
      DetailSpec(
        'cvv',
        'Código de seguridad',
        hidden: true,
        kind: DetailKind.number,
        hint: 'Los 3 o 4 números de atrás',
      ),
    ],
    EntryType.contact => const [
      DetailSpec('phone', 'Teléfono', kind: DetailKind.phone),
      DetailSpec('email', 'Email', kind: DetailKind.email),
      DetailSpec('address', 'Dirección', kind: DetailKind.address),
    ],
  };
}

/// Un elemento guardado en la bóveda: una sesión (usuario y contraseña),
/// una tarjeta o un contacto. Todos sus datos se guardan cifrados.
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
    this.type = EntryType.login,
    this.details = const {},
  });

  factory VaultEntry.create({
    required String title,
    String url = '',
    String username = '',
    String password = '',
    String notes = '',
    List<CustomField> fields = const [],
    EntryType type = EntryType.login,
    Map<String, String> details = const {},
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
      type: type,
      details: Map.unmodifiable(details),
    );
  }

  final EntryType type;

  /// Datos propios del tipo ([EntryType.details]), por clave.
  final Map<String, String> details;

  String detail(String key) => details[key] ?? '';

  /// Nombre de la página o servicio, de la tarjeta o del contacto.
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
    EntryType? type,
    Map<String, String>? details,
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
      type: type ?? this.type,
      details: details == null ? this.details : Map.unmodifiable(details),
      createdAt: createdAt,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Coincidencia de búsqueda sin distinguir mayúsculas. No busca en la
  /// contraseña ni en los datos ocultos (número de tarjeta, código…).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        url.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        notes.toLowerCase().contains(q) ||
        (type != EntryType.login && type.label.toLowerCase().contains(q)) ||
        type.details.any(
          (d) => !d.hidden && detail(d.key).toLowerCase().contains(q),
        ) ||
        fields.any(
          (f) =>
              f.label.toLowerCase().contains(q) ||
              (!f.hidden && f.value.toLowerCase().contains(q)),
        );
  }

  /// El contacto como texto, para copiarlo entero: nombre y, en cada
  /// línea, los datos que tenga (los campos ocultos no se incluyen).
  String contactText() => [
    title,
    for (final d in type.details)
      if (!d.hidden && detail(d.key).isNotEmpty) '${d.label}: ${detail(d.key)}',
    for (final f in fields)
      if (!f.hidden && f.value.isNotEmpty) '${f.label}: ${f.value}',
  ].join('\n');

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.id,
    'title': title,
    'url': url,
    'username': username,
    'password': password,
    'notes': notes,
    'details': {
      for (final e in details.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    },
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
      // Las bóvedas y copias anteriores no tienen tipo: son sesiones.
      type: switch (json['type']) {
        null => EntryType.login,
        final String id => EntryType.fromId(id),
        _ => throw const FormatException('Campo "type" no válido'),
      },
      details: switch (json['details']) {
        null => const {},
        final Map<String, Object?> map => Map.unmodifiable({
          for (final e in map.entries)
            e.key: e.value is String
                ? e.value! as String
                : throw const FormatException('Campo "details" no válido'),
        }),
        _ => throw const FormatException('Campo "details" no válido'),
      },
    );
  }

  static String newEntryId() =>
      randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Serialización del contenido (en claro) de la bóveda, antes de cifrarlo.
class VaultContents {
  /// 2: elementos con tipo (sesión, tarjeta, contacto). Se siguen leyendo
  /// las bóvedas y copias de la versión 1 (todo son sesiones). Una versión
  /// anterior de la app rechaza la 2 en vez de perder las tarjetas y los
  /// contactos al guardar.
  static const int schemaVersion = 2;
  static const Set<int> readableVersions = {1, 2};

  static List<int> encode(List<VaultEntry> entries) => utf8.encode(
    jsonEncode({
      'schema': schemaVersion,
      'entries': [for (final e in entries) e.toJson()],
    }),
  );

  static List<VaultEntry> decode(List<int> bytes) {
    final doc = jsonDecode(utf8.decode(bytes));
    if (doc is! Map<String, Object?> ||
        !readableVersions.contains(doc['schema'])) {
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
