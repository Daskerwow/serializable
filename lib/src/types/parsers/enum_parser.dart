// =============================================================================
// enum_parser.dart
//
// Parser/serializer combinators for Dart enums, matched by name.
//
// The name→value lookup table is built once, when the parser is created —
// not on every call.
// =============================================================================

import '../types.dart';
import 'primitives.dart' show stringOrNull;

/// Enum parser that returns `null` for unrecognized values.
///
/// [caseInsensitive] makes the name comparison case-insensitive.
@pragma('vm:prefer-inline')
Parser<T?> enumOrNull<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final byName = caseInsensitive
      ? <String, T>{for (final v in values) v.name.toLowerCase(): v}
      : values.asNameMap();

  return (Object? v) {
    if (v is T) return v;
    final key = caseInsensitive
        ? stringOrNull(v)?.toLowerCase()
        : stringOrNull(v);
    return key != null ? byName[key] : null;
  };
}

@pragma('vm:prefer-inline')
Parser<T> enumOrDefault<T extends Enum>(
  List<T> values,
  T fallback, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) => orNull(v) ?? fallback;
}

@pragma('vm:prefer-inline')
Parser<T> enumOrFirst<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) => orNull(v) ?? values.first;
}

@pragma('vm:prefer-inline')
Parser<T> enumOrLast<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) => orNull(v) ?? values.last;
}

/// Enum parser that throws [FormatException] for unrecognized values.
@pragma('vm:prefer-inline')
Parser<T> enumOrThrow<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) =>
      orNull(v) ??
      (throw FormatException(
        'enumOrThrow<$T>: unknown value "$v". Expected one of: '
        '${values.map((e) => e.name).join(', ')}',
      ));
}

/// Serializer: `Enum` → its `.name`.
@pragma('vm:prefer-inline')
String enumToJson(Object? v) => (v as Enum).name;
