// =============================================================================
// parser.dart
//
// Library of total parsers and serializers for primitive types,
// collections, nested models, and helper combinators.
//
// ─── Naming Conventions ─────────────────────────────────────────────────
//
//   xOrNull     — returns null if the value is missing or incompatible.
//                 Total function (never throws).
//   xOrDefault  — returns a default value (0, '', false, epoch…).
//                 Total function.
//   xOrThrow    — throws [FormatException] if the value is null or incompatible.
//                 Use only for fields where an incorrect value is a bug.
//
// ─── Fixed Issues ────────────────────────────────────────────────────
//
//   1. [at] now correctly extracts a nested value from a Map by key,
//      AND saves path metadata in Expando. Previously, the wrapper simply passed through
//      the value without access to the nested key.
//
//   2. [stringOrNull] no longer converts arbitrary objects via .toString().
//      It now returns null for unknown types, preventing silent
//      conversion of List/Map/Object into strings like "Instance of 'Foo'".
//
//   3. [listOf] / [setOf] / [mapOf] — replaced untyped `const []` / `const {}`
//      with typed `<T>[]` / `<T>{}` / `<K, V>{}` to avoid
//      `List<Never>` at runtime.
//
//   4. [uriOrNull] now accepts all syntactically valid URIs (including
//      relative, mailto:, and others), not just absolute HTTP URIs with a host.
//      The strict variant has been renamed to [httpUriOrNull] with explicit documentation.
//
//   5. [listOrNullOf] / [setOf] / [setOrNullOf] now wrap element errors
//      with index specification, just like [listOf].
// =============================================================================

import 'types.dart';

// ─── Nesting metadata (used by [at]) ─────────────────────────────────────────

/// Stores the accumulated path of ancestor keys for parsers created via [at].
///
/// We cannot attach state to a regular function, so we use
/// [Expando]: it maps *function object* → accumulated path.
///
/// Each [at] call:
///   1. Reads the already accumulated path of the child parser (if any).
///   2. Adds its own key to the beginning.
///   3. Saves the new path on the created wrapper object.
final Expando<List<String>> _nestingMeta = Expando('_nesting');

/// Returns the nesting path saved on [parser] via [at].
/// If there is no metadata — returns an empty list.
List<String> nestingOf(Function parser) =>
    _nestingMeta[parser] ?? const <String>[];

// ─── Nullable helper ──────────────────────────────────────────────────────────

/// Lifts a non-nullable serializer to the nullable level.
///
/// ```dart
/// 'ts'.field((m) => m.ts, serializer: nullable(dateTimeToJson))
/// ```
@pragma('vm:prefer-inline')
Serializer<T?> nullable<T>(Serializer<T> s) =>
    (v) => v == null ? null : s(v);

// =============================================================================
// String
// =============================================================================

/// Converts a value to String or returns null.
///
/// Supported input types:
///   - null        → null
///   - String      → string with trim()
///   - int/double  → numeric string (via num.toString())
///   - bool        → "true" / "false"
@pragma('vm:prefer-inline')
String? stringOrNull(Object? v) => switch (v) {
  null => null,
  final String s => s.trim(),
  // We explicitly handle numeric types and bool — they have a predictable
  // string representation. Other objects (List, Map, custom classes) → null.
  final num n => n.toString(),
  final bool b => b.toString(),
  _ => null,
};

@pragma('vm:prefer-inline')
String stringOrEmpty(Object? v) => stringOrNull(v) ?? '';

@pragma('vm:prefer-inline')
String stringOrThrow(Object? v) {
  final r = stringOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'stringOrThrow: expected non-null String, got ${v?.runtimeType} ($v)',
  );
}

// =============================================================================
// int
// =============================================================================

@pragma('vm:prefer-inline')
int? intOrNull(Object? v) => switch (v) {
  null => null,
  final int n => n,
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()),
  final bool b => b ? 1 : 0,
  _ => null,
};

@pragma('vm:prefer-inline')
int intOrZero(Object? v) => intOrNull(v) ?? 0;

@pragma('vm:prefer-inline')
int intOrThrow(Object? v) {
  final r = intOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'intOrThrow: expected int-compatible value, got ${v?.runtimeType} ($v)',
  );
}

// =============================================================================
// double
// =============================================================================

@pragma('vm:prefer-inline')
double? doubleOrNull(Object? v) => switch (v) {
  null => null,
  final double n => n,
  final num n => n.toDouble(),
  final String s => double.tryParse(s.trim()),
  final bool b => b ? 1.0 : 0.0,
  _ => null,
};

@pragma('vm:prefer-inline')
double doubleOrZero(Object? v) => doubleOrNull(v) ?? 0.0;

@pragma('vm:prefer-inline')
double doubleOrThrow(Object? v) {
  final r = doubleOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'doubleOrThrow: expected double-compatible value, got ${v?.runtimeType} ($v)',
  );
}

// =============================================================================
// num
// =============================================================================

@pragma('vm:prefer-inline')
num? numOrNull(Object? v) => switch (v) {
  null => null,
  final num n => n,
  final String s => num.tryParse(s.trim()),
  final bool b => b ? 1 : 0,
  _ => null,
};

@pragma('vm:prefer-inline')
num numOrZero(Object? v) => numOrNull(v) ?? 0;

@pragma('vm:prefer-inline')
num numOrThrow(Object? v) {
  final r = numOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'numOrThrow: expected num-compatible value, got ${v?.runtimeType} ($v)',
  );
}

// =============================================================================
// BigInt
// =============================================================================

@pragma('vm:prefer-inline')
BigInt? bigIntOrNull(Object? v) => switch (v) {
  null => null,
  final int n => BigInt.from(n),
  final String s => BigInt.tryParse(s.trim()),
  final bool b => b ? BigInt.one : BigInt.zero,
  _ => null,
};

@pragma('vm:prefer-inline')
BigInt bigIntOrZero(Object? v) => bigIntOrNull(v) ?? BigInt.zero;

@pragma('vm:prefer-inline')
BigInt bigIntOrThrow(Object? v) {
  final r = bigIntOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'bigIntOrThrow: expected BigInt-compatible value, got ${v?.runtimeType} ($v)',
  );
}

@pragma('vm:prefer-inline')
String bigIntToJson(BigInt v) => v.toString();

// =============================================================================
// bool
// =============================================================================

@pragma('vm:prefer-inline')
bool? boolOrNull(Object? v) => switch (v) {
  null => null,
  final bool b => b,
  final num n => n != 0,
  final String s => switch (s.toLowerCase().trim()) {
    'true' || '1' || 'yes' || 'y' || 'on' => true,
    'false' || '0' || 'no' || 'n' || 'off' => false,
    _ => null,
  },
  _ => null,
};

@pragma('vm:prefer-inline')
bool boolOrFalse(Object? v) => boolOrNull(v) ?? false;

@pragma('vm:prefer-inline')
bool boolOrTrue(Object? v) => boolOrNull(v) ?? true;

@pragma('vm:prefer-inline')
bool boolOrThrow(Object? v) {
  final r = boolOrNull(v);
  if (r != null) return r;
  throw FormatException(
    'boolOrThrow: expected bool-compatible value, got ${v?.runtimeType} ($v)',
  );
}

// =============================================================================
// DateTime
// =============================================================================

/// Smart DateTime parser: supports ISO-8601 strings and Unix timestamps.
///
/// Threshold for determining seconds vs milliseconds: `> 10_000_000_000`.
/// This corresponds to approximately the year 2001 in seconds and 1970 + 116 days in ms.
@pragma('vm:prefer-inline')
DateTime? dateTimeOrNull(Object? v) => switch (v) {
  null => null,
  final DateTime dt => dt,
  final String s when s.isNotEmpty => DateTime.tryParse(s),
  final int n => _tsToDateTime(n),
  final num n => _tsToDateTime(n.toInt()),
  _ => null,
};

/// Determines the Unix timestamp unit and converts to UTC DateTime.
///
/// Threshold `> 10_000_000_000`: values greater than this number are considered
/// milliseconds, smaller ones — seconds.
@pragma('vm:prefer-inline')
DateTime _tsToDateTime(int n) {
  final ms = n > 10_000_000_000 ? n : n * 1000;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

@pragma('vm:prefer-inline')
DateTime dateTimeOrEpoch(Object? v) =>
    dateTimeOrNull(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

@pragma('vm:prefer-inline')
DateTime dateTimeOrThrow(Object? v) =>
    dateTimeOrNull(v) ??
    (throw FormatException(
      'dateTimeOrThrow: expected DateTime/ISO-string/timestamp, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: DateTime → ISO-8601 string.
@pragma('vm:prefer-inline')
String dateTimeToJson(DateTime v) => v.toIso8601String();

/// Serializer: DateTime → Unix seconds (int).
@pragma('vm:prefer-inline')
int dateTimeToUnixSeconds(DateTime v) => v.millisecondsSinceEpoch ~/ 1000;

/// Serializer: DateTime → Unix milliseconds (int).
@pragma('vm:prefer-inline')
int dateTimeToUnixMillis(DateTime v) => v.millisecondsSinceEpoch;

// =============================================================================
// Duration
// =============================================================================

/// Parses Duration from milliseconds (int/num) or a string with the number of milliseconds.
@pragma('vm:prefer-inline')
Duration? durationOrNull(Object? v) => switch (v) {
  null => null,
  final int ms => Duration(milliseconds: ms),
  final num ms => Duration(milliseconds: ms.toInt()),
  final String s when s.trim().isNotEmpty => switch (intOrNull(s.trim())) {
    final int ms => Duration(milliseconds: ms),
    _ => null,
  },
  _ => null,
};

@pragma('vm:prefer-inline')
Duration durationOrZero(Object? v) => durationOrNull(v) ?? Duration.zero;

@pragma('vm:prefer-inline')
Duration durationOrThrow(Object? v) =>
    durationOrNull(v) ??
    (throw FormatException(
      'durationOrThrow: expected int (ms) or parseable string, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: Duration → milliseconds.
@pragma('vm:prefer-inline')
int durationToJson(Duration v) => v.inMilliseconds;

// =============================================================================
// Uri
// =============================================================================

/// Parses any syntactically valid URI from a string.
/// If you need validation for only HTTP(S) URIs with a host — use [httpUriOrNull].
@pragma('vm:prefer-inline')
Uri? uriOrNull(Object? v) => switch (stringOrNull(v)) {
  final String s when s.isNotEmpty => Uri.tryParse(s),
  _ => null,
};

/// Parses only absolute HTTP(S) URIs with a non-empty host.
///
/// Returns null for relative URIs, mailto:, urn:, etc.
/// Use instead of [uriOrNull] when the field must contain only
/// a web address with a host.
@pragma('vm:prefer-inline')
Uri? httpUriOrNull(Object? v) => switch (uriOrNull(v)) {
  final Uri u when u.hasScheme && u.host.isNotEmpty => u,
  _ => null,
};

@pragma('vm:prefer-inline')
Uri uriOrEmpty(Object? v) => uriOrNull(v) ?? Uri();

@pragma('vm:prefer-inline')
Uri uriOrThrow(Object? v) =>
    uriOrNull(v) ??
    (throw FormatException(
      'uriOrThrow: expected valid URI string, got ${v?.runtimeType} ($v)',
    ));

/// Сериализатор: Uri → строка.
@pragma('vm:prefer-inline')
String uriToJson(Uri v) => v.toString();

// =============================================================================
// Enum
// =============================================================================
//
// Implementation principles:
//   • Lookup table is built once when creating the parser (not on every call).
//   • [enumOrNull] accepts Object? and normalizes via stringOrNull().
//   • Support for case-insensitive mode.
//   • If the value already has the correct type T — it is returned immediately.

/// Enum parser: returns null for unknown values.
///
/// [caseInsensitive] — if true, name comparison is case-insensitive.
@pragma('vm:prefer-inline')
Parser<T?> enumOrNull<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  // Строим lookup один раз при создании парсера.
  final byName = caseInsensitive
      ? <String, T>{for (final v in values) v.name.toLowerCase(): v}
      : values.asNameMap();

  return (Object? v) {
    // Build lookup once when creating the parser.
    if (v is T) return v;
    final key = caseInsensitive
        ? stringOrNull(v)?.toLowerCase()
        : stringOrNull(v);
    return key != null ? byName[key] : null;
  };
}

/// Enum parser: returns [fallback] (or the first element) for unknown values.
@pragma('vm:prefer-inline')
Parser<T> enumOrDefault<T extends Enum>(
  List<T> values, {
  T? fallback,
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) => orNull(v) ?? fallback ?? values.first;
}

/// Enum parser: throws [FormatException] for unknown values.
@pragma('vm:prefer-inline')
Parser<T> enumOrThrow<T extends Enum>(
  List<T> values, {
  bool caseInsensitive = false,
}) {
  final orNull = enumOrNull(values, caseInsensitive: caseInsensitive);
  return (Object? v) =>
      orNull(v) ??
      (throw FormatException(
        'enumOrThrow<$T>: unknown value "$v". '
        'Expected one of: ${values.map((e) => e.name).join(', ')}',
      ));
}

/// Serializer: Enum → string (`.name`).
@pragma('vm:prefer-inline')
String enumToJson(Object? v) => (v as Enum).name;

// =============================================================================
// Collections — List
// =============================================================================

/// Parses List<T> from a JSON array. Returns an empty list for non-List values.
///
/// On element parsing error — throws [FormatException] with the index:
/// `"listOf<int>[3]: ..."`.
@pragma('vm:prefer-inline')
Parser<List<T>> listOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => List<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('listOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => <T>[],
    };

/// Parses List<T>? from a JSON array. Returns null for non-List values.
@pragma('vm:prefer-inline')
Parser<List<T>?> listOrNullOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => List<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('listOrNullOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => null,
    };

/// Parses List<T> from a JSON array. Throws [FormatException] for non-List values.
@pragma('vm:prefer-inline')
Parser<List<T>> listOrThrowOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => List<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('listOrThrowOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => throw FormatException(
        'listOrThrowOf<$T>: expected List, got ${v?.runtimeType}',
      ),
    };

// =============================================================================
// Collections — Set
// =============================================================================

/// Parses Set<T> from a JSON array. Returns an empty set for non-List values.
@pragma('vm:prefer-inline')
Parser<Set<T>> setOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => Set<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('setOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => <T>{},
    };

/// Parses Set<T>? from a JSON array. Returns null for non-List values.
@pragma('vm:prefer-inline')
Parser<Set<T>?> setOrNullOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => Set<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('setOrNullOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => null,
    };

/// Parses Set<T> from a JSON array. Throws [FormatException] for non-List values.
@pragma('vm:prefer-inline')
Parser<Set<T>> setOrThrowOf<T>(Parser<T> item) =>
    (Object? v) => switch (v) {
      final List l => Set<T>.unmodifiable(
        l.indexed.map((r) {
          try {
            return item(r.$2);
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('setOrThrowOf<$T>[${r.$1}]: $e'),
              st,
            );
          }
        }),
      ),
      _ => throw FormatException(
        'setOrThrowOf<$T>: expected List, got ${v?.runtimeType}',
      ),
    };

// =============================================================================
// Collections — Map
// =============================================================================

/// Parses Map<K, V> from a JSON object. Returns an empty map for non-Map values.
@pragma('vm:prefer-inline')
Parser<Map<K, V>> mapOf<K, V>(Parser<K> keyParser, Parser<V> valueParser) =>
    (Object? v) => switch (v) {
      final Map m => Map<K, V>.unmodifiable(
        m.map((k, val) {
          try {
            return MapEntry(keyParser(k), valueParser(val));
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('mapOf<$K,$V> key "$k": $e'),
              st,
            );
          }
        }),
      ),
      _ => <K, V>{},
    };

/// Parses Map<K, V>? from a JSON object. Returns null for non-Map values.
@pragma('vm:prefer-inline')
Parser<Map<K, V>?> mapOrNullOf<K, V>(
  Parser<K> keyParser,
  Parser<V> valueParser,
) =>
    (Object? v) => switch (v) {
      final Map m => Map<K, V>.unmodifiable(
        m.map((k, val) => MapEntry(keyParser(k), valueParser(val))),
      ),
      _ => null,
    };

/// Parses Map<K, V> from a JSON object. Throws [FormatException] for non-Map values.
@pragma('vm:prefer-inline')
Parser<Map<K, V>> mapOrThrowOf<K, V>(
  Parser<K> keyParser,
  Parser<V> valueParser,
) =>
    (Object? v) => switch (v) {
      final Map m => Map<K, V>.unmodifiable(
        m.map((k, val) {
          try {
            return MapEntry(keyParser(k), valueParser(val));
          } catch (e, st) {
            Error.throwWithStackTrace(
              FormatException('mapOrThrowOf<$K,$V> key "$k": $e'),
              st,
            );
          }
        }),
      ),
      _ => throw FormatException(
        'mapOrThrowOf<$K,$V>: expected Map, got ${v?.runtimeType}',
      ),
    };

// =============================================================================
// Nested models
// =============================================================================

/// Parses a nested model from a JSON object. Throws if not a Map.
@pragma('vm:prefer-inline')
Parser<T> modelOf<T>(T Function(Json) fromJson) =>
    (Object? v) => switch (v) {
      final Map m => fromJson(Json.from(m)),
      _ => throw FormatException(
        'modelOf<$T>: expected Map, got ${v?.runtimeType}',
      ),
    };

/// Parses a nested model from a JSON object. Returns null if not a Map.
@pragma('vm:prefer-inline')
Parser<T?> modelOrNull<T>(T Function(Json) fromJson) =>
    (Object? v) => switch (v) {
      final Map m => fromJson(Json.from(m)),
      _ => null,
    };

/// Alias for [modelOf] — for symmetry with other `xOrThrow` parsers.
@pragma('vm:prefer-inline')
Parser<T> modelOrThrow<T>(T Function(Json) fromJson) => modelOf(fromJson);

// =============================================================================
// Deep access — at(key, parser)
// =============================================================================
//
// `at(key, parser)` — a combinator for accessing nested JSON keys.
//
// How it works:
//   1. Accepts the raw value `v`.
//   2. Expects `v` to be a Map. If not — throws FormatException.
//   3. Extracts `v[key]` and passes it to the child [parser].
//
// Chain: `at('meta', at('stats', intOrZero))` reads `json['meta']['stats']`.
//
// Path metadata is stored in [_nestingMeta] for use in
// [SerializableHelpers._readPath] and [_writeDeep].

/// Creates a parser that first extracts the value by [key] from a Map,
/// then applies [child] to the obtained value.
///
/// ```dart
/// // Reads json['address']['city'] as String:
/// 'address'.field((m) => m.city, parser: at('address', stringOrEmpty))
///
/// // Chain — reads json['meta']['stats']['count'] as int:
/// 'count'.field((m) => m.count, parser: at('meta', at('stats', intOrZero)))
/// ```
///
/// Throws [FormatException] if the value by [key] is not found or `v` is not a Map.
Parser<T> at<T>(String key, Parser<T> child) {
  // Read the already accumulated path of the child parser (in case of chained at-calls).
  final childPath = _nestingMeta[child] ?? const <String>[];
  // Our key goes first, then the child's path.
  final fullPath = [key, ...childPath];

  // Create a new function object — it gets its own slot in Expando.
  T wrapper(Object? v) {
    if (v is! Map) {
      throw FormatException(
        'at("$key"): expected Map to extract key, got ${v?.runtimeType}',
      );
    }
    return child(v[key]);
  }

  // Save the full path on the wrapper for use in Field.nesting.
  _nestingMeta[wrapper] = fullPath;
  return wrapper;
}

// =============================================================================
// Raw JSON object
// =============================================================================

/// Parses an arbitrary JSON object as Map<String, Object?>.
@pragma('vm:prefer-inline')
Json? jsonObjectOrNull(Object? v) => switch (v) {
  final Map m => Json.from(m),
  _ => null,
};

@pragma('vm:prefer-inline')
Json jsonObjectOrEmpty(Object? v) => jsonObjectOrNull(v) ?? const {};

@pragma('vm:prefer-inline')
Json jsonObjectOrThrow(Object? v) =>
    jsonObjectOrNull(v) ??
    (throw FormatException(
      'jsonObjectOrThrow: expected Map<String, Object?>, got ${v?.runtimeType}',
    ));

// =============================================================================
// Combinators
// =============================================================================

/// Tries parsers in sequence; returns the first non-null result.
///
/// All parser exceptions are silently suppressed.
/// If none returned a value — returns null.
@pragma('vm:prefer-inline')
Parser<T?> oneOf<T>(List<Parser<T?>> parsers) {
  assert(parsers.isNotEmpty, 'oneOf: list must not be empty');
  return (Object? v) {
    for (final p in parsers) {
      try {
        final r = p(v);
        if (r != null) return r;
      } catch (_) {
        // Намеренно подавляем — пробуем следующий парсер.
      }
    }
    return null;
  };
}

/// Applies [transform] to the result of [parser] if it returned non-null.
@pragma('vm:prefer-inline')
Parser<R?> mappedOrNull<T, R>(
  Parser<T?> parser,
  R? Function(T value) transform,
) =>
    (Object? v) => switch (parser(v)) {
      final T r => transform(r),
      _ => null,
    };

/// Applies [transform] to the result of [parser]; returns [defaultValue] if null.
@pragma('vm:prefer-inline')
Parser<R> mappedOrDefault<T, R>(
  Parser<T?> parser,
  R Function(T value) transform,
  R defaultValue,
) {
  final orNull = mappedOrNull(parser, transform);
  return (Object? v) => orNull(v) ?? defaultValue;
}

/// Wraps [parser] in try/catch; returns null on any exception.
@pragma('vm:prefer-inline')
Parser<T?> tryOrNull<T>(Parser<T> parser) => (Object? v) {
  try {
    return parser(v);
  } catch (_) {
    return null;
  }
};

/// Applies [parser]; on error or null result returns [fallback].
@pragma('vm:prefer-inline')
Parser<T> withFallback<T>(Parser<T> parser, T fallback) {
  final orNull = tryOrNull(parser);
  return (Object? v) => orNull(v) ?? fallback;
}
