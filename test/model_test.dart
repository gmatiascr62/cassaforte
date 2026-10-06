import 'dart:convert';

import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los campos adicionales se guardan y se leen en orden', () {
    final entry = VaultEntry.create(
      title: 'Banco',
      username: 'juan',
      password: 'clave',
      fields: const [
        CustomField(label: 'Cliente', value: '123'),
        CustomField(label: 'PIN', value: '9876', hidden: true),
      ],
    );
    final decoded = VaultContents.decode(VaultContents.encode([entry])).single;
    expect(decoded.fields, entry.fields);
    expect(decoded.password, 'clave');
  });

  test(
    'las cuentas de versiones anteriores (sin campos) se siguen leyendo',
    () {
      final legacy = {
        'schema': 1,
        'entries': [
          {
            'id': 'a1',
            'title': 'Correo',
            'url': 'https://correo.example',
            'username': 'yo',
            'password': 'x',
            'notes': 'nota',
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
      };
      final entry = VaultContents.decode(utf8.encode(jsonEncode(legacy)))
          .single;
      expect(entry.fields, isEmpty);
      expect(entry.url, 'https://correo.example');
      expect(entry.notes, 'nota');
    },
  );

  test('rechaza campos adicionales mal formados', () {
    final bad = {
      'schema': 1,
      'entries': [
        {
          'id': 'a1',
          'title': 'X',
          'url': '',
          'username': '',
          'password': 'x',
          'notes': '',
          'fields': [
            {'label': 1},
          ],
          'createdAt': 0,
          'updatedAt': 0,
        },
      ],
    };
    expect(
      () => VaultContents.decode(utf8.encode(jsonEncode(bad))),
      throwsFormatException,
    );
  });

  test('la búsqueda incluye los campos visibles pero no los ocultos', () {
    final entry = VaultEntry.create(
      title: 'Banco',
      password: 'clave',
      fields: const [
        CustomField(label: 'Cliente', value: 'ABC123'),
        CustomField(label: 'PIN', value: '9876', hidden: true),
      ],
    );
    expect(entry.matches('abc'), isTrue);
    expect(entry.matches('pin'), isTrue);
    expect(entry.matches('9876'), isFalse);
    expect(entry.matches('clave'), isFalse);
  });
}
