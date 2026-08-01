import 'package:path/path.dart' as p;

import '../models/extracted_string.dart';

/// Generates and assigns snake_case localization keys to [ExtractedString]s.
///
/// **Key format:** `{file_name}_{value_words}` (max 4 value words)
///
/// Examples:
/// ```
/// home_screen.dart  +  'My Dashboard'   →  home_screen_my_dashboard
/// home_screen.dart  +  'Welcome home'   →  home_screen_welcome_home
/// profile_page.dart +  'Edit profile'   →  profile_page_edit_profile
/// HomeScreen.dart   +  'Sign in'        →  home_screen_sign_in
/// ```
///
/// **Deduplication:** Identical values within the *same* file reuse the same
/// key (the first occurrence wins). Across different files, keys are scoped by
/// file prefix so identical text can have different keys in different contexts.
///
/// **Collision resolution:** If two different values in the same file happen to
/// produce the same key (e.g., `'Ok!'` and `'Ok?'` both yield `_ok`), a
/// numeric suffix is appended: `home_screen_ok`, `home_screen_ok_2`, etc.
class KeyGenerator {
  /// Assigns a localization key to every [ExtractedString] in [strings].
  ///
  /// Mutates the [ExtractedString.key] field in-place. Call this once after
  /// [FileScanner.scan] has finished collecting all strings.
  void assignKeys(List<ExtractedString> strings) {
    // Tracks all keys in use (across all files) to detect cross-file collisions.
    final usedKeys = <String>{};

    // Per-file deduplication map: filePath → { value → assignedKey }
    // Ensures the same string value in the same file always gets the same key.
    final fileValueKeyMap = <String, Map<String, String>>{};

    for (final s in strings) {
      final valueMap = fileValueKeyMap.putIfAbsent(s.filePath, () => {});

      if (valueMap.containsKey(s.value)) {
        // Same value already seen in this file — reuse the key.
        s.key = valueMap[s.value];
      } else {
        final baseKey = _buildKey(s.filePath, s.value);
        final uniqueKey = _resolveCollision(baseKey, usedKeys);

        usedKeys.add(uniqueKey);
        valueMap[s.value] = uniqueKey;
        s.key = uniqueKey;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Builds an unvalidated key from [filePath] and [value].
  ///
  /// Falls back to `{filePrefix}_text` when the value produces no usable words
  /// (e.g., a string made entirely of special characters).
  String _buildKey(String filePath, String value) {
    final filePrefix = _fileNameToSnakeCase(filePath);
    final valueSuffix = _valueToSnakeCase(value);
    return valueSuffix.isEmpty ? '${filePrefix}_text' : '${filePrefix}_$valueSuffix';
  }

  /// Converts a file path to a snake_case string using only the base name.
  ///
  /// Handles both already-snake-case names and PascalCase/camelCase names:
  /// - `home_screen.dart`  → `home_screen`
  /// - `HomeScreen.dart`   → `home_screen`
  /// - `myWidget.dart`     → `my_widget`
  String _fileNameToSnakeCase(String filePath) {
    final name = p.basenameWithoutExtension(filePath);

    // Insert underscore before each uppercase letter that follows a lowercase
    // letter or digit (converts PascalCase → pascal_case).
    final snaked = name
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])([A-Z])'),
          (m) => '_${m.group(1)!.toLowerCase()}',
        )
        .toLowerCase()
        // Replace any non-alphanumeric characters (hyphens, dots, spaces) with _.
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        // Trim leading and trailing underscores.
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return snaked.isEmpty ? 'file' : snaked;
  }

  /// Converts a human-readable string value to a snake_case key suffix.
  ///
  /// Takes at most **4 words** to keep keys concise while remaining readable.
  /// Single-character words (e.g., 'a', 'I') are excluded to avoid noise.
  ///
  /// Examples:
  /// - `'Welcome to your dashboard!'` → `welcome_to_your_dashboard`
  /// - `'Tap to add a new item'`     → `tap_to_add_new` (≤4 words)
  /// - `'No items yet'`              → `no_items_yet`
  String _valueToSnakeCase(String value) {
    final words = value
        .toLowerCase()
        // Replace everything that is not a letter, digit, or whitespace with a space.
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)  // drop single-char words ('a', 'I', etc.)
        .take(4)                      // cap at 4 words for key brevity
        .toList();

    return words.join('_');
  }

  /// Returns a key based on [baseKey] that does not appear in [used].
  ///
  /// If [baseKey] is free, returns it as-is. Otherwise appends `_2`, `_3`, …
  /// until a free candidate is found.
  String _resolveCollision(String baseKey, Set<String> used) {
    if (!used.contains(baseKey)) return baseKey;

    var counter = 2;
    String candidate;
    do {
      candidate = '${baseKey}_$counter';
      counter++;
    } while (used.contains(candidate));

    return candidate;
  }
}
