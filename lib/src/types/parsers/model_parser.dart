// =============================================================================
// model_parser.dart
//
// Parsers for nested models (`T Function(Json)` factories) and for "raw"
// JSON objects.
// =============================================================================

import '../types.dart';

/// Parses a nested model from a JSON object. Throws [FormatException] if the
/// value isn't a `Map`.
@pragma('vm:prefer-inline')
Parser<T> modelOf<T>(T Function(Json) fromJson) =>
    (Object? v) => switch (v) {
      // A typed *view* via Map.cast, not a copy via Map.from — the map is
      // only ever read from fromJson, matching the same reasoning as
      // readJsonPath (see types/json_path.dart).
      final Map m => fromJson(m.cast<String, Object?>()),
      _ => throw FormatException(
        'modelOf<$T>: expected a Map, got ${v?.runtimeType}',
      ),
    };

/// Parses a nested model from a JSON object. Returns `null` if the value
/// isn't a `Map`.
@pragma('vm:prefer-inline')
Parser<T?> modelOrNull<T>(T Function(Json) fromJson) =>
    (Object? v) => switch (v) {
      final Map m => fromJson(m.cast<String, Object?>()),
      _ => null,
    };

/// Alias for [modelOf] — for symmetry with the other `xOrThrow` parsers.
@pragma('vm:prefer-inline')
Parser<T> modelOrThrow<T>(T Function(Json) fromJson) => modelOf(fromJson);

// =============================================================================
// Raw JSON object
// =============================================================================

/// Parses an arbitrary JSON object as `Map<String, Object?>`.
@pragma('vm:prefer-inline')
Json? jsonObjectOrNull(Object? v) => switch (v) {
  final Map m => m.cast<String, Object?>(),
  _ => null,
};

@pragma('vm:prefer-inline')
Json jsonObjectOrEmpty(Object? v) => jsonObjectOrNull(v) ?? const {};

Parser<Json> jsonObjectOrDefault(Json fallback) =>
    (Object? v) => jsonObjectOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
Json jsonObjectOrThrow(Object? v) =>
    jsonObjectOrNull(v) ??
    (throw FormatException(
      'jsonObjectOrThrow: expected a Map, got ${v?.runtimeType}',
    ));
