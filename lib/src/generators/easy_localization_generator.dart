import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/extracted_string.dart';
import 'base_generator.dart';

/// Generates easy_localization JSON translation files for a Flutter project.
///
/// **Output structure inside the target project:**
/// ```
/// assets/
///   translations/
///     en.json   ← source locale (values from code, always regenerated)
///     ar.json   ← other locales (existing translations preserved,
///                  new keys appended as empty placeholders)
/// ```
class EasyLocalizationGenerator extends OutputGenerator {
  @override
  Future<void> generate({
    required List<ExtractedString> strings,
    required String projectPath,
    required List<String> locales,
    required String sourceLocale,
  }) async {
    final outputDir = Directory(p.join(projectPath, 'assets', 'translations'))
      ..createSync(recursive: true);

    for (final locale in locales) {
      await _writeJsonFile(
        outputDir: outputDir,
        locale: locale,
        strings: strings,
        isSourceLocale: locale == sourceLocale,
      );
    }

    stdout.writeln('[easy_localization] Written to ${outputDir.path}');
    _printNextSteps(projectPath, locales);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _writeJsonFile({
    required Directory outputDir,
    required String locale,
    required List<ExtractedString> strings,
    required bool isSourceLocale,
  }) async {
    final file = File(p.join(outputDir.path, '$locale.json'));

    // For non-source locales, load any translations a human already added so
    // they survive subsequent CLI runs. New keys get empty placeholders.
    final existing = isSourceLocale ? <String, String>{} : _parseExisting(file);

    final translations = <String, String>{
      for (final s in strings)
        s.key!: isSourceLocale
            // Source locale: real value with {param} placeholder syntax.
            ? s.buildLocaleValue((k) => '{$k}')
            // Non-source: keep existing human translation or empty placeholder.
            : (existing[s.key!] ?? ''),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(translations),
    );

    final status = isSourceLocale
        ? 'regenerated'
        : _mergeStatus(existing, strings);
    stdout.writeln('  ✔ $locale.json — $status');
  }

  /// Prints one-time setup instructions for easy_localization.
  ///
  /// Checks whether the assets entry already exists in `pubspec.yaml` so the
  /// message is suppressed on subsequent runs.
  void _printNextSteps(String projectPath, List<String> locales) {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    final pubspecContent =
        pubspec.existsSync() ? pubspec.readAsStringSync() : '';

    // If pubspec already declares the translations asset path, stay quiet.
    if (pubspecContent.contains('assets/translations/')) return;

    final supportedLocales = locales
        .map((l) => "Locale('${l.split('_').first}'${l.contains('_') ? ", '${l.split('_').last}'" : ''})")
        .join(', ');

    stdout.writeln('''
┌─────────────────────────────────────────────────────────┐
│  easy_localization one-time setup required              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. Declare the asset path in pubspec.yaml:             │
│                                                         │
│     flutter:                                            │
│       assets:                                           │
│         - assets/translations/                          │
│                                                         │
│  2. Wrap your app in main.dart:                         │
│                                                         │
│     void main() async {                                 │
│       WidgetsFlutterBinding.ensureInitialized();        │
│       await EasyLocalization.ensureInitialized();       │
│       runApp(                                           │
│         EasyLocalization(                               │
│           supportedLocales: [$supportedLocales],
│           path: 'assets/translations',                  │
│           fallbackLocale: ${locales.isEmpty ? "Locale('en')" : "Locale('${locales.first.split('_').first}')"},                    │
│           child: MyApp(),                               │
│         ),                                              │
│       );                                                │
│     }                                                   │
│                                                         │
│  3. In MaterialApp / CupertinoApp add:                  │
│                                                         │
│     localizationsDelegates:                             │
│       context.localizationDelegates,                    │
│     supportedLocales: context.supportedLocales,         │
└─────────────────────────────────────────────────────────┘''');
  }

  /// Reads an existing JSON translation file and returns its key→value map.
  /// Returns an empty map on missing file or parse error.
  Map<String, String> _parseExisting(File file) {
    if (!file.existsSync()) return {};
    try {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  String _mergeStatus(
    Map<String, String> existing,
    List<ExtractedString> strings,
  ) {
    if (existing.isEmpty) return 'created';
    final newKeys = strings.where((s) => !existing.containsKey(s.key)).length;
    return newKeys > 0 ? 'merged (+$newKeys new key(s))' : 'no new keys';
  }
}
