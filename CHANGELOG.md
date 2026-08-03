## 1.0.2

- README: removed dev_dependency installation option — tool should be installed via `dart pub global activate` to avoid transitive `meta` version conflicts with the Flutter SDK.
- Added confirmation prompt before `--replace` rewrites source files. Warns user to back up or commit first, defaults to N.

## 1.0.1

- Improved README: restructured installation section with global activation and dev dependency options.
- Moved "Run from source" to Contributing section.

## 1.0.0

- Initial release.
- AST-based scanner using `package:analyzer` — extracts hardcoded strings from Flutter UI widgets.
- Generates locale files for **GetX** (`.dart` maps), **easy_localization** (`.json`), and **intl** (`.arb`).
- `--replace` flag rewrites source files with `.tr` / `.tr()` / `AppLocalizations` calls.
- Handles string interpolation — `$variable` mapped to `@param` / `{param}` syntax.
- Auto `const` removal and auto import insertion on `--replace`.
- Idempotent — safe to re-run; preserves existing translations in non-source locales.
- One-time setup hints printed per package on first run.
