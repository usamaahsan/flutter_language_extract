## 1.0.0

- Initial release.
- AST-based scanner using `package:analyzer` — extracts hardcoded strings from Flutter UI widgets.
- Generates locale files for **GetX** (`.dart` maps), **easy_localization** (`.json`), and **intl** (`.arb`).
- `--replace` flag rewrites source files with `.tr` / `.tr()` / `AppLocalizations` calls.
- Handles string interpolation — `$variable` mapped to `@param` / `{param}` syntax.
- Auto `const` removal and auto import insertion on `--replace`.
- Idempotent — safe to re-run; preserves existing translations in non-source locales.
- One-time setup hints printed per package on first run.
