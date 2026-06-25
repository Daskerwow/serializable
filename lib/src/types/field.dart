// =============================================================================
// field.dart
//
// Descriptor for a single JSON field of a model.
//
// Do not construct [Field] directly — use the `FieldStringX` extension:
//   'json_key'.field((m) => m.property, parser: intOrZero)
//
// ─── Type erasure ────────────────────────────────────────────────────────────
//
// When `Field<M, R>` is stored in `List<Field<M, Object?>>` (aliased as
// `ListFieldOf`), the specific type `R` is erased. Calling `field.serializer`
// through an erased reference throws at runtime: Dart checks function-type
// compatibility contravariantly in parameters, so `(DateTime) → String` is
// NOT a subtype of `(Object?) → Object?`.
//
// The fix: build a type-erased wrapper once, in the constructor —
//   _erased = (Object? v) => serializer(v as R)
// — which accepts `Object?` and stays safe at any level of erasure. Use
// [hasSerializer] + [serializeErased] wherever the field is stored as
// `Field<M, Object?>`.
//
// ─── Why isn't there a "name" you can look a field up by? ───────────────────
//
// There used to be — an earlier version of this package indexed fields by
// a Dart-facing `name` for `copyWith`, so call sites read `$['title']`. It
// was dropped in favor of plain Dart Records (see `ModelType.bind`'s doc
// comment): a Record gives `$.title` directly, fully checked at compile
// time, for free, with no lookup table and no string at the call site at
// all. `fieldName` below still exists, but purely for nicer error messages
// — it has no bearing on how a field is reached for `copyWith` anymore.
// =============================================================================

import 'types.dart';

/// Descriptor that binds a single JSON key to a typed Dart property.
final class Field<M, R> {
  Field({
    required this.jsonKey,
    required this.fieldName,
    required this.nesting,
    required this.getter,
    required this.parser,
    bool? nullable,
    Serializer<R>? serializer,
  }) : nullable = nullable ?? (null is R),
       serializer = serializer,
       // Build the type-erased wrapper once, up front.
       _erased = serializer == null
           ? null
           : ((Object? v) => serializer(v as R));

  /// Key in the JSON object (e.g., `"user_id"`, `"created_at"`).
  final String jsonKey;

  /// A friendlier name to use in error messages, in place of [jsonKey].
  ///
  /// Defaults to [jsonKey] — pass it only when the JSON key itself wouldn't
  /// read well in a `RequiredFieldError`/`TypeConversionError` message:
  /// ```dart
  /// 'created_at'.field((m) => m.createdAt, name: 'createdAt')
  /// ```
  /// Purely cosmetic: it isn't used to look the field up for `copyWith` (see
  /// the file header above) or anywhere else that affects behavior.
  final String fieldName;

  /// Ancestor keys for fields with nested access via `at(...)`.
  ///
  /// Empty for top-level fields. Example: for
  /// `'count'.field(getter, parser: at('meta', intOrZero))` the nesting is
  /// `['meta']`, and the full read path is `json['meta']['count']`.
  final List<String> nesting;

  /// Extracts the typed value from a model instance [M].
  ///
  /// Accepts `Object?` (instead of `M`) so it keeps working once the field
  /// is stored in an erased `Field<M, Object?>` list.
  final R Function(Object? model) getter;

  /// Parses a raw JSON value.
  ///
  /// Returns a value of type [R], or `null` when the raw value couldn't be
  /// parsed (missing key, wrong shape, ...). That `null` is *not* a final
  /// verdict — `SerializableHelpers.fromJson` is the single place that
  /// decides whether it's acceptable, based on [nullable]. Throw a
  /// `SerializationError` (or subclass) for genuinely unrecoverable input.
  ///
  /// Declared as `Object? Function(Object?)` rather than `R Function(Object?)`
  /// on purpose: it must be able to return `null` even when [R] itself is a
  /// non-nullable type, without an unsound `null as R` cast.
  final Object? Function(Object? jsonValue) parser;

  /// Whether this field accepts a `null` value from JSON.
  ///
  /// `true`  — `null` is a valid result.
  /// `false` — a `null` parse result throws `RequiredFieldError`.
  ///
  /// Defaults to `null is R` when not given explicitly, so a field typed
  /// `String?` is optional out of the box and a field typed `String` is
  /// required out of the box — matching what the Dart type already says.
  /// Pass it explicitly only to override that default.
  final bool nullable;

  /// Typed serializer.
  ///
  /// Safe only when [R] is known at compile time. Use [serializeErased] when
  /// the type has been erased.
  final Serializer<R>? serializer;

  // Type-erased wrapper, built once in the constructor.
  final Serializer<Object?>? _erased;

  /// `true` if a custom serializer is attached to this field.
  bool get hasSerializer => _erased != null;

  /// Serializes [value] via the type-erased wrapper.
  ///
  /// Safe at any level of type erasure. Call only after checking
  /// [hasSerializer].
  Object? serializeErased(Object? value) => _erased!(value);

  @override
  String toString() =>
      'Field<$M, $R>(jsonKey: $jsonKey, fieldName: $fieldName, '
      'nullable: $nullable, nesting: $nesting)';
}
