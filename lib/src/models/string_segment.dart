/// Represents one segment of a Dart string interpolation.
///
/// A string like `'Welcome $user, you have $count items'` is broken into:
/// ```
/// StaticSegment('Welcome ')
/// DynamicSegment(expression: 'user',  paramKey: 'user')
/// StaticSegment(', you have ')
/// DynamicSegment(expression: 'count', paramKey: 'count')
/// StaticSegment(' items')
/// ```
///
/// Generators use these segments to reconstruct locale map values with the
/// correct placeholder syntax (e.g., `@user` for GetX, `{user}` for intl).
sealed class StringSegment {
  const StringSegment();
}

/// A literal (non-interpolated) portion of a string.
final class StaticSegment extends StringSegment {
  /// The raw text of this segment, exactly as it appears in source.
  final String text;
  const StaticSegment(this.text);
}

/// A dynamic (interpolated) portion of a string, e.g. `$variable` or `${expr}`.
final class DynamicSegment extends StringSegment {
  /// The original Dart expression as written in source (without `$` or `${}`).
  ///
  /// Examples: `'user'`, `'user.firstName'`, `'items.length'`
  final String expression;

  /// The sanitized key used in locale placeholder maps.
  ///
  /// Derived from [expression] by converting dotted property chains to
  /// camelCase. Used as the placeholder name in locale files and as the
  /// key in `.trParams({})` / `.tr(namedArgs: {})` calls.
  ///
  /// Examples: `'user'`, `'userFirstName'`, `'itemsLength'`
  final String paramKey;

  const DynamicSegment({required this.expression, required this.paramKey});
}
