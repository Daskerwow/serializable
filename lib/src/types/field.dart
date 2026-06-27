// =============================================================================
// field.dart
//
// Descriptor for a single JSON field of a model. Field is purely about JSON:
// the key, how to parse it, and how to serialize it back. It holds no
// per-instance state and no getter — a model's *current* values come from
// its own `props` (the standard Equatable list), not from this class. See
// `Serializable.toJson()` in serializable_model.dart for how the two are
// zipped together.
//
// Do not create [Field] directly — use the [FieldStringX] extension:
//   'json_key'.field<M, int>(parser: intOrZero)
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

import 'field_patch.dart';
import 'types.dart';

/// Descriptor that binds a single JSON key to a typed Dart property.
///
/// A `Field` only describes the JSON side — it carries no instance, no
/// getter, and no cached value. It's stateless after construction (aside
/// from the type-erased serializer wrapper, built once).
///
/// ### Fields
/// - [jsonKey]    — key in the JSON object.
/// - [nesting]    — list of ancestor keys for nested access via `at(...)`.
/// - [parser]     — converts a raw JSON value to [R].
/// - [nullable]   — whether the field allows a null value.
/// - [serializer] — custom serializer (optional).
final class Field<M, R> {
  Field({
    required this.jsonKey,
    required this.nesting,
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

  /// List of ancestor keys for fields with nested access.
  ///
  /// Empty for top-level fields. Populated when using `at(...)`.
  ///
  /// Example: for `'count'.field(parser: at('meta', intOrZero))` the nesting
  /// will be `['meta']`, and the full read path is `json['meta']['count']`.
  final List<String> nesting;

  /// Parses a raw JSON value, producing a value of type [R] — or `null`
  /// when the value is absent or couldn't be parsed.
  ///
  /// `null` is returned as-is here, never cast to [R]: whether a `null`
  /// result is acceptable for this field is decided by
  /// [SerializableHelpers.fromJson], based on [nullable] — not by this
  /// closure. May still throw [SerializationError] (or a subclass) for
  /// genuinely malformed input.
  final Parser<Object?> parser;

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

// =============================================================================
// FieldPatchX — Field extension for creating a patch
// =============================================================================

extension FieldPatchX<M, R> on Field<M, R> {
  /// Creates a [FieldPatch] for this field with the given value.
  ///
  /// Usage:
  /// ```dart
  /// model.copyWith(($) => [
  ///   $.price.set(9.99),
  ///   $.title.set('New title'),
  /// ]);
  /// ```
  FieldPatch set(R value) => FieldPatch(jsonKey, nesting, value);
}
