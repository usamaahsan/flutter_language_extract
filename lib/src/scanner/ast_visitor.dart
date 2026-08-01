import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/extracted_string.dart'; // also re-exports StringSegment types

/// Walks a parsed Dart AST and collects hardcoded UI strings.
///
/// Two complementary filters decide whether a string is extracted:
///
/// 1. **Value filter** ([_shouldSkipByValue]) — rejects strings that are
///    clearly not translatable UI text based on their content alone (routes,
///    URLs, identifier-like strings, asset paths, etc.).
///
/// 2. **Context filter** ([_isInUiContext]) — accepts strings only when they
///    appear inside a recognized Flutter widget constructor or as the value of
///    a well-known UI-related named parameter (e.g., `hintText:`, `label:`).
///
/// For interpolated strings (e.g., `'Welcome $user'`), the visitor captures
/// the full segment list so generators can reconstruct the value with the
/// correct placeholder syntax and [SourceReplacer] can build the right call.
///
/// Usage:
/// ```dart
/// final visitor = StringExtractorVisitor(
///   filePath: '/path/to/home_screen.dart',
///   fileName: 'home_screen.dart',
/// );
/// compilationUnit.visitChildren(visitor);
/// print(visitor.results); // List<ExtractedString>
/// ```
class StringExtractorVisitor extends RecursiveAstVisitor<void> {
  /// All UI strings successfully extracted from the visited AST.
  final List<ExtractedString> results = [];

  /// Absolute path to the file being visited.
  final String filePath;

  /// Base file name (e.g., `home_screen.dart`).
  final String fileName;

  // ---------------------------------------------------------------------------
  // Widget and parameter allow-lists
  // ---------------------------------------------------------------------------

  /// Flutter widget class names whose constructor arguments are considered
  /// potential UI strings. Add custom widget names here to extend coverage.
  static const Set<String> _uiWidgets = {
    // ── Text display ──────────────────────────────────────────────────────────
    'Text', 'SelectableText', 'RichText',

    // ── App bars ──────────────────────────────────────────────────────────────
    'AppBar', 'SliverAppBar', 'CupertinoNavigationBar',

    // ── Dialogs & overlays ────────────────────────────────────────────────────
    'AlertDialog', 'SimpleDialog', 'CupertinoAlertDialog',
    'SnackBar', 'MaterialBanner',

    // ── Buttons ───────────────────────────────────────────────────────────────
    'ElevatedButton', 'TextButton', 'OutlinedButton',
    'FilledButton', 'CupertinoButton',
    'FloatingActionButton', 'IconButton',

    // ── Text input ────────────────────────────────────────────────────────────
    'TextField', 'TextFormField', 'CupertinoTextField',
    'SearchBar', 'InputDecoration',

    // ── List / tile widgets ───────────────────────────────────────────────────
    'ListTile', 'CheckboxListTile', 'RadioListTile',
    'SwitchListTile', 'ExpansionTile',

    // ── Navigation ────────────────────────────────────────────────────────────
    'BottomNavigationBarItem', 'NavigationDestination',
    'NavigationRailDestination', 'Tab',

    // ── Chips ─────────────────────────────────────────────────────────────────
    'Chip', 'InputChip', 'ActionChip', 'FilterChip', 'ChoiceChip',

    // ── Tooltips / badges ─────────────────────────────────────────────────────
    'Tooltip', 'Badge',

    // ── Drawers ───────────────────────────────────────────────────────────────
    'DrawerHeader',

    // ── Dropdowns / menus ─────────────────────────────────────────────────────
    'DropdownMenuItem', 'DropdownButton', 'PopupMenuItem',

    // ── Data tables ───────────────────────────────────────────────────────────
    'DataColumn', 'DataCell',

    // ── Stepper ───────────────────────────────────────────────────────────────
    'Step',
  };

  /// Named constructor parameters that indicate a UI string regardless of
  /// which widget they belong to.
  static const Set<String> _uiNamedParams = {
    'title', 'label', 'labelText',
    'hint', 'hintText', 'helperText',
    'errorText', 'prefixText', 'suffixText', 'counterText',
    'tooltip', 'semanticsLabel', 'placeholder',
    'buttonText', 'cancelText', 'confirmText',
    'message',  // Tooltip.message
    'header', 'footer',
  };

  /// Maximum AST parent levels to traverse when checking UI context.
  static const int _maxParentDepth = 8;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  StringExtractorVisitor({
    required this.filePath,
    required this.fileName,
  });

  // ---------------------------------------------------------------------------
  // Visitor overrides
  // ---------------------------------------------------------------------------

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    // Adjacent string literals are Dart's compile-time concatenation:
    //   'Hello ' 'World'  →  'Hello World'
    //   'Line one\n' 'Line two'  →  'Line one\nLine two'
    //
    // We visit the AdjacentStrings node as a single unit and extract the
    // concatenated value. We do NOT call super so the individual child
    // strings are not visited again — that would create duplicate extractions
    // and broken replacements (two separate `.tr` calls side by side).
    final segments = <StringSegment>[];
    var hasInterpolation = false;

    for (final part in node.strings) {
      if (part is SimpleStringLiteral) {
        segments.add(StaticSegment(part.value));
      } else if (part is StringInterpolation) {
        hasInterpolation = true;
        for (final element in part.elements) {
          if (element is InterpolationString) {
            segments.add(StaticSegment(element.value));
          } else if (element is InterpolationExpression) {
            final expr = element.expression.toSource();
            segments.add(DynamicSegment(
              expression: expr,
              paramKey: _expressionToParamKey(expr),
            ));
          }
        }
      }
    }

    final staticText =
        segments.whereType<StaticSegment>().map((s) => s.text).join();

    _tryExtract(
      value: staticText,
      node: node,
      hasInterpolation: hasInterpolation,
      segments: segments,
    );
    // Intentionally no super call — children must not be visited individually.
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    // Skip strings that are part of an AdjacentStrings — handled as a unit above.
    if (node.parent is AdjacentStrings) return;

    // Skip strings that live inside a ${...} interpolation expression.
    // e.g., `${table.name ?? 'Table'}` — the `'Table'` fallback is a string
    // literal but it is not a UI string to translate; it is part of a Dart
    // expression. Extracting it would produce a broken extra `.tr` call.
    if (_isInsideInterpolationExpression(node)) return;

    _tryExtract(
      value: node.value,
      node: node,
      hasInterpolation: false,
      segments: [StaticSegment(node.value)],
    );
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    // Skip interpolations that are children of an AdjacentStrings node.
    if (node.parent is AdjacentStrings) return;

    // Skip string interpolations that are themselves inside a ${...} expression.
    if (_isInsideInterpolationExpression(node)) return;
    // Build the ordered segment list from the interpolation elements.
    final segments = <StringSegment>[];

    for (final element in node.elements) {
      if (element is InterpolationString) {
        segments.add(StaticSegment(element.value));
      } else if (element is InterpolationExpression) {
        // element.expression is the Dart AST node inside ${ }.
        // For `$user` the expression is a SimpleIdentifier;
        // for `${user.firstName}` it is a PropertyAccess, etc.
        final expr = element.expression.toSource();
        segments.add(DynamicSegment(
          expression: expr,
          paramKey: _expressionToParamKey(expr),
        ));
      }
    }

    // The plain text used for key generation and value filtering:
    // join only the static portions.
    final staticText =
        segments.whereType<StaticSegment>().map((s) => s.text).join();

    _tryExtract(
      value: staticText,
      node: node,
      hasInterpolation: true,
      segments: segments,
    );
    super.visitStringInterpolation(node);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Core extraction logic — applies all filters and, if the string qualifies,
  /// appends an [ExtractedString] to [results].
  void _tryExtract({
    required String value,
    required AstNode node,
    required bool hasInterpolation,
    required List<StringSegment> segments,
  }) {
    // Skip strings that were already converted in a previous run of the CLI.
    // e.g., 'welcome_home'.tr / 'key'.trParams({}) / 'key'.tr()
    // Running the tool twice must be safe and produce the same result.
    if (_isAlreadyLocalized(node)) return;

    // For pure-dynamic interpolations like `'$title'` the static text is empty.
    // We still want to extract these if they are in a UI context — the param
    // key will be used to generate a meaningful key (e.g., `home_screen_title`).
    final hasDynamicParts = segments.any((s) => s is DynamicSegment);

    if (!hasDynamicParts && _shouldSkipByValue(value)) return;
    if (!_isInUiContext(node)) return;

    // Find the nearest ancestor widget constructor that carries a `const`
    // keyword. When --replace rewrites this string to a runtime call, that
    // `const` becomes invalid and must also be removed.
    final constWidget = _findNearestConstWidget(node);

    results.add(ExtractedString(
      value: value,
      filePath: filePath,
      fileName: fileName,
      line: _lineOf(node),
      hasInterpolation: hasInterpolation,
      offset: node.offset,
      length: node.length,
      segments: segments,
      constKeywordOffset: constWidget?.keyword?.offset,
      constKeywordLength: constWidget?.keyword?.length,
    ));
  }

  /// Walks up the parent chain to find the nearest [InstanceCreationExpression]
  /// with an explicit `const` keyword.
  ///
  /// We do NOT restrict to [_uiWidgets] here — once a string has passed the
  /// context filter it may be inside any constructor (including custom widgets
  /// like `SignupSectionLabel(label: '...')`). Any `const` on a constructor
  /// whose argument is replaced with a runtime call (`.tr`, etc.) must be
  /// removed, regardless of whether the class is a known Flutter widget.
  InstanceCreationExpression? _findNearestConstWidget(AstNode node) {
    AstNode? current = node.parent;
    int depth = 0;

    while (current != null && depth < _maxParentDepth) {
      if (current is InstanceCreationExpression && current.keyword != null) {
        return current;
      }
      if (current is FunctionBody || current is ClassDeclaration) break;
      current = current.parent;
      depth++;
    }
    return null;
  }

  /// Returns `true` when [node] is already the target of a localization call,
  /// meaning it was converted by a previous run of the CLI.
  ///
  /// Detected patterns (all packages):
  ///
  /// | Expression                        | Parent node type      |
  /// |-----------------------------------|-----------------------|
  /// | `'key'.tr`                        | [PropertyAccess]      |
  /// | `'key'.tr()`                      | [MethodInvocation]    |
  /// | `'key'.trParams({...})`           | [MethodInvocation]    |
  /// | `'key'.tr(namedArgs: {...})`      | [MethodInvocation]    |
  ///
  /// intl strings (`AppLocalizations.of(context)!.method`) contain no string
  /// literal for the key, so they are inherently idempotent.
  bool _isAlreadyLocalized(AstNode node) {
    final parent = node.parent;

    // 'key'.tr  →  PropertyAccess whose propertyName is 'tr'
    if (parent is PropertyAccess && parent.propertyName.name == 'tr') {
      return true;
    }

    // 'key'.tr() / 'key'.trParams({}) / 'key'.tr(namedArgs: {})
    // →  MethodInvocation whose target is this string node
    if (parent is MethodInvocation) {
      const localizedMethods = {'tr', 'trParams'};
      if (localizedMethods.contains(parent.methodName.name)) return true;
    }

    return false;
  }

  /// Returns `true` when [value] is clearly not a translatable UI string.
  bool _shouldSkipByValue(String value) {
    final v = value.trim();

    if (v.isEmpty) return true;
    if (v.length == 1) return true;

    // Route strings and URLs
    if (v.startsWith('/')) return true;
    if (v.startsWith('http://') || v.startsWith('https://')) return true;

    // Pure numbers
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(v)) return true;

    // Asset / file paths: has a dot but no space
    if (v.contains('.') && !v.contains(' ')) return true;

    // Identifier-like strings: camelCase, snake_case, SCREAMING_SNAKE
    if (RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(v)) return true;
    if (RegExp(r'^[a-z_][a-z0-9_]+$').hasMatch(v)) return true;
    if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(v)) return true;

    // Hex colors
    if (RegExp(r'^#[0-9a-fA-F]+$').hasMatch(v)) return true;

    // Reverse-domain identifiers
    if (RegExp(r'^[a-z]+(\.[a-zA-Z][a-zA-Z0-9]*)+$').hasMatch(v)) return true;

    return false;
  }

  /// Returns `true` when [node] appears inside a recognized UI widget or as
  /// the value of a UI-related named parameter.
  bool _isInUiContext(AstNode node) {
    AstNode? current = node.parent;
    int depth = 0;

    while (current != null && depth < _maxParentDepth) {
      // Named parameter: e.g., hintText: 'Search...'
      if (current is NamedExpression) {
        if (_uiNamedParams.contains(current.name.label.name)) return true;
      }

      // Widget constructor: e.g., Text('Hello'), AppBar(...)
      if (current is InstanceCreationExpression) {
        // In analyzer 12.x, NamedType.name is a Token — use .lexeme.
        final typeName = current.constructorName.type.name.lexeme;
        if (_uiWidgets.contains(typeName)) return true;
      }

      // Stop at function/class boundaries.
      if (current is FunctionBody || current is ClassDeclaration) break;

      current = current.parent;
      depth++;
    }

    return false;
  }

  /// Returns `true` when [node] is nested inside an [InterpolationExpression].
  ///
  /// Strings inside `${...}` blocks are part of a Dart expression (e.g., a
  /// null-coalescing fallback `${name ?? 'Guest'}`). They must not be
  /// extracted or replaced independently — only the surrounding interpolated
  /// string as a whole is a candidate for localization.
  bool _isInsideInterpolationExpression(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is InterpolationExpression) return true;
      // Stop at boundaries where the interpolation cannot extend.
      if (current is FunctionBody || current is ClassDeclaration) break;
      current = current.parent;
    }
    return false;
  }

  /// Converts a Dart expression string to a camelCase parameter key.
  ///
  /// **Null-coalescing fallbacks are stripped first** so the key reflects the
  /// meaningful variable name, not the fallback literal:
  ///   `'table.tableName ?? \'Table\''` → strip → `'table.tableName'` → `'tableTableName'`
  ///
  /// Simple dotted property chains are converted to camelCase:
  ///   `'user'`           → `'user'`
  ///   `'user.firstName'` → `'userFirstName'`
  ///   `'items.length'`   → `'itemsLength'`
  ///
  /// Complex expressions are sanitized to alphanumeric words and joined:
  ///   `'count + 1'` → `'count1'`
  String _expressionToParamKey(String expression) {
    // Strip null-coalescing fallback so `table.name ?? 'N/A'` → `table.name`.
    final stripped = expression.split('??').first.trim();

    final parts = stripped.split('.');
    // Simple dotted chain: each part must be a plain identifier.
    if (parts.every((p) => RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(p))) {
      return parts.first +
          parts
              .skip(1)
              .map((p) => p[0].toUpperCase() + p.substring(1))
              .join();
    }

    // Complex expression: sanitize to alphanumeric words and camelCase-join.
    final words = stripped
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return 'param';
    return words.first.toLowerCase() +
        words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
  }

  /// Returns the 1-based line number of [node] within its compilation unit.
  int _lineOf(AstNode node) {
    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) return 0;
    return unit.lineInfo.getLocation(node.offset).lineNumber;
  }
}
