// =============================================================================
// collections.dart
//
// Total parsers for List, Set, and Map — built from a per-element/per-entry
// Parser<T>.
//
// All three come in the same three flavors:
//   xOf        — empty collection on a non-matching input.
//   xOrNullOf  — null on a non-matching input.
//   xOrThrowOf — FormatException on a non-matching input.
//
// Element/entry errors are wrapped with their index (List/Set) or key (Map)
// so a failure deep inside a large payload is easy to locate.
// =============================================================================

import '../types.dart';

// =============================================================================
// List
// =============================================================================

/// Parses `List<T>` from a JSON array. Returns `[]` for non-`List` input.
@pragma('vm:prefer-inline')
Parser<List<T>> listOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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

/// Parses `List<T>?` from a JSON array. Returns `null` for non-`List` input.
@pragma('vm:prefer-inline')
Parser<List<T>?> listOrNullOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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

/// Parses `List<T>` from a JSON array. Throws [FormatException] for
/// non-`List` input.
@pragma('vm:prefer-inline')
Parser<List<T>> listOrThrowOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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
    'listOrThrowOf<$T>: expected a List, got ${v?.runtimeType}',
  ),
};

// =============================================================================
// Set
// =============================================================================

/// Parses `Set<T>` from a JSON array. Returns `{}` for non-`List` input.
@pragma('vm:prefer-inline')
Parser<Set<T>> setOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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

/// Parses `Set<T>?` from a JSON array. Returns `null` for non-`List` input.
@pragma('vm:prefer-inline')
Parser<Set<T>?> setOrNullOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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

/// Parses `Set<T>` from a JSON array. Throws [FormatException] for
/// non-`List` input.
@pragma('vm:prefer-inline')
Parser<Set<T>> setOrThrowOf<T>(Parser<T> item) => (Object? v) => switch (v) {
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
    'setOrThrowOf<$T>: expected a List, got ${v?.runtimeType}',
  ),
};

// =============================================================================
// Map
// =============================================================================

/// Parses `Map<K, V>` from a JSON object. Returns `{}` for non-`Map` input.
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

/// Parses `Map<K, V>?` from a JSON object. Returns `null` for non-`Map`
/// input.
@pragma('vm:prefer-inline')
Parser<Map<K, V>?> mapOrNullOf<K, V>(
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
              FormatException('mapOrNullOf<$K,$V> key "$k": $e'),
              st,
            );
          }
        }),
      ),
      _ => null,
    };

/// Parses `Map<K, V>` from a JSON object. Throws [FormatException] for
/// non-`Map` input.
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
        'mapOrThrowOf<$K,$V>: expected a Map, got ${v?.runtimeType}',
      ),
    };
