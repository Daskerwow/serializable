// =============================================================================
// enum_parser.dart
//
// Parser/serializer combinators for Dart enums, matched by name.
//
// Each returned parser is additionally tagged (via an Expando — the same
// technique `at()` uses in nested_access.dart to stash nesting metadata)
// with the exact `values` list it was built from. This lets `ModelBinder`
// recover an enum field's full value domain later, purely from the parser
// the field was already declared with — no change to how a model declares
// its fields. See `enumDomainOf` and `ModelBinder._alternateValueFor` in
// model_type.dart: it's what lets `$.set((m) => m.status, ...)` resolve
// correctly even when two fields of the *same* enum type currently hold
// the *same* member.
// =============================================================================

import '../types.dart';
import 'primitives.dart' show stringOrNull;

/// Domain metadata stashed on every parser built below.
final Expando<List<Enum>> _enumDomainMeta = Expando('_enumDomain');

/// The `values` list an enum parser was built from — `null` for any
/// parser not built by one of the functions in this file.
///
/// Internal plumbing for [ModelBinder]; not part of the public
/// field-declaration API.
List<Enum>? enumDomainOf(Object? parser) =>
    parser is Function ? _enumDomainMeta[parser] : null;

/// Enum parser that returns `null` for unrecognized values.
///
/// [caseInsensitive] makes the name comparison case-insensitive.
Parser<T?> enumOrNull<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final byName = caseInsensitive
      ? <String, T>{for (final v in values) v.name.toLowerCase(): v}
      : values.asNameMap();

  T? parser(Object? v) {
    if (v is T) return v;
    final key = caseInsensitive
        ? stringOrNull(v)?.toLowerCase()
        : stringOrNull(v);
    return key != null ? byName[key] : null;
  }

  _enumDomainMeta[parser] = values;
  return parser;
}

Parser<T> enumOrDefault<T extends Enum>(
  List<T> values,
  T fallback, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  T parser(Object? v) => orNull(v) ?? fallback;
  _enumDomainMeta[parser] = values;
  return parser;
}

Parser<T> enumOrFirst<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  T parser(Object? v) => orNull(v) ?? values.first;
  _enumDomainMeta[parser] = values;
  return parser;
}

Parser<T> enumOrLast<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  T parser(Object? v) => orNull(v) ?? values.last;
  _enumDomainMeta[parser] = values;
  return parser;
}

/// Enum parser that throws [FormatException] for unrecognized values.
Parser<T> enumOrThrow<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  T parser(Object? v) =>
      orNull(v) ??
      (throw FormatException(
        'enumOrThrow<$T>: unknown value "$v". Expected one of: '
        '${values.map((e) => e.name).join(', ')}',
      ));
  _enumDomainMeta[parser] = values;
  return parser;
}

/// Serializer: `Enum` → its `.name`.
@pragma('vm:prefer-inline')
String enumToJson(Object? v) => (v as Enum).name;
