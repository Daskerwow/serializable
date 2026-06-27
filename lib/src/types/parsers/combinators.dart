// =============================================================================
// combinators.dart
//
// Small parser/serializer combinators that build new (de)serialization
// behavior out of existing ones.
// =============================================================================

import '../types.dart';

/// Lifts a non-nullable serializer to the nullable level.
///
/// ```dart
/// 'ts'.field<M, DateTime?>(serializer: nullable(dateTimeToJson))
/// ```
@pragma('vm:prefer-inline')
Serializer<T?> nullable<T>(Serializer<T> s) => (v) => v == null ? null : s(v);

/// Tries each parser in turn; returns the first non-null result.
///
/// Exceptions from individual parsers are swallowed so the next one gets a
/// chance. Returns `null` if none of them produced a value.
@pragma('vm:prefer-inline')
Parser<T?> oneOf<T>(List<Parser<T?>> parsers) {
  assert(parsers.isNotEmpty, 'oneOf: the parser list must not be empty');
  return (Object? v) {
    for (final p in parsers) {
      try {
        final r = p(v);
        if (r != null) return r;
      } catch (_) {
        // Intentionally swallowed — try the next parser.
      }
    }
    return null;
  };
}

/// Applies [transform] to the result of [parser], if it returned non-null.
@pragma('vm:prefer-inline')
Parser<R?> mappedOrNull<T, R>(
  Parser<T?> parser,
  R? Function(T value) transform,
) =>
    (Object? v) => switch (parser(v)) {
      final T r => transform(r),
      _ => null,
    };

/// Applies [transform] to the result of [parser]; returns [fallback] if it
/// was null.
@pragma('vm:prefer-inline')
Parser<R> mappedOrDefault<T, R>(
  Parser<T?> parser,
  R Function(T value) transform,
  R fallback,
) {
  final orNull = mappedOrNull(parser, transform);
  return (Object? v) => orNull(v) ?? fallback;
}

/// Wraps [parser] in try/catch — returns `null` on any exception.
@pragma('vm:prefer-inline')
Parser<T?> tryOrNull<T>(Parser<T> parser) => (Object? v) {
  try {
    return parser(v);
  } catch (_) {
    return null;
  }
};

/// Runs [parser]; falls back to [fallback] on error or a null result.
@pragma('vm:prefer-inline')
Parser<T> withFallback<T>(Parser<T> parser, T fallback) {
  final orNull = tryOrNull(parser);
  return (Object? v) => orNull(v) ?? fallback;
}
