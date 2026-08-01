import '../models/extracted_string.dart';

/// Contract that every localization output generator must implement.
///
/// Each generator receives the full list of deduplicated [ExtractedString]s
/// (with keys already assigned by [KeyGenerator]) and writes one or more
/// output files into the target Flutter project.
///
/// The locale whose code matches [sourceLocale] receives the real extracted
/// values. All other locales preserve existing human translations and receive
/// empty placeholders for new keys.
abstract class OutputGenerator {
  /// Writes localization output files into [projectPath].
  ///
  /// [strings]      — deduplicated list with [ExtractedString.key] already set.
  /// [projectPath]  — root of the target Flutter project (contains `lib/`).
  /// [locales]      — all locale codes to generate, e.g. `['en_US', 'ar_AR']`.
  /// [sourceLocale] — the locale whose file is populated with real extracted
  ///                  values. Must be present in [locales]. Defaults to the
  ///                  first entry when callers omit it.
  Future<void> generate({
    required List<ExtractedString> strings,
    required String projectPath,
    required List<String> locales,
    required String sourceLocale,
  });

  // ---------------------------------------------------------------------------
  // Shared utilities available to all generators
  // ---------------------------------------------------------------------------

  /// Escapes a string value for use inside a Dart single-quoted string literal.
  ///
  /// [SimpleStringLiteral.value] and [InterpolationString.value] return the
  /// **interpreted** string — i.e., escape sequences have already been decoded
  /// into their actual characters (real newline, real tab, etc.). This method
  /// re-encodes those characters so the output `.dart` file is valid Dart.
  ///
  /// Replacement order matters: backslash must be escaped first so later
  /// replacements don't accidentally double-escape already-added backslashes.
  String escapeDartString(String value) => value
      .replaceAll(r'\', r'\\')   // \  →  \\   (must be first)
      .replaceAll('\n', r'\n')   // real newline  →  \n
      .replaceAll('\r', r'\r')   // real CR       →  \r
      .replaceAll('\t', r'\t')   // real tab      →  \t
      .replaceAll("'", r"\'");   // '  →  \'

  /// Escapes characters that have special meaning inside JSON string values.
  String escapeJsonString(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');

  /// Converts a locale code to a lowerCamelCase Dart variable name.
  ///
  /// Examples:
  ///   `en_US`  → `enUS`
  ///   `ar_AR`  → `arAR`
  ///   `fr`     → `fr`
  ///   `zh_CN`  → `zhCN`
  String localeToVarName(String locale) => locale.replaceAllMapped(
        RegExp(r'_([A-Za-z]+)'),
        (m) => m.group(1)!.toUpperCase(),
      );
}
