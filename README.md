# language_extract

> **Stop translating by hand. Extract, generate, replace — done.**

`language_extract` is a Dart CLI tool that scans a Flutter project's source code for hardcoded UI strings, generates localization files for your chosen i18n package, and optionally rewrites every string literal with the correct localized call — including dynamic strings with `$variables`.

---

## Features

- **AST-based scanning** — uses the Dart analyzer, not regex. Understands context: only extracts strings inside UI widgets (`Text`, `AppBar`, `SnackBar`, `AlertDialog`, …), not route names, asset paths, or code identifiers.
- **Three i18n packages supported** — GetX, easy_localization, intl (ARB).
- **Handles interpolation** — `'Hello $name'` becomes `'hello_name'.trParams({'name': name.toString()})` (GetX) or `'hello_name'.tr(namedArgs: {'name': name.toString()})` (easy_localization).
- **Idempotent** — safe to re-run. Source locale files are always regenerated; non-source locale files merge new keys while preserving existing human translations.
- **Auto `const` removal** — when a string inside a `const` widget is replaced, the `const` keyword is removed automatically.
- **Auto import insertion** — the required package import is added to every modified file.
- **One-time setup hints** — prints setup instructions on first run; silently skips them once your project is already wired up.

---

## Installation

### Installation

Install once, run from any directory:

```bash
dart pub global activate language_extract
```

Then run from anywhere in your terminal:

```bash
language_extract getx /path/to/my_flutter_app --locales en_US,ar_AR
```


---

## Quick start

> **Important:** `<project_path>` must be the **Flutter project root** — the folder that contains `pubspec.yaml` and `lib/`.
> Do **not** point it at the `lib/` folder itself, or the tool will fail looking for `lib/lib/`.

```bash
# Correct — project root
language_extract getx ~/projects/myapp --locales en_US,ar_AR

# Wrong — do not point at lib/
language_extract getx ~/projects/myapp/lib --locales en_US,ar_AR
```

```bash
# 1. Scan and generate locale files (dry run — source untouched)
language_extract getx /path/to/app --locales en_US,ar_AR

# 2. Also rewrite source files (adds .tr calls, removes const, adds imports)
language_extract getx /path/to/app --locales en_US,ar_AR --replace

# 3. Use easy_localization instead
language_extract easy_localization /path/to/app --locales en,ar --replace

# 4. Use the intl package
language_extract intl /path/to/app --locales en_US,ar_AR --replace
```

---

## Usage

```
language_extract <package> <project_path> [options]

Packages:
  getx               GetX — generates lib/translations/*.dart
  easy_localization  easy_localization — generates assets/translations/*.json
  intl               intl / flutter gen-l10n — generates lib/l10n/app_*.arb

Options:
  -l, --locales        Comma-separated list of locales  [required]
                       e.g. --locales en_US,ar_AR,fr_FR
  -s, --source-locale  Which locale to use as the source (values from code).
                       Must be one of the --locales values.
                       Defaults to the first locale in the list.
  -r, --replace        Rewrite source files with localized calls.
  -h, --help           Show this help message.
```

### Examples

```bash
# GetX — English source, add Arabic
language_extract getx ~/projects/myapp --locales en_US,ar_AR --source-locale en_US

# easy_localization — three locales, rewrite source
language_extract easy_localization ~/projects/myapp \
  --locales en,ar,fr \
  --source-locale en \
  --replace

# intl — default source locale (first in list)
language_extract intl ~/projects/myapp --locales en_US,ar_AR --replace
```

---

## What gets generated

### GetX

```
lib/
  translations/
    en_US.dart              ← source locale (values from code, always regenerated)
    ar_AR.dart              ← other locales (existing translations preserved,
                               new keys appended as empty strings)
    app_translations.dart   ← Translations subclass, register in GetMaterialApp
```

**`en_US.dart`**
```dart
const Map<String, String> enUS = {
  'home_screen_welcome': 'Welcome',
  'home_screen_hello_name': 'Hello @name',
};
```

**`ar_AR.dart`** (fill in your translations)
```dart
const Map<String, String> arAR = {
  'home_screen_welcome': '',        // ← translate here
  'home_screen_hello_name': '',
};
```

**`app_translations.dart`**
```dart
import 'package:get/get.dart';
import 'en_US.dart';
import 'ar_AR.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': enUS,
    'ar_AR': arAR,
  };
}
```

**One-time `main.dart` setup** (printed on first run):
```dart
import 'translations/app_translations.dart';

GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  fallbackLocale: const Locale('en', 'US'),
  // ... rest of your config
)
```

---

### easy_localization

```
assets/
  translations/
    en.json    ← source locale
    ar.json    ← other locales (merged)
```

**`en.json`**
```json
{
  "home_screen_welcome": "Welcome",
  "home_screen_hello_name": "Hello {name}"
}
```

**One-time setup** (printed on first run):

1. `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/translations/
   ```

2. `main.dart`:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await EasyLocalization.ensureInitialized();
     runApp(
       EasyLocalization(
         supportedLocales: [Locale('en'), Locale('ar')],
         path: 'assets/translations',
         fallbackLocale: Locale('en'),
         child: MyApp(),
       ),
     );
   }
   ```

3. In `MaterialApp`:
   ```dart
   localizationsDelegates: context.localizationDelegates,
   supportedLocales: context.supportedLocales,
   ```

---

### intl (flutter gen-l10n)

```
lib/
  l10n/
    app_en.arb    ← source locale (values + metadata for gen-l10n)
    app_ar.arb    ← other locales (merged)
```

**`app_en.arb`**
```json
{
  "@@locale": "en",
  "homeScreenWelcome": "Welcome",
  "@homeScreenWelcome": { "description": "home_screen_welcome" },
  "homeScreenHelloName": "Hello {name}",
  "@homeScreenHelloName": {
    "description": "home_screen_hello_name",
    "placeholders": { "name": { "type": "String" } }
  }
}
```

**One-time setup** (printed on first run):

1. Create `l10n.yaml` in your project root:
   ```yaml
   arb-dir: lib/l10n
   template-arb-file: app_en.arb
   output-localization-file: app_localizations.dart
   ```

2. Add to `pubspec.yaml`:
   ```yaml
   flutter:
     generate: true
   ```

3. Run `flutter gen-l10n` to generate `AppLocalizations`.

---

## The `--replace` flag

Without `--replace`, only locale files are written — your source code stays untouched. With `--replace`, every detected string literal is rewritten in place.

### Before

```dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = 'Alice';
    return Scaffold(
      appBar: AppBar(title: const Text('My Dashboard')),
      body: Column(
        children: [
          Text('Welcome back, $user'),
          const Text('Settings'),
        ],
      ),
    );
  }
}
```

### After (GetX)

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = 'Alice';
    return Scaffold(
      appBar: AppBar(title: Text('home_screen_my_dashboard'.tr)),
      body: Column(
        children: [
          Text('home_screen_welcome_back_user'.trParams({'user': (user).toString()})),
          Text('home_screen_settings'.tr),
        ],
      ),
    );
  }
}
```

Notice:
- `const` removed from `Text` widgets (`.tr` is a runtime call, so `const` is invalid)
- `import 'package:get/get.dart';` added automatically
- Dynamic `$user` mapped to `trParams` with `.toString()` conversion (safe for int, double, etc.)

### After (easy_localization)

```dart
Text('home_screen_my_dashboard'.tr())
Text('home_screen_welcome_back_user'.tr(namedArgs: {'user': (user).toString()}))
```

### After (intl)

```dart
Text(AppLocalizations.of(context)!.homeScreenMyDashboard)
Text(AppLocalizations.of(context)!.homeScreenWelcomeBackUser((user).toString()))
```

---

## Key format

Keys are derived from the file name and string value:

| File | String | Key |
|------|--------|-----|
| `home_screen.dart` | `"Welcome"` | `home_screen_welcome` |
| `home_screen.dart` | `"Hello $name"` | `home_screen_hello_name` |
| `signup_screen.dart` | `"Create your account today"` | `signup_screen_create_your_account` |

Rules:
- **Prefix** — file name without `.dart`, converted to `snake_case`
- **Suffix** — up to 4 words from the string value, lowercased, joined by `_`
- **Deduplication** — same string in the same file → same key (no duplicates in output)
- **Collision resolution** — different strings that map to the same key get `_2`, `_3` suffixes

---

## What gets skipped

The scanner ignores strings that are clearly not UI text:

| Pattern | Example |
|---------|---------|
| Route strings | `/home`, `/auth/login` |
| URLs | `https://api.example.com` |
| Asset paths | `assets/images/logo.png` |
| Pure numbers | `'42'`, `'3.14'` |
| Reverse-domain IDs | `com.example.app` |
| `camelCase` identifiers | `myVariableName` |
| `snake_case` identifiers | `my_variable_name` |
| Hex colors | `#FF5733` |
| Single characters | `'/'`, `':'` |
| Strings not in UI context | Log messages, map keys, constants |

---

## Idempotency & merge behavior

| Locale type | Behavior on re-run |
|-------------|-------------------|
| Source locale | Always regenerated from current source code |
| Other locales | Existing translations preserved; new keys appended as empty strings |

Re-run the tool at any time as your codebase grows. Translators can fill in non-source locale files between runs without losing their work.

---

## Interpolation handling

| Input | GetX output |
|-------|------------|
| `'Hello $name'` | `'hello_name'.trParams({'name': (name).toString()})` |
| `'Order #${order.id}'` | `'order_id'.trParams({'orderId': (order.id).toString()})` |
| `'Hi ${user.name ?? "Guest"}'` | `'hi_user_name_guest'.trParams({'userNameGuest': (user.name ?? "Guest").toString()})` |

Locale file values use package-specific placeholder syntax:

| Package | Placeholder syntax |
|---------|--------------------|
| GetX | `Hello @name` |
| easy_localization | `Hello {name}` |
| intl | `Hello {name}` |

All dynamic values are wrapped in `(expr).toString()` — this ensures safety when the expression is an `int`, `double`, or uses null-coalescing (`??`) where operator precedence would otherwise cause issues.

---

## Supported UI widgets

The scanner detects strings in these built-in Flutter widgets:

`Text` · `AppBar` · `SnackBar` · `AlertDialog` · `CupertinoAlertDialog` · `TextButton` · `ElevatedButton` · `OutlinedButton` · `FloatingActionButton` · `ListTile` · `DropdownMenuItem` · `InputDecoration` · `PopupMenuEntry` · `Tab` · `Tooltip` · `Card` · `Chip` · `Badge` · `NavigationDestination` · `BottomNavigationBarItem` · `DrawerHeader` · `ExpansionTile` · `DataColumn` · `DataCell` · `SelectableText`

**Custom widgets** are also supported — any string passed to a recognized named parameter is extracted:

`title:` · `label:` · `text:` · `message:` · `hintText:` · `labelText:` · `helperText:` · `errorText:` · `prefixText:` · `suffixText:` · `counterText:` · `tooltip:` · `semanticLabel:` · `buttonText:` · `confirmText:` · `cancelText:` · `placeholderText:`

---

## Requirements

- Dart SDK `>=3.0.0`
- A Flutter project with the standard structure (`pubspec.yaml` + `lib/` at the root)
- Pass the **project root** as `<project_path>` — the tool automatically scans `lib/` and writes output relative to that root

---

## Contributing

Contributions are welcome! Please open an issue first to discuss what you'd like to change.

### Run from source

```bash
git clone https://github.com/usamaahsan/flutter_language_extract.git
cd flutter_language_extract
dart pub get
dart run bin/language_extract.dart getx /path/to/my_flutter_app --locales en_US,ar_AR
```

### Run tests

```bash
dart test
```

### Analyze

```bash
dart analyze
```

---

## License

MIT
