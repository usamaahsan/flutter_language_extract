// ignore_for_file: avoid_print

// language_extract is a CLI tool — run it from your terminal, not from Dart code.
//
// Installation:
//   dart pub global activate language_extract
//
// ─── GetX ────────────────────────────────────────────────────────────────────
//
//   language_extract getx /path/to/my_flutter_app \
//     --locales en_US,ar_AR \
//     --source-locale en_US \
//     --replace
//
//   Generates:
//     lib/translations/en_US.dart
//     lib/translations/ar_AR.dart
//     lib/translations/app_translations.dart
//
// ─── easy_localization ───────────────────────────────────────────────────────
//
//   language_extract easy_localization /path/to/my_flutter_app \
//     --locales en,ar \
//     --source-locale en \
//     --replace
//
//   Generates:
//     assets/translations/en.json
//     assets/translations/ar.json
//
// ─── intl (flutter gen-l10n) ─────────────────────────────────────────────────
//
//   language_extract intl /path/to/my_flutter_app \
//     --locales en_US,ar_AR \
//     --source-locale en_US \
//     --replace
//
//   Generates:
//     lib/l10n/app_en.arb
//     lib/l10n/app_ar.arb
//
// ─── What --replace does ──────────────────────────────────────────────────────
//
//   Before:
//     const Text('Welcome back')
//     Text('Hello $name')
//
//   After (GetX):
//     Text('home_screen_welcome_back'.tr)
//     Text('home_screen_hello_name'.trParams({'name': (name).toString()}))
//
// See README for full documentation.

void main() {
  print('language_extract is a CLI tool.');
  print('Run: dart pub global activate language_extract');
  print('Then: language_extract --help');
}
