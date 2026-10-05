import 'package:cassaforte/src/security/clipboard_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  const wait = Duration(milliseconds: 60);
  const after = Duration(milliseconds: 150);

  test('el plazo por defecto es de 20 segundos', () {
    expect(ClipboardGuard().clearAfter, const Duration(seconds: 20));
  });

  test('borra la contraseña pasado el plazo', () async {
    final clip = FakeClipboard();
    final guard = ClipboardGuard(clipboard: clip, clearAfter: wait);
    await guard.copySecret('secreto');
    expect(clip.content, 'secreto');
    await Future<void>.delayed(after);
    expect(clip.content, isNull);
    expect(guard.hasPending, isFalse);
  });

  test('no borra lo que el usuario copió después', () async {
    final clip = FakeClipboard();
    final guard = ClipboardGuard(clipboard: clip, clearAfter: wait);
    await guard.copySecret('secreto');
    clip.userCopies('texto del usuario');
    await Future<void>.delayed(after);
    expect(clip.content, 'texto del usuario');
    expect(clip.clears, 0);
  });

  test('una copia nueva sustituye a la anterior y reinicia el plazo', () async {
    final clip = FakeClipboard();
    final guard = ClipboardGuard(
      clipboard: clip,
      clearAfter: const Duration(milliseconds: 120),
    );
    await guard.copySecret('uno');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await guard.copySecret('dos');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(clip.content, 'dos');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(clip.content, isNull);
    expect(clip.clears, 1);
  });

  test('si el sistema no deja acceder, reintenta al volver', () async {
    final clip = FakeClipboard()..accessible = false;
    final guard = ClipboardGuard(clipboard: clip, clearAfter: wait);
    await guard.copySecret('secreto');
    await Future<void>.delayed(after);
    expect(clip.content, 'secreto');
    expect(guard.hasPending, isTrue);

    clip.accessible = true;
    await guard.onAppResumed();
    expect(clip.content, isNull);
    expect(guard.hasPending, isFalse);
  });

  test('al volver no borra si el usuario copió otra cosa', () async {
    final clip = FakeClipboard()..accessible = false;
    final guard = ClipboardGuard(clipboard: clip, clearAfter: wait);
    await guard.copySecret('secreto');
    await Future<void>.delayed(after);
    clip
      ..accessible = true
      ..userCopies('otra cosa');
    await guard.onAppResumed();
    expect(clip.content, 'otra cosa');
  });

  test('volver antes del plazo no borra antes de tiempo', () async {
    final clip = FakeClipboard();
    final guard = ClipboardGuard(
      clipboard: clip,
      clearAfter: const Duration(milliseconds: 200),
    );
    await guard.copySecret('secreto');
    await guard.onAppResumed();
    expect(clip.content, 'secreto');
    guard.dispose();
  });
}
