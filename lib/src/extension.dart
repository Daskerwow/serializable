// =============================================================================
// extension.dart
//
// Syntactic sugar: declaring a field via a JSON key as a string literal.
//
// Usage example:
// ```dart
// 'user_id'.field((m) => m.id, parser: intOrZero)
// 'name'.field((m) => m.name)     // smart inference for String
// 'status'.field((m) => m.status, parser: enumOrDefault(Status.values, Status.unknown))
// 'tags'.field((m) => m.tags, parser: listOf(stringOrEmpty))
// 'address'.field((m) => m.address, parser: modelOrNull(Address.fromJson), nullable: true)
// 'created_at'.field((m) => m.ts, parser: at('meta', dateTimeOrEpoch), serializer: dateTimeToUnixSeconds)
// ```
//
// ─── Fixed Issues ────────────────────────────────────────────────────
//
//   1. Eliminated double null-checking.
//      Previously, RequiredFieldError could be thrown twice for the same field:
//        - first time inside the parser closure (here),
//        - second time in SerializableHelpers.fromJson after returning from the parser.
//      Now the null-check lives in ONLY ONE place — in SerializableHelpers.
//      Here we simply return null, and fromJson decides whether this is acceptable.
//
//   2. _smartParse no longer conflicts with the nullable mechanism.
//      Previously, nullable primitives (int?, String?...) were processed in parallel
//      with the field's nullable flag, which created inconsistent behavior.
//      Now _smartParse always works with a specific type R, and the nullable
//      logic is centralized in SerializableHelpers.fromJson.
// =============================================================================

import 'package:json_forge/src/errors.dart';
import 'package:json_forge/src/types/parser.dart';

import 'serializable_model.dart';
import 'types/field.dart';

/// Extension on [String] for declarative definition of model fields.
///
/// ### Parameters
///
/// **[getter]** — function that extracts the value from a model instance.
/// The return type [R] is inferred automatically.
///
/// **[name]** — the Dart constructor parameter name, if it differs from
/// the JSON key (jsonKey). Used in error messages and copyWith.
/// Defaults to jsonKey.
/// ```dart
/// 'created_at'.field((m) => m.createdAt, name: 'createdAt')
/// ```
///
/// **[parser]** — explicit parser. If not specified, [_smartParse] automatically
/// selects a default parser for primitive types (int, String, bool…).
/// For complex types (List, models, Enum) the parser is mandatory.
///
/// **[serializer]** — custom serializer. If not specified, the universal
/// [SerializableHelpers._serialize] is used.
///
/// **[nullable]** — set to `true` for fields of type `T?`. Then null from JSON
/// will be accepted without throwing [RequiredFieldError].
extension FieldStringX on String {
  Field<M, R> field<M, R>(
    R Function(M) getter, {
    String? name,
    R Function(Object?)? parser,
    Object? Function(R)? serializer,
    bool nullable = false,
  }) {
    // Extract the nesting path from the parser metadata (if at() was used).
    // Empty for regular top-level fields.
    final nesting = parser != null ? nestingOf(parser) : const <String>[];

    return Field<M, R>(
      jsonKey: this,
      fieldName: name ?? this,
      nesting: nesting,
      getter: (Object? m) => getter(m as M),
      nullable: nullable,
      serializer: serializer,
      // ─── Parser closure ──────────────────────────────────────────────────
      //   • The parser only parses — returns null if it couldn't.
      //   • The required check (null guard) — only in fromJson.
      //   • This eliminates duplication and confusion with error paths.
      parser: (Object? v) {
        // Apply the explicit parser or try to smartly infer the type.
        final raw = parser != null ? parser(v) : _smartParse<R>(v);

        // Return null as is — fromJson will decide if this is acceptable.
        // The responsibility for RequiredFieldError is moved to fromJson.
        if (raw == null) return null as R;

        // If the type is already correct — return without extra checks.
        if (raw is R) return raw as R;

        // The type does not match — throw a typed error.
        // The full path is built from the nesting + the current key.
        throw TypeConversionError(
          modelType: M,
          fieldName: name ?? this,
          path: [...nesting, this].join('.'),
          expectedType: R,
          actualType: raw.runtimeType,
          rawValue: raw,
        );
      },
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Returns `true` if type `T` is exactly equal to type `R`.
///
/// Used to select the parser in [_smartParse].
/// Dart does not allow comparing generic types directly — this helper
/// creates concrete instances for comparison via `==`.
bool _isType<T, R>() => T == R;

/// Smart default parser for primitive types.
///
/// If type [R] is a known primitive, it calls the corresponding parser from parser.dart.
/// For unknown types, it returns [v] unchanged — it is assumed that
/// the calling side will pass the correct [parser].
Object? _smartParse<R>(Object? v) {
  // ── Non-nullable примитивы ─────────────────────────────────────────────────
  if (_isType<int, R>()) return intOrZero(v);
  if (_isType<double, R>()) return doubleOrZero(v);
  if (_isType<num, R>()) return numOrZero(v);
  if (_isType<bool, R>()) return boolOrFalse(v);
  if (_isType<String, R>()) return stringOrEmpty(v);
  if (_isType<DateTime, R>()) return dateTimeOrEpoch(v);
  if (_isType<Duration, R>()) return durationOrZero(v);
  if (_isType<Uri, R>()) return uriOrEmpty(v);
  if (_isType<BigInt, R>()) return bigIntOrZero(v);

  // ── Nullable primitives ────────────────────────────────────────────────────
  // Checked via `null is R` — this is a runtime null-compatibility check.
  // If R allows null, the orNull variants of the parsers are used.
  if (null is R) {
    if (_isType<int?, R>()) return intOrNull(v);
    if (_isType<double?, R>()) return doubleOrNull(v);
    if (_isType<num?, R>()) return numOrNull(v);
    if (_isType<bool?, R>()) return boolOrNull(v);
    if (_isType<String?, R>()) return stringOrNull(v);
    if (_isType<DateTime?, R>()) return dateTimeOrNull(v);
    if (_isType<Duration?, R>()) return durationOrNull(v);
    if (_isType<Uri?, R>()) return uriOrNull(v);
    if (_isType<BigInt?, R>()) return bigIntOrNull(v);
  }

  // Unknown type (List, Map, custom model, Enum) — pass through as is.
  // The calling side must pass an explicit [parser] for such types.
  return v;
}
