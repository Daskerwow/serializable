// =============================================================================
// extension.dart
//
// Syntactic sugar: declaring a field via a JSON key string literal.
//
// Usage:
// ```dart
// 'user_id'.field((m) => m.id, parser: intOrZero)
// 'name'.field((m) => m.name)     // smart inference for String
// 'status'.field((m) => m.status, parser: enumOrDefault(Status.values, Status.unknown))
// 'tags'.field((m) => m.tags, parser: listOf(stringOrEmpty))
// 'address'.field((m) => m.address, parser: modelOrNull(Address.fromJson))
// 'created_at'.field((m) => m.ts, parser: at('meta', dateTimeOrEpoch), serializer: dateTimeToUnixSeconds)
// ```
//
// ─── Design notes ───────────────────────────────────────────────────────────
//
//   • Single source of truth for the required-field check.
//     The parser closure built here only *parses* — it returns `null` when
//     it can't, and never decides whether that's acceptable. The one place
//     that makes that call is `SerializableHelpers.fromJson`, based on
//     `Field.nullable`. This keeps `RequiredFieldError` from ever being
//     raised twice for the same field.
//
//   • No unsound cast for the `null` case.
//     `Field.parser` is typed `Object? Function(Object?)`, not
//     `R Function(Object?)` — so returning `null` here for a non-nullable
//     `R` is always safe. There's no `null as R` cast that could throw
//     before `fromJson` even gets a chance to look at the value.
//
//   • `nullable` defaults from `R`.
//     If you don't pass `nullable` explicitly, it's derived as `null is R` —
//     a field typed `String?` is optional out of the box, a field typed
//     `String` is required out of the box. Pass it explicitly only to
//     override that default (e.g. a `T?` field you still want to treat as
//     required).
// =============================================================================

import 'errors.dart';
import 'types/field.dart';
import 'types/parser.dart';

/// Extension on [String] for declaratively defining model fields.
///
/// ### Parameters
///
/// **[getter]** — extracts the value from a model instance. The return
/// type [R] is inferred from it (and from [parser], if given).
///
/// **[name]** — the Dart constructor parameter name, if it differs from the
/// JSON key. Used in error messages and in `FieldPatch`es. Defaults to the
/// JSON key:
/// ```dart
/// 'created_at'.field((m) => m.createdAt, name: 'createdAt')
/// ```
///
/// **[parser]** — explicit parser. If omitted, a smart default parser is
/// picked for known primitive types (`int`, `String`, `bool`, ...). Complex
/// types (`List`, models, `Enum`) require an explicit parser.
///
/// **[serializer]** — custom serializer. If omitted, the universal
/// `SerializableHelpers` serialization logic is used.
///
/// **[nullable]** — whether `null` from JSON is acceptable. Defaults to
/// `null is R` (see the design notes above) — pass it only to override that.
extension FieldStringX on String {
  Field<M, R> field<M, R>(
    R Function(M) getter, {
    String? name,
    R Function(Object?)? parser,
    Object? Function(R)? serializer,
    bool? nullable,
  }) {
    // The nesting path comes from the parser's metadata, if `at(...)` was
    // used to build it. Empty for ordinary top-level fields.
    final nesting = parser != null ? nestingOf(parser) : const <String>[];
    final fieldName = name ?? this;

    return Field<M, R>(
      jsonKey: this,
      fieldName: fieldName,
      nesting: nesting,
      getter: (Object? m) => getter(m as M),
      nullable: nullable,
      serializer: serializer,
      // ─── Parser closure ────────────────────────────────────────────────
      //   • Only parses — returns `null` when it can't.
      //   • The required check (the null guard) lives only in `fromJson`.
      parser: (Object? v) {
        final raw = parser != null ? parser(v) : _smartParse<R>(v);

        // A `null` result is valid here — `fromJson` decides whether it's
        // acceptable. No unsound cast needed: see the file header.
        if (raw == null) return null;

        // Already the right runtime type — nothing more to do.
        if (raw is R) return raw;

        // Wrong type — fail with full context instead of a bare CastError
        // surfacing somewhere downstream.
        throw TypeConversionError(
          modelType: M,
          fieldName: fieldName,
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

/// `true` exactly when type `T` equals type `R`.
///
/// Dart doesn't let you compare generic types directly; reifying both as
/// type arguments and comparing via `==` does the job. Used to pick the
/// right default parser in [_smartParse].
bool _isType<T, R>() => T == R;

/// Default parser for primitive types, used when no explicit `parser` is
/// given to [FieldStringX.field].
///
/// Returns the matching default for a known primitive [R] (see
/// `parsers/primitives.dart` and `parsers/temporal.dart`). For unknown
/// types (`List`, `Map`, custom models, `Enum`, ...) it returns [v] as-is —
/// the caller must supply an explicit `parser` for those.
Object? _smartParse<R>(Object? v) {
  // ── Non-nullable primitives ────────────────────────────────────────────
  if (_isType<int, R>()) return intOrZero(v);
  if (_isType<double, R>()) return doubleOrZero(v);
  if (_isType<num, R>()) return numOrZero(v);
  if (_isType<bool, R>()) return boolOrFalse(v);
  if (_isType<String, R>()) return stringOrEmpty(v);
  if (_isType<DateTime, R>()) return dateTimeOrEpoch(v);
  if (_isType<Duration, R>()) return durationOrZero(v);
  if (_isType<Uri, R>()) return uriOrEmpty(v);
  if (_isType<BigInt, R>()) return bigIntOrZero(v);

  // ── Nullable primitives ────────────────────────────────────────────────
  // `null is R` is a runtime null-compatibility check: true when R itself
  // allows null (e.g. R == int?).
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

  // Unknown type — pass through; the caller must supply an explicit parser.
  return v;
}
