// Language Extract — a CLI tool for extracting hardcoded strings from Flutter
// projects and generating localization map literals for packages such as
// GetX, easy_localization, and intl.
//
// Core API:
//   FileScanner           — walk lib/ and parse every .dart file
//   StringExtractorVisitor — AST visitor that finds UI strings
//   KeyGenerator          — assign snake_case localization keys
//   ExtractedString       — data model for a single extracted string

export 'src/generators/base_generator.dart';
export 'src/generators/easy_localization_generator.dart';
export 'src/generators/getx_generator.dart';
export 'src/generators/intl_generator.dart';
export 'src/models/extracted_string.dart';
export 'src/models/string_segment.dart';
export 'src/replacer/source_replacer.dart';
export 'src/scanner/ast_visitor.dart';
export 'src/scanner/file_scanner.dart';
export 'src/utils/key_generator.dart';
