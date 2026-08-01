import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../models/extracted_string.dart';
import 'ast_visitor.dart';

/// Scans all Dart files inside a Flutter project's `lib/` directory and
/// returns every hardcoded UI string found.
///
/// Internally, [FileScanner] uses `package:analyzer` to produce a full AST
/// for each file and then runs [StringExtractorVisitor] to collect strings.
/// Files that cannot be read or parsed are skipped with a warning on stderr.
///
/// Usage:
/// ```dart
/// final scanner = FileScanner();
/// final strings = await scanner.scan('/path/to/my_flutter_app');
/// ```
class FileScanner {
  /// Scans `[projectPath]/lib/` for hardcoded UI strings.
  ///
  /// Recursively visits every `.dart` file found under the `lib/` directory.
  /// Returns a flat, unordered list of [ExtractedString] objects — one entry
  /// per unique string occurrence (same value on different lines = two entries).
  ///
  /// Throws [ArgumentError] when [projectPath] does not contain a `lib/`
  /// directory, which indicates it is not a Flutter/Dart project root.
  Future<List<ExtractedString>> scan(String projectPath) async {
    final libDir = Directory(p.join(projectPath, 'lib'));

    if (!libDir.existsSync()) {
      throw ArgumentError(
        'No lib/ directory found at "$projectPath". '
        'Ensure the path points to the root of a Flutter project.',
      );
    }

    final results = <ExtractedString>[];

    // Recursively list all entities in lib/ and process .dart files.
    await for (final entity in libDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final extracted = _parseFile(entity);
        results.addAll(extracted);
      }
    }

    return results;
  }

  /// Parses a single [file] and returns the UI strings extracted from it.
  ///
  /// Returns an empty list on read errors or parse failures, printing a
  /// diagnostic warning to stderr so the caller can continue processing other
  /// files without crashing.
  List<ExtractedString> _parseFile(File file) {
    final String content;

    try {
      content = file.readAsStringSync();
    } catch (e) {
      stderr.writeln(
        '[language_extract] Warning: could not read ${file.path}\n  $e',
      );
      return [];
    }

    try {
      // parseString builds a full AST without requiring a Dart analysis context,
      // making it suitable for a CLI that runs outside of a build system.
      // throwIfDiagnostics: false lets us handle files with minor errors
      // gracefully — the partial AST still contains extractable strings.
      final result = parseString(
        content: content,
        featureSet: FeatureSet.latestLanguageVersion(),
        path: file.path,
        throwIfDiagnostics: false,
      );

      final visitor = StringExtractorVisitor(
        filePath: file.path,
        fileName: p.basename(file.path),
      );

      result.unit.visitChildren(visitor);

      return visitor.results;
    } catch (e) {
      stderr.writeln(
        '[language_extract] Warning: could not parse ${file.path}\n  $e',
      );
      return [];
    }
  }
}
