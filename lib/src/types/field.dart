// =============================================================================
// field.dart
//
// Descriptor for a single JSON field of a model.
//
// Do not create [Field] directly — use the [FieldStringX] extension:
//   'json_key'.field((m) => m.property, parser: intOrZero)
//
// ─── Type Erasure Problem and Its Solution ───────────────────────────────────
//
// When `Field<M, R>` is stored in `List<Field<M, Object?>>`, the specific
// type `R` is erased. Accessing `field.serializer` through an erased reference
// throws a `_TypeError` at runtime: Dart checks function type compatibility
// (contravariant in parameters), so `(DateTime) → String` is NOT a
// subtype of `(Object?) → Object?`.
//
// Solution: create a type-erased wrapper once in the constructor:
//   _erased = (Object? v) => serializer(v as R)
//
// The wrapper accepts `Object?` and is safe at any level of erasure.
// Use [hasSerializer] + [serializeErased] wherever the field is stored
// as `Field<M, Object?>`.
// =============================================================================

import 'types.dart';

/// Descriptor that binds a single JSON key to a typed Dart property.
///
/// ### Fields
/// - [jsonKey]    — key in the JSON object.
/// - [fieldName]  — parameter name in the Dart constructor.
/// - [nesting]    — list of ancestor keys for nested access via `at(...)`.
/// - [getter]     — extracts the value from a model instance.
/// - [parser]     — converts a raw JSON value to [R].
/// - [nullable]   — whether the field allows a null value.
/// - [serializer] — custom serializer (optional).
final class Field<M, R> {
  Field({
    required this.jsonKey,
    required this.fieldName,
    required this.nesting,
    required this.getter,
    required this.parser,
    this.nullable = false,
    Serializer<R>? serializer,
  }) : serializer = serializer,
       // Create a type-erased wrapper once during initialization.
       // This allows safely calling the serializer through an erased type.
       _erased = serializer == null
           ? null
           : ((Object? v) => serializer(v as R));

  /// Key in the JSON object (e.g., `"user_id"`, `"created_at"`).
  final String jsonKey;

  /// Dart constructor parameter name.
  ///
  /// Used when building `copyWith` and displaying in error messages.
  /// By default, it matches [jsonKey], but can differ:
  /// ```dart
  /// 'created_at'.field((m) => m.createdAt, name: 'createdAt')
  /// ```
  final String fieldName;

  /// List of ancestor keys for fields with nested access.
  ///
  /// Empty for top-level fields. Populated when using `at(...)`.
  ///
  /// Example: for `'count'.field(at('meta', intOrZero))` the nesting will be `['meta']`,
  /// and the full read path is `json['meta']['count']`.
  final List<String> nesting;

  /// Extracts the typed value from a model instance [M].
  ///
  /// Accepts `Object?` (instead of `M`) to work during type erasure.
  final R Function(Object? model) getter;

  /// Parses a raw JSON value into type [R].
  ///
  /// Throws [SerializationError] (or a subclass) on error.
  final R Function(Object? jsonValue) parser;

  /// Whether this field allows a null value.
  ///
  /// If `true` — null from JSON is considered valid.
  /// If `false` — null will throw [RequiredFieldError].
  final bool nullable;

  /// Typed serializer.
  ///
  /// Safe only when [R] is known at compile time.
  /// Use [serializeErased] when the type is erased.
  final Serializer<R>? serializer;

  // Type-erased wrapper created once in the constructor.
  // Accepts Object? and casts to R via `as R` inside.
  final Serializer<Object?>? _erased;

  /// `true` if a custom serializer is attached to the field.
  bool get hasSerializer => _erased != null;

  /// Serializes [value] via the type-erased wrapper.
  ///
  /// Safe at any level of type erasure.
  /// Call only after checking [hasSerializer].
  Object? serializeErased(Object? value) => _erased!(value);
}
