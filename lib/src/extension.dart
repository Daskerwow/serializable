// =============================================================================
// extension.dart
//
// Syntactic sugar: declaring a field via a JSON key as a string literal.
//
// Usage example:
// ```dart
// 'user_id'.field<User, int>(parser: intOrZero)
// 'name'.field<User, String>()                          // smart inference for String
// 'status'.field<User, Status>(parser: enumOrDefault(Status.values, Status.unknown))
// 'tags'.field<User, List<String>>(parser: listOf(stringOrEmpty))
// 'address'.field<User, Address?>(parser: modelOrNull(Address.fromJson))
// 'created_at'.field<User, DateTime>(parser: at('meta', dateTimeOrEpoch), serializer: dateTimeToUnixSeconds)
// ```
//
// There's no getter argument above: `Field` only describes the JSON side
// (key, parser, serializer). A model's current values come from its own
// `props` (the standard Equatable list — see `Serializable` in
// serializable_model.dart), not from a closure on `Field` itself. Prefer
// `Schema.field` over this top-level extension when a model already
// declares a schema — see model_type.dart.
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
//
//   3. `getter` is a named parameter, not a required positional one.
//      `field<M, R>(R Function(M) getter, {...})` compiled, but made every
//      call site above that omits a getter (`'name'.field<User, String>()`)
//      a compile error, despite that being exactly what this file's own
//      examples (and the README) show. Dart also does not allow an
//      *optional* positional parameter to sit alongside named ones in the
//      same signature, so "optional and positional" was never reachable
//      here to begin with — `getter` is now `getter: (m) => m.x`, an
//      optional named parameter, matching `Schema.field` in model_type.dart.
// =============================================================================

import 'errors.dart';
import 'types/field.dart';
import 'types/parser.dart';

/// Extension on [String] for declarative, top-level definition of a model
/// field. Prefer [Schema.field] when the model already declares a schema —
/// it reads more naturally (`field<R>(jsonKey, ...)`, with `M` already
/// known from the schema's own type parameter) and is what every model in
/// the README actually uses. This extension is for the rare field declared
/// outside any [Schema].
///
/// ### Type parameters
///
/// **[M]** and **[R]** can't be inferred from any argument here — neither
/// appears in the parameter list, only in the `Field<M, R>` return type —
/// so this needs an explicit `.field<User, String>(...)` call, or a
/// surrounding expression whose expected type pins them down.
///
/// ### Parameters
///
/// **[parser]** — explicit parser. If omitted, [_smartParse] picks a
/// default parser for primitive types (`int`, `String`, `bool`, ...) based
/// on [R]. For complex types (`List`, models, `Enum`) an explicit parser is
/// mandatory — there's nothing for `_smartParse` to infer for those.
///
/// **[serializer]** — custom serializer for `toJson()`. If omitted, the
/// universal [SerializableHelpers._serialize] is used — it already handles
/// `DateTime`, `Duration`, `Uri`, `BigInt`, `Enum`, and nested
/// `SerializableModelI` models on its own. A custom serializer is only
/// needed for something `_serialize` can't infer (e.g. an `Enum`-keyed
/// `Map`, whose default serialization would key by `.toString()` rather
/// than `.name`).
///
/// **[nullable]** — whether a `null` value from JSON is acceptable for this
/// field. Defaults to `null is R`, so a field typed `T?` is optional out of
/// the box and a field typed `T` is required out of the box. Pass
/// `nullable:` explicitly only to override that default.
///
/// **[getter]** — optional named argument (`.field(getter: (m) => m.x)`).
/// `Field` still only *describes* the JSON side (key, parser, serializer)
/// and carries no per-instance state of its own — but attaching a getter
/// lets [Serializable]'s default `props` implementation read this field's
/// current value straight off a model instance, so the model doesn't have
/// to declare `props` by hand. Omit it (as in every example above) and
/// declare `props` yourself, exactly as you would for plain `Equatable`.
/// See [Serializable] in serializable_model.dart for both styles.
extension FieldStringX on String {
  Field<M, R> field<M, R>({
    R Function(M)? getter,
    R Function(Object?)? parser,
    Object? Function(R)? serializer,
    bool? nullable,
  }) => buildField<M, R>(
    jsonKey: this,
    parser: parser,
    serializer: serializer,
    nullable: nullable,
    getter: getter,
  );
}

/// A bare, model-agnostic way to declare a field — `field<R>(jsonKey)`,
/// with no `M` to supply at all (unlike [FieldStringX.field] /
/// [Schema.field], both of which need or infer a concrete model type).
///
/// Every call is also registered into the current [recordFields] frame,
/// if one is active — this is what lets [RecordedFields] build a model's
/// `fields` from nothing but the `field(...)` calls its own `fromJson`
/// already makes, with no separate `fields` list to keep in sync:
/// ```dart
/// factory UserModel.fromJson(Json json) => recordFields(() => UserModel._(
///   id: field<int>('user_id').readFrom(json),
///   name: field<String>('full_name').readFrom(json),
/// ));
/// ```
/// See [RecordedFields]'s doc comment (serializable_model.dart) for the
/// full pattern, including why the real constructor above is private.
///
/// Returns `Field<Object?, R>` — the same [Field], with the same
/// [Field.readFrom]/[Field.parser]/[Field.nullable] behavior as any other,
/// just with its `M` fixed to `Object?` instead of the real model type.
/// The only thing that costs is error-message precision: a
/// [RequiredFieldError]/[TypeConversionError] thrown by a field declared
/// this way reports `modelType: Object?` rather than the model's real
/// name, since there's no model type in scope here for it to report. If
/// you want the real model name in error output — or a `getter:`, for
/// [PropsFromGetters] — declare the field through [Schema.field] or
/// [FieldStringX.field] (`'jsonKey'.field<M, R>(...)`) instead, both of
/// which take an explicit or inferred `M` (and are registered into
/// [recordFields] exactly the same way, if you want to mix styles).
///
/// Not using [RecordedFields]? `Field<Object?, R>` doesn't require every
/// field in a `ListFieldOf` to share one exact model type (see that
/// typedef's doc comment in types/types.dart), so fields declared this
/// way sit in a hand-declared `fields` list just as well:
/// ```dart
/// static final _fields = <Field<Object?, Object?>>[
///   field<int>('user_id'),
///   field<String>('full_name'),
/// ];
///
/// @override
/// ListFieldOf get fields => _fields;
/// ```
Field<Object?, R> field<R>(
  String jsonKey, {
  R Function(Object?)? parser,
  Object? Function(R)? serializer,
  bool? nullable,
}) => buildField<Object?, R>(
  jsonKey: jsonKey,
  parser: parser,
  serializer: serializer,
  nullable: nullable,
);

Field<M, R> buildField<M, R>({
  required String jsonKey,
  R Function(Object?)? parser,
  Object? Function(R)? serializer,
  bool? nullable,
  R Function(M)? getter,
}) {
  // Extract the nesting path from the parser metadata (if at() was used).
  // Empty for regular top-level fields.
  final nesting = parser != null ? nestingOf(parser) : const <String>[];

  // Smart default: a field typed `T?` is optional out of the box. An
  // explicitly-passed `nullable:` always wins over this default.
  final resolvedNullable = nullable ?? (null is R);

  final built = Field<M, R>(
    jsonKey: jsonKey,
    nesting: nesting,
    nullable: resolvedNullable,
    serializer: serializer,
    getter: getter,
    // ─── Parser closure ──────────────────────────────────────────────────
    //   • The parser only parses — returns null if it couldn't.
    //   • The required check (null guard) — only in fromJson.
    //   • This eliminates duplication and confusion with error paths.
    parser: (Object? v) {
      // Apply the explicit parser or try to smartly infer the type.
      final raw = parser != null ? parser(v) : _smartParse<R>(v);

      // Return null as is — fromJson will decide if this is acceptable.
      // The responsibility for RequiredFieldError is moved to fromJson.
      // (No cast to R here: `Field.parser` is `Object? Function(Object?)`,
      // precisely so a `null` for a non-nullable R doesn't need an unsound
      // `null as R` to satisfy the return type.)
      if (raw == null) return null;

      // If the type is already correct — return without extra checks.
      if (raw is R) return raw;

      // The type does not match — throw a typed error.
      // The full path is built from the nesting + the current key.
      throw TypeConversionError(
        modelType: M,
        jsonKey: jsonKey,
        path: [...nesting, jsonKey].join('.'),
        expectedType: R,
        actualType: raw.runtimeType,
        rawValue: raw,
      );
    },
  );

  // A no-op unless recordFields(...) is currently active — see
  // types/recording.dart. This is what lets RecordedFields build a
  // model's `fields` from nothing but the field(...) calls its own
  // fromJson already makes.
  registerField(built);
  return built;
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
  // ── Non-nullable primitives ────────────────────────────────────────────────
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
