import 'dart:io';

import 'package:args/args.dart';
import 'package:language_extract/src/generators/base_generator.dart';
import 'package:language_extract/src/generators/easy_localization_generator.dart';
import 'package:language_extract/src/generators/getx_generator.dart';
import 'package:language_extract/src/generators/intl_generator.dart';
import 'package:language_extract/src/replacer/source_replacer.dart';
import 'package:language_extract/src/scanner/file_scanner.dart';
import 'package:language_extract/src/utils/key_generator.dart';

const _supportedPackages = ['getx', 'intl', 'easy_localization'];

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'locales',
      abbr: 'l',
      defaultsTo: 'en_US',
      help: 'Comma-separated locale codes to generate.\n'
          'Example: --locales=en_US,ar_AR,fr_FR',
    )
    ..addOption(
      'source-locale',
      abbr: 's',
      help: 'The locale whose file is populated with the real extracted values.\n'
          'Defaults to the first entry in --locales.\n'
          'Example: --source-locale=en_US',
    )
    ..addFlag(
      'replace',
      abbr: 'r',
      negatable: false,
      help: 'Rewrite source files to replace hardcoded strings with '
          'localized calls.\n'
          'GetX:              Text(\'hello\')  →  Text(\'key\'.tr)\n'
          'easy_localization: Text(\'hello\')  →  Text(\'key\'.tr())\n'
          'intl:              Text(\'hello\')  →  Text(AppLocalizations.of(context)!.key)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    _exitWithError('$e\n\n${_usage(parser)}');
  }

  if (args['help'] as bool) {
    stdout.writeln(_usage(parser));
    exit(0);
  }

  final positional = args.rest;
  if (positional.length < 2) {
    _exitWithError('Missing required arguments.\n\n${_usage(parser)}');
  }

  final package = positional[0].toLowerCase();
  final projectPath = positional[1];
  final shouldReplace = args['replace'] as bool;
  final locales = (args['locales'] as String)
      .split(',')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // Source locale: the one whose file gets real extracted values.
  // Defaults to the first locale if --source-locale is not specified.
  final sourceLocale = (args['source-locale'] as String?) ?? locales.first;

  if (!locales.contains(sourceLocale)) {
    _exitWithError(
      'source-locale "$sourceLocale" must be included in --locales.\n'
      'Current locales: ${locales.join(', ')}',
    );
  }

  if (!_supportedPackages.contains(package)) {
    _exitWithError(
      'Unknown package "$package". Supported: ${_supportedPackages.join(', ')}',
    );
  }

  if (!Directory(projectPath).existsSync()) {
    _exitWithError('Project path not found: "$projectPath"');
  }

  // ---------------------------------------------------------------------------
  // 1. Scan
  // ---------------------------------------------------------------------------
  stdout.writeln('Scanning $projectPath/lib for hardcoded strings...\n');

  final strings = await FileScanner().scan(projectPath);
  KeyGenerator().assignKeys(strings);

  // `unique` → one entry per key, used for locale map/file generation.
  // `strings` (full list) → every occurrence, used for --replace so every
  //  instance in every file is rewritten.
  final seen = <String>{};
  final unique = strings.where((s) => seen.add(s.key!)).toList();
  final duplicateCount = strings.length - unique.length;

  if (unique.isEmpty) {
    stdout.writeln('No hardcoded UI strings found. Nothing to generate.');
    exit(0);
  }

  stdout.writeln(
    'Found ${unique.length} unique string(s)'
    '${duplicateCount > 0 ? ' ($duplicateCount duplicate(s) merged)' : ''}.\n',
  );

  // ---------------------------------------------------------------------------
  // 2. Generate locale files
  // ---------------------------------------------------------------------------
  stdout.writeln(
    'Generating $package output for locales: ${locales.join(', ')}\n',
  );

  await _resolveGenerator(package).generate(
    strings: unique,
    projectPath: projectPath,
    locales: locales,
    sourceLocale: sourceLocale,
  );

  // ---------------------------------------------------------------------------
  // 3. Replace source files (opt-in)
  // ---------------------------------------------------------------------------
  if (shouldReplace) {
    stdout.writeln(
      '\n⚠️  WARNING: --replace will rewrite your source files.\n'
      '   Every hardcoded string found in lib/ will be replaced with a\n'
      '   localized call. This cannot be automatically undone.\n'
      '\n'
      '   Make sure you have committed your changes or created a backup\n'
      '   before continuing.\n',
    );
    stdout.write('   Continue? [y/N] ');

    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input != 'y') {
      stdout.writeln('Aborted.');
      exit(0);
    }

    stdout.writeln('\nReplacing hardcoded strings in source files...\n');
    await SourceReplacer().replace(
      strings: strings,
      package: package,
      projectPath: projectPath,
    );
  }

  stdout.writeln('\nDone.');
}

OutputGenerator _resolveGenerator(String package) {
  return switch (package) {
    'getx' => GetxGenerator(),
    'intl' => IntlGenerator(),
    'easy_localization' => EasyLocalizationGenerator(),
    _ => throw StateError('Unhandled package: $package'),
  };
}

String _usage(ArgParser parser) => '''
Usage:
  dart run language_extract <package> <project_path> [options]

Packages:
  getx               Generates lib/translations/*.dart + AppTranslations class
  intl               Generates lib/l10n/app_{locale}.arb files
  easy_localization  Generates assets/translations/{locale}.json files

Options:
${parser.usage}

Examples:
  dart run language_extract getx ~/projects/my_app
  dart run language_extract getx ~/projects/my_app --locales=en_US,ar_AR --replace
  dart run language_extract getx ~/projects/my_app --locales=ar_AR,en_US --source-locale=en_US
  dart run language_extract intl ~/projects/my_app --locales=en_US,ar_AR
  dart run language_extract easy_localization . --locales=en,ar,fr --replace
''';

Never _exitWithError(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
