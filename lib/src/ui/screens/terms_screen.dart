import 'package:flutter/material.dart';

import '../../legal/terms.dart';
import '../widgets/common.dart';

/// Texto completo de los Términos de uso.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Términos de uso')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CenteredBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versión $termsVersion · $termsDate',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  for (final section in termsOfUse) ...[
                    Text(section.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final p in section.paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(p),
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
