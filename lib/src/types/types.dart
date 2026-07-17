// =============================================================================
// types.dart
//
// Common type aliases (typedefs) for the entire library.
//
// Conventions:
//   Parser<T>    — function that takes a raw JSON value and returns T.
//                  Implementations should be "total" (never throw
//                  exceptions during normal use).
//   Serializer<T>— function that converts a Dart value T into a JSON-compatible type.
//   Json         — alias for Map<String, Object?>.
//   JsonRaw      — alias for Map<String, dynamic> (for compatibility with APIs
//                  that return dynamic).
// =============================================================================

import 'field.dart';

/// `Object? → T`
///
/// Parser accepts an arbitrary JSON value and returns a typed T.
/// Implementations should be total (not throw on normal input).
/// To handle null — use `T?` and return null.
typedef Parser<T> = T Function(Object? value);

/// `T → JSON-compatible Object?`
///
/// Serializer converts a Dart value back into a JSON primitive,
/// List, Map, or nested object.
typedef Serializer<T> = Object? Function(T value);

/// Convenient alias: a field with a type-erased value type.
///
/// Used in field lists where the specific value type is unknown
/// at compile time (e.g., `List<FieldOf<User>>`).
typedef FieldOf<M> = Field<M, Object?>;

/// List of all field descriptors for model [T] in the order of constructor parameters.
///
/// This order is critical for [SerializableHelpers.fromJson],
/// which passes values as positional arguments.
typedef ListFieldOf<T> = List<Field<T, Object?>>;

/// Field values for [Equatable.props].
typedef Props = List<Object?>;

/// Standard JSON object: keys are strings, values are arbitrary.
typedef Json = Map<String, Object?>;

/// JSON object with dynamic values.
///
/// Used when interacting with external APIs that return
/// `Map<String, dynamic>` instead of `Map<String, Object?>`.
typedef JsonRaw = Map<String, dynamic>;
