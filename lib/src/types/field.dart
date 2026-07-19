// =============================================================================
// field.dart
//
// Descriptor for a single JSON field of a model. Field is purely about JSON:
// the key, how to parse it, and how to serialize it back. It holds no
// per-instance state and no getter — a model's *current* values come from
// its own `props` (the standard Equatable list), not from this class. See
// `Serializable` in serializable_model.dart for how `fields` and `props`
// are zipped together to build `toJson()`.
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
//
// ─── Two ways to turn a `Field` list back into a model ───────────────────────
//
// [readErased] (below) reads a field's *current* value off a live model
// instance — the write direction, used to build `props`/`toJson()`.
// [readFrom] is the read direction's counterpart: it pulls this field's
// value *out of* raw JSON. [SerializableHelpers.fromJson] calls it once per
// field and threads the results through `Function.apply` — the
// zero-extra-code path every example in the README starts with. Calling
// [readFrom] directly, once per field, as a literal positional argument to
// the model's own constructor, skips `Function.apply` entirely and gets the
// same values with a statically-typed, directly-inlinable call instead of a
// dynamic one — see the README's "Fast, Function.apply-free
// deserialization" section for the full pattern (and how it composes with
// Dart's primary constructors).
// =============================================================================

import '../errors.dart';
import 'json_path.dart';
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
    this.getter,
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

  /// Optional accessor that reads this field's current value off a model
  /// instance — e.g. `getter: (m) => m.uid`.
  ///
  /// Entirely optional: a model can keep declaring `props` by hand (the
  /// original approach) and never set this. But when *every* field has a
  /// getter, [PropsFromGetters]'s default `props` implementation can build
  /// the whole `props` list from `fields` alone — one less hand-maintained
  /// list that has to stay in sync with the constructor.
  ///
  /// Unlike [serializer], this needs no type-erased wrapper: [R] only
  /// appears in *return* position here, so `R Function(M)` is already a
  /// safe subtype of `Object? Function(M)` — the type Dart sees through an
  /// erased `Field<M, Object?>` reference — with no unsound cast required.
  final R Function(M)? getter;

  /// `true` if a [getter] is attached to the field.
  bool get hasGetter => getter != null;

  /// Reads this field's current value off [instance] via [getter].
  ///
  /// Call only after checking [hasGetter].
  Object? readErased(M instance) => getter!(instance);

  /// Reads, parses, and null-checks this field's value directly out of
  /// [json] — the same work [SerializableHelpers.fromJson] does per field
  /// before handing everything to `Function.apply`, but for exactly this
  /// one field, statically typed as [R], and callable on its own.
  ///
  /// Meant to be called once per field, directly as a positional argument
  /// to a hand-written factory constructor:
  /// ```dart
  /// factory UserModel.fromJson(Json json) => UserModel(
  ///   id: field<int>('user_id').readFrom(json),
  ///   name: field<String>('full_name').readFrom(json),
  ///   email: field<String?>('email_address').readFrom(json),
  /// );
  /// ```
  /// (`field<R>(jsonKey)` here is the model-agnostic top-level convenience
  /// in extension.dart — a [RecordedFields]-derived field or a
  /// `'key'.field<M, R>()`-declared one works identically, just with a
  /// concrete `M` instead of `Object?`.)
  /// No `Function.apply`, no intermediate `List<Object?>` holding every
  /// field's value, and — since this is now a literal constructor call
  /// instead of a dynamic one — a field whose type doesn't match the
  /// constructor parameter it feeds is a **compile-time** error instead of
  /// the runtime `StateError` `Function.apply` needed to catch the same
  /// mistake.
  ///
  /// Throws [RequiredFieldError] if the parsed value is `null` and
  /// [nullable] is `false`. [TypeConversionError] typically surfaces from
  /// within [parser] itself (see `buildField` in extension.dart); any other
  /// exception [parser] throws is wrapped in a [SerializationError] with
  /// this field's [modelType]/[jsonKey]/[path]/raw value attached, same as
  /// `fromJson` already did.
  R readFrom(Json json) {
    final raw = readJsonPath(json, nesting, jsonKey);
    final Object? value;
    try {
      value = parser(raw);
    } on SerializationError {
      // Typed errors already carry full context — propagate unwrapped.
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SerializationError(
          modelType: M,
          jsonKey: jsonKey,
          path: path,
          rawValue: raw,
          cause: e,
        ),
        st,
      );
    }

    if (value == null) {
      // A nullable field legitimately resolves to null — safe to hand back
      // as R: `nullable` is only ever true when `null is R` (see
      // `buildField`'s `resolvedNullable`), so this cast can't fail for a
      // correctly-built Field.
      if (nullable) return null as R;
      throw RequiredFieldError(
        modelType: M,
        jsonKey: jsonKey,
        path: path,
        rawValue: raw,
      );
    }

    // `parser` already validated `value is R` (see `buildField`) —
    // `TypeConversionError` would already have been thrown above otherwise.
    return value as R;
  }

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

  /// The full dot-separated path for this field: [nesting] followed by
  /// [jsonKey] (e.g. `'meta.count'` for `at('meta', ...)` + jsonKey
  /// `'count'`; just `jsonKey` itself when there's no nesting). Used in
  /// error messages — see [SerializableHelpers.fromJson].
  String get path =>
      nesting.isEmpty ? jsonKey : [...nesting, jsonKey].join('.');

  /// Best-effort check that [value] could plausibly be this field's
  /// current value — `value is R`.
  ///
  /// Used by `Serializable.toJson()` — in every build mode, not just
  /// debug — as a sanity check that `props` lines up with `fields` in the
  /// same order: it catches many transposition mistakes (e.g. a `List`
  /// field swapped with a `String` one), but not all (two fields of the
  /// identical type, swapped, still passes — only an actual getter, or
  /// the model's own correctness, can catch that).
  bool acceptsValue(Object? value) => value is R;
}
