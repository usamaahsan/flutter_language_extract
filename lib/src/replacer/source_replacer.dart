import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/extracted_string.dart'; // also re-exports StringSegment types

/// Rewrites Dart source files to replace hardcoded string literals with the
/// appropriate localized calls for the target i18n package.
///
/// **Replacement examples:**
///
/// GetX:
/// ```dart
/// // Before
/// import 'package:get/get.dart';   ← added automatically
/// Text('Welcome home')
/// Text('Hello $user')
///
/// // After
/// Text('home_screen_welcome_home'.tr)
/// Text('home_screen_hello_user'.trParams({'user': user.toString()}))
/// ```
///
/// **How it works:**
/// Each [ExtractedString] carries [offset] and [length] of its source node.
/// All edits (string replacements, const removals, import insertion) are
/// collected and applied in **descending offset order** so no edit invalidates
/// the position of another.
class SourceReplacer {
  /// Rewrites source files for all strings in [strings].
  ///
  /// [strings]     — full list (including duplicates) so every occurrence is
  ///                 rewritten, not just the first per key.
  /// [package]     — one of `'getx'`, `'intl'`, `'easy_localization'`.
  /// [projectPath] — Flutter project root; used to read `pubspec.yaml` for
  ///                 the package name (needed to build the intl import path).
  Future<void> replace({
    required List<ExtractedString> strings,
    required String package,
    required String projectPath,
  }) async {
    final importLine = _resolveImport(package, projectPath);

    // Group strings by file so we can process each file in one pass.
    final byFile = <String, List<ExtractedString>>{};
    for (final s in strings) {
      byFile.putIfAbsent(s.filePath, () => []).add(s);
    }

    var filesModified = 0;
    for (final entry in byFile.entries) {
      final modified = await _replaceInFile(
        filePath: entry.key,
        strings: entry.value,
        package: package,
        importLine: importLine,
      );
      if (modified) filesModified++;
    }

    stdout.writeln('\n[replace] Modified $filesModified file(s).');
  }

  // ---------------------------------------------------------------------------
  // Import resolution
  // ---------------------------------------------------------------------------

  /// Returns the import statement that must be present in every modified file.
  ///
  /// For intl, reads `pubspec.yaml` to get the project's package name so the
  /// generated `AppLocalizations` class can be found at the right path.
  String _resolveImport(String package, String projectPath) {
    return switch (package) {
      'getx' => "import 'package:get/get.dart';",
      'easy_localization' =>
        "import 'package:easy_localization/easy_localization.dart';",
      'intl' => _intlImport(projectPath),
      _ => throw ArgumentError('Unknown package: $package'),
    };
  }

  /// Constructs the intl AppLocalizations import path.
  ///
  /// `flutter gen-l10n` with default settings outputs to:
  ///   `package:flutter_gen/gen_l10n/app_localizations.dart`
  ///
  /// If a custom `output-localization-file` is set in `l10n.yaml` the user
  /// will need to adjust this import manually. We default to the standard path.
  String _intlImport(String projectPath) {
    // Read the package name from pubspec.yaml so we can point to the generated
    // file under lib/l10n when flutter_gen is not being used.
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final content = pubspec.readAsStringSync();
      final match =
          RegExp(r'^name:\s+(\S+)', multiLine: true).firstMatch(content);
      if (match != null) {
        final packageName = match.group(1)!;
        // flutter gen-l10n standard output — works for most projects.
        return "import 'package:$packageName/l10n/app_localizations.dart';";
      }
    }
    // Fallback to the flutter_gen synthetic package path.
    return "import 'package:flutter_gen/gen_l10n/app_localizations.dart';";
  }

  // ---------------------------------------------------------------------------
  // Per-file replacement
  // ---------------------------------------------------------------------------

  /// Applies all edits for [strings] in a single file.
  ///
  /// Three kinds of edits are collected and applied in one descending-offset
  /// pass to avoid offset drift:
  ///
  /// 1. **String replacements** — literal → localized call.
  /// 2. **Const removals** — strip `const` keywords made invalid by step 1.
  /// 3. **Import insertion** — add the package import if not already present.
  Future<bool> _replaceInFile({
    required String filePath,
    required List<ExtractedString> strings,
    required String package,
    required String importLine,
  }) async {
    var content = File(filePath).readAsStringSync();

    final edits = <({int start, int end, String replacement})>[];

    // ── 1. String replacements ──────────────────────────────────────────────
    for (final s in strings) {
      if (s.key == null || (s.offset == 0 && s.length == 0)) continue;
      edits.add((
        start: s.offset,
        end: s.offset + s.length,
        replacement: _buildReplacement(s, package),
      ));
    }

    // ── 2. Const keyword removals ───────────────────────────────────────────
    // Deduplicate: a const widget with several replaced strings only needs its
    // `const` removed once.
    final seenConstOffsets = <int>{};
    for (final s in strings) {
      final co = s.constKeywordOffset;
      final cl = s.constKeywordLength;
      if (co == null || cl == null) continue;
      if (!seenConstOffsets.add(co)) continue;
      // Remove `const` + the space that follows it → `const Text(` becomes `Text(`.
      edits.add((start: co, end: co + cl + 1, replacement: ''));
    }

    if (edits.isEmpty) return false;

    // ── 3. Import insertion ─────────────────────────────────────────────────
    // Skip if the file already imports the package (exact line match).
    if (!content.contains(importLine)) {
      final insertOffset = _importInsertOffset(content);
      // Inserting at a low offset means this edit runs LAST in the descending
      // sort — correct, since all string edits are at higher offsets.
      edits.add((
        start: insertOffset,
        end: insertOffset,
        replacement: '\n$importLine',
      ));
    }

    // ── Apply all edits highest-offset first ────────────────────────────────
    edits.sort((a, b) => b.start.compareTo(a.start));
    for (final edit in edits) {
      content = content.substring(0, edit.start) +
          edit.replacement +
          content.substring(edit.end);
    }

    File(filePath).writeAsStringSync(content);
    stdout.writeln('  ✔ ${filePath.split('/').last}');
    return true;
  }

  /// Returns the character offset at which to insert a new import statement.
  ///
  /// Inserts immediately after the last existing `import '...';` line so the
  /// new import joins the existing import block. Falls back to offset 0 (top
  /// of file) when no imports are present.
  int _importInsertOffset(String content) {
    // Match both single- and double-quoted import directives.
    final importRegex =
        RegExp(r"""^import\s+['"].*?['"];""", multiLine: true);
    final matches = importRegex.allMatches(content);
    if (matches.isNotEmpty) return matches.last.end;

    // No existing imports — prepend to the file.
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Replacement builders
  // ---------------------------------------------------------------------------

  String _buildReplacement(ExtractedString s, String package) {
    final key = s.key!;
    final params = s.dynamicSegments;
    return switch (package) {
      'getx' => _getxReplacement(key, params),
      'easy_localization' => _easyLocReplacement(key, params),
      'intl' => _intlReplacement(key, params),
      _ => throw ArgumentError('Unknown package: $package'),
    };
  }

  // ── GetX ──────────────────────────────────────────────────────────────────

  /// `'key'.tr`  or  `'key'.trParams({'param': expr.toString()})`
  ///
  /// GetX's `trParams` requires `Map<String, String>` — `.toString()` ensures
  /// no type error when the interpolated value is an int, double, etc.
  String _getxReplacement(String key, List<DynamicSegment> params) {
    if (params.isEmpty) return "'$key'.tr";
    // Wrap each expression in parentheses before .toString() so operator
    // precedence doesn't cause issues with complex expressions like
    // `table.name ?? 'Guest'` → `(table.name ?? 'Guest').toString()`
    // instead of the broken `table.name ?? 'Guest'.toString()`.
    final entries = params
        .map((p) => "'${p.paramKey}': (${p.expression}).toString()")
        .join(', ');
    return "'$key'.trParams({$entries})";
  }

  // ── easy_localization ─────────────────────────────────────────────────────

  String _easyLocReplacement(String key, List<DynamicSegment> params) {
    if (params.isEmpty) return "'$key'.tr()";
    final entries = params
        .map((p) => "'${p.paramKey}': (${p.expression}).toString()")
        .join(', ');
    return "'$key'.tr(namedArgs: {$entries})";
  }

  // ── intl ──────────────────────────────────────────────────────────────────

  String _intlReplacement(String key, List<DynamicSegment> params) {
    final method = _snakeToCamel(key);
    if (params.isEmpty) return 'AppLocalizations.of(context)!.$method';
    final args =
        params.map((p) => '(${p.expression}).toString()').join(', ');
    return 'AppLocalizations.of(context)!.$method($args)';
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// `home_screen_welcome_home` → `homeScreenWelcomeHome`
  String _snakeToCamel(String key) {
    final parts = key.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
            .join();
  }
}
