// =============================================================================
// parser.dart
//
// Barrel: re-exports the parser library, split by concern under parsers/.
// Existing `import 'package:json_forge/...types/parser.dart'` (or, more
// commonly, the top-level `package:json_forge/json_forge.dart`) keeps
// working unchanged — only the internal organization changed.
// =============================================================================

export 'parsers/primitives.dart';
export 'parsers/temporal.dart';
export 'parsers/enum_parser.dart';
export 'parsers/collections.dart';
export 'parsers/model_parser.dart';
export 'parsers/nested_access.dart';
export 'parsers/combinators.dart';
export 'field_builder.dart';
