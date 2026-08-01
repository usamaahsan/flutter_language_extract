import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/extracted_string.dart';
import 'base_generator.dart';

/// Generates ARB (Application Resource Bundle) files for the intl package.
///
/// **Output structure inside the target project:**
/// ```
/// lib/
///   l10n/
///     app_en.arb   ← source locale (values from code + metadata, always regenerated)
///     app_ar.arb   ← other locales (existing translations preserved,
///                     new keys appended as empty placeholders)
/// ```
class IntlGenerator extends OutputGenerator {
  @override
  Future<void> generate({
    required List<ExtractedString> strings,
    required String projectPath,
    required List<String> locales,
    required String sourceLocale,
  }) async {
    final outputDir = Directory(p.join(projectPath, 'lib', 'l10n'))
      ..createSync(recursive: true);

    for (final locale in locales) {
      await _writeArbFile(
        outputDir: outputDir,
        locale: locale,
        strings: strings,
        isSourceLocale: locale == sourceLocale,
      );
    }

    stdout.writeln('[intl] Written to ${outputDir.path}');
    _printNextSteps(projectPath, locales.first.split('_').first);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _writeArbFile({
    required Directory outputDir,
    required String locale,
    required List<ExtractedString> strings,
    required bool isSourceLocale,
  }) async {
    // intl expects BCP 47 language codes — use the language portion only.
    // e.g., 'en_US' → 'en', 'ar_AR' → 'ar'
    final languageCode = locale.split('_').first;
    final file = File(p.join(outputDir.path, 'app_$languageCode.arb'));

    // For non-source locales, read existing ARB translations so they survive
    // subsequent CLI runs. New keys are added with empty placeholders.
    final existing =
        isSourceLocale ? <String, String>{} : _parseExisting(file);

    // ARB files must begin with @@locale, then alternate key/metadata pairs.
    final arbMap = <String, dynamic>{'@@locale': languageCode};

    for (final s in strings) {
      if (isSourceLocale) {
        // Source locale: real value with {param} placeholder syntax.
        arbMap[s.key!] = s.buildLocaleValue((k) => '{$k}');

        // @key metadata — only in the template ARB file.
        // flutter gen-l10n uses this to generate typed Dart method signatures.
        final meta = <String, dynamic>{'description': s.key};
        if (s.hasInterpolation && s.dynamicSegments.isNotEmpty) {
          meta['placeholders'] = {
            for (final d in s.dynamicSegments)
              d.paramKey: {'type': 'String'}, // user can refine the type manually
          };
        }
        arbMap['@${s.key}'] = meta;
      } else {
        // Non-source locale: keep existing human translation or empty placeholder.
        arbMap[s.key!] = existing[s.key!] ?? '';
      }
    }

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(arbMap));

    final status = isSourceLocale ? 'regenerated' : _mergeStatus(existing, strings);
    stdout.writeln('  ✔ app_$languageCode.arb — $status');
  }

  /// Prints one-time setup instructions for flutter gen-l10n.
  ///
  /// Checks whether `l10n.yaml` already exists so the message is only shown
  /// when actually needed, avoiding noise on subsequent runs.
  void _printNextSteps(String projectPath, String sourceLanguageCode) {
    final l10nYaml = File(p.join(projectPath, 'l10n.yaml'));
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));

    final yamlExists = l10nYaml.existsSync();
    final generateEnabled = pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('generate: true');

    if (yamlExists && generateEnabled) return; // already set up, stay quiet

    stdout.writeln('''
┌─────────────────────────────────────────────────────────┐
│  intl one-time setup required                           │
├─────────────────────────────────────────────────────────┤''');

    if (!yamlExists) {
      stdout.writeln('''│                                                         │
│  1. Create l10n.yaml in your project root:              │
│                                                         │
│     arb-dir: lib/l10n                                   │
│     template-arb-file: app_$sourceLanguageCode.arb${' ' * (26 - sourceLanguageCode.length)}│
│     output-localization-file: app_localizations.dart    │
│                                                         │''');
    }

    if (!generateEnabled) {
      stdout.writeln('''│  ${yamlExists ? '1' : '2'}. Add to pubspec.yaml under the flutter: section:   │
│                                                         │
│     flutter:                                            │
│       generate: true                                    │
│                                                         │''');
    }

    stdout.writeln('''│  ${(!yamlExists && !generateEnabled) ? '3' : '2'}. Run:                                                  │
│                                                         │
│     flutter gen-l10n                                    │
│                                                         │
│  This generates lib/l10n/app_localizations.dart which   │
│  the added imports point to.                            │
└─────────────────────────────────────────────────────────┘''');
  }

  /// Reads an existing ARB file and returns only the translation key→value pairs,
  /// skipping `@@locale` and `@key` metadata entries.
  Map<String, String> _parseExisting(File file) {
    if (!file.existsSync()) return {};
    try {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (!e.key.startsWith('@')) e.key: e.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  String _mergeStatus(
      Map<String, String> existing, List<ExtractedString> strings) {
    if (existing.isEmpty) return 'created';
    final newKeys =
        strings.where((s) => !existing.containsKey(s.key)).length;
    return newKeys > 0 ? 'merged (+$newKeys new key(s))' : 'no new keys';
  }
}
