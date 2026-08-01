import 'string_segment.dart';

export 'string_segment.dart';

/// Represents a single hardcoded UI string found in a Dart source file.
///
/// Instances are created by [StringExtractorVisitor] and enriched in two
/// passes:
/// - [KeyGenerator.assignKeys] sets the [key] field.
/// - [SourceReplacer] uses [offset] and [length] to rewrite source files.
class ExtractedString {
  /// The plain-text value of the string.
  ///
  /// For simple strings this is the full value (e.g., `'Hello User'` → `Hello User`).
  /// For interpolated strings this is only the **static portions joined**
  /// (e.g., `'Welcome $user'` → `Welcome `). Use [buildLocaleValue] to get
  /// the full template with placeholders for locale map generation.
  final String value;

  /// Absolute path to the Dart source file containing this string.
  final String filePath;

  /// Base file name (e.g., `home_screen.dart`). Used for key generation.
  final String fileName;

  /// 1-based line number within [filePath] where this string starts.
  final int line;

  /// Whether this string uses Dart string interpolation (e.g., `'Hi $name'`).
  final bool hasInterpolation;

  /// Byte offset of the opening quote of this string node within [filePath].
  ///
  /// Used by [SourceReplacer] to locate and replace the string in source.
  /// Defaults to `0` when not needed (e.g., in unit tests).
  final int offset;

  /// Byte length of the full string node in source, including quotes.
  ///
  /// `source.substring(offset, offset + length)` yields the original literal.
  /// Defaults to `0` when not needed (e.g., in unit tests).
  final int length;

  /// Offset of the `const` keyword on the nearest ancestor widget constructor,
  /// if one exists. Null when no `const` keyword needs to be removed.
  ///
  /// Example: `const Text('Hello')` → offset of the `const` token.
  /// Also handles implicit const: `const Column(children: [Text('Hello')])`
  /// → offset of Column's `const`, since removing the string breaks it too.
  ///
  /// [SourceReplacer] removes this keyword (and its trailing space) when
  /// `--replace` is active.
  final int? constKeywordOffset;

  /// Length of the `const` keyword token (always 5 — `'const'.length`).
  /// Stored for symmetry; [SourceReplacer] uses this to know how many chars
  /// to remove starting at [constKeywordOffset].
  final int? constKeywordLength;

  /// Ordered list of segments making up this string.
  ///
  /// For simple strings this is a single [StaticSegment].
  /// For interpolated strings this alternates between [StaticSegment] and
  /// [DynamicSegment] following the order they appear in source.
  ///
  /// Use [dynamicSegments] for quick access to only the dynamic parts.
  final List<StringSegment> segments;

  /// The generated snake_case localization key (e.g., `home_screen_welcome_home`).
  ///
  /// Null until [KeyGenerator.assignKeys] has been called.
  String? key;

  ExtractedString({
    required this.value,
    required this.filePath,
    required this.fileName,
    required this.line,
    this.hasInterpolation = false,
    this.offset = 0,
    this.length = 0,
    this.segments = const [],
    this.constKeywordOffset,
    this.constKeywordLength,
    this.key,
  });

  /// Convenience accessor for only the [DynamicSegment]s in [segments].
  List<DynamicSegment> get dynamicSegments =>
      segments.whereType<DynamicSegment>().toList();

  // ---------------------------------------------------------------------------
  // Locale value reconstruction
  // ---------------------------------------------------------------------------

  /// Builds the locale map value string, substituting each [DynamicSegment]
  /// with the placeholder format expected by the target i18n package.
  ///
  /// [placeholderFn] receives the [DynamicSegment.paramKey] and should return
  /// the package-specific placeholder string:
  ///
  /// | Package           | placeholderFn           | Example output     |
  /// |-------------------|-------------------------|--------------------|
  /// | GetX              | `(k) => '@$k'`          | `Welcome @user`    |
  /// | easy_localization | `(k) => '{$k}'`         | `Welcome {user}`   |
  /// | intl (ARB)        | `(k) => '{$k}'`         | `Welcome {user}`   |
  ///
  /// For non-interpolated strings, returns [value] unchanged regardless of
  /// [placeholderFn].
  String buildLocaleValue(String Function(String paramKey) placeholderFn) {
    if (!hasInterpolation || segments.isEmpty) return value;

    final buffer = StringBuffer();
    for (final segment in segments) {
      switch (segment) {
        case StaticSegment(:final text):
          buffer.write(text);
        case DynamicSegment(:final paramKey):
          buffer.write(placeholderFn(paramKey));
      }
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'ExtractedString(key: $key, value: "$value", file: $fileName:$line)';
}
