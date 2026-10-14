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

  group('Tipos', () {
    final card = VaultEntry.create(
      title: 'Visa Banco',
      type: EntryType.card,
      details: const {
        'number': '4111 1111 1111 1234',
        'expiry': '08/29',
        'holder': 'Juan Pérez',
        'cvv': '123',
      },
    );
    final contact = VaultEntry.create(
      title: 'Ana',
      type: EntryType.contact,
      details: const {
        'phone': '+54 11 5555-1234',
        'email': 'ana@example.com',
        'address': 'Calle 1',
      },
      fields: const [
        CustomField(label: 'Cumpleaños', value: '3 de mayo'),
        CustomField(label: 'Clave del portón', value: '4321', hidden: true),
      ],
    );

    test('tarjetas y contactos se guardan y se leen con sus datos', () {
      final decoded = VaultContents.decode(
        VaultContents.encode([card, contact]),
      );
      expect(decoded[0].type, EntryType.card);
      expect(decoded[0].details, card.details);
      expect(decoded[0].password, isEmpty);
      expect(decoded[1].type, EntryType.contact);
      expect(decoded[1].details, contact.details);
      expect(decoded[1].fields, contact.fields);
    });

    test('lo guardado antes (sin tipo) es una sesión', () {
      final legacy = {
        'schema': 1,
        'entries': [
          {
            'id': 'a1',
            'title': 'Correo',
            'url': '',
            'username': 'yo',
            'password': 'x',
            'notes': '',
            'createdAt': 0,
            'updatedAt': 0,
          },
        ],
      };
      final entry = VaultContents.decode(utf8.encode(jsonEncode(legacy)))
          .single;
      expect(entry.type, EntryType.login);
      expect(entry.details, isEmpty);
    });

    test('se guarda con la versión 2 del formato', () {
      final doc = jsonDecode(utf8.decode(VaultContents.encode([card])));
      expect(doc['schema'], 2);
    });

    test('rechaza tipos y datos no válidos', () {
      Map<String, Object?> doc(Map<String, Object?> extra) => {
        'schema': 2,
        'entries': [
          {
            'id': 'a1',
            'title': 'X',
            'url': '',
            'username': '',
            'password': '',
            'notes': '',
            'createdAt': 0,
            'updatedAt': 0,
            ...extra,
          },
        ],
      };
      for (final bad in [
        doc({'type': 'otro'}),
        doc({'type': 3}),
        doc({
          'details': {'number': 1234},
        }),
        doc({'details': 'x'}),
        {'schema': 3, 'entries': <Object?>[]},
      ]) {
        expect(
          () => VaultContents.decode(utf8.encode(jsonEncode(bad))),
          throwsFormatException,
        );
      }
    });

    test('la búsqueda no mira el número ni el código de la tarjeta', () {
      expect(card.matches('visa'), isTrue);
      expect(card.matches('juan'), isTrue);
      expect(card.matches('tarjeta'), isTrue);
      expect(card.matches('1234'), isFalse);
      expect(card.matches('123'), isFalse);
      expect(contact.matches('ana@'), isTrue);
      expect(contact.matches('5555'), isTrue);
      expect(contact.matches('contacto'), isTrue);
      expect(contact.matches('4321'), isFalse);
    });

    test('el contacto entero se copia como texto, sin campos ocultos', () {
      expect(
        contact.contactText(),
        'Ana\n'
        'Teléfono: +54 11 5555-1234\n'
        'Email: ana@example.com\n'
        'Dirección: Calle 1\n'
        'Cumpleaños: 3 de mayo',
      );
    });
  });
}
