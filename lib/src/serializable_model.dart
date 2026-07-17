// =============================================================================
// serializable_model.dart
//
// Serialization core: model interface, Serializable mixin, and
// SerializableHelpers engine.
//
// ─── Fixed Issues ────────────────────────────────────────────────────
//
//   1. Centralized null-check for required fields.
//      Previously, RequiredFieldError was duplicated: in extension.dart AND in fromJson.
//      Now the null-guard lives only in fromJson — a single source of truth.
//
//   2. Function.apply — positional call (documentation fixed).
//      The old comment claimed "named dispatch" and "positional: false",
//      although Function.apply(factory, args) is ALWAYS a positional call.
//      Named-dispatch requires Function.apply(factory, null, namedArgsMap).
//      The documentation has been aligned with the actual behavior.
//
//   3. _serialize: DateTime is now converted via toIso8601String(),
//      which is compatible with dateTimeOrNull (accepts ISO strings).
//      The contract "whatever _serialize wrote, the parser will read back" is now
//      explicitly documented.
//
//   4. Removed the Expando-based per-instance value cache (`Field.attach`/
//      `readErased`). It only ever got populated by `fromJson`, so `toJson()`
//      and `==` silently went blank — null for every field, no exception —
//      for any instance built via its own constructor instead of
//      `fromJson` (and threw a raw cast TypeError on a custom `serializer`
//      instead, since `null as R` is unsound for non-nullable `R`).
//      `toJson()` is now built from `fields` + `props` (see [Serializable]
//      below) — real values, regardless of how the instance was
//      constructed, with no per-field getter required. A length mismatch
//      between `fields` and `props`, or a per-slot type mismatch (see
//      `Field.acceptsValue`), is now a clear `StateError` — in every build
//      mode, including release, not just a debug-only `assert`.
//
//   5. Removed `copyWith` from this library entirely (along with the
//      `undefined` sentinel, `Schema.set`, and `ModelBinder` in
//      model_type.dart). This library owns JSON ⇄ model mapping only; a
//      model's own immutable `copyWith` is domain-layer value-object
//      logic and belongs on the domain entity, written by hand — see
//      model_type.dart's header for the full reasoning, and the README's
//      "Writing your own copyWith" section for a worked example.
// =============================================================================

import 'package:equatable/equatable.dart';

import 'errors.dart';
import 'types/types.dart';

// =============================================================================
// SerializableModelI — model interface
// =============================================================================

/// Contract that every serializable model must implement.
///
/// Use the [Serializable] mixin for an automatic implementation of
/// [toJson] — built from [fields] and [props] together. [props] is the
/// standard `Equatable` list, and it's what makes [toJson] (and
/// `==`/`hashCode`, via `Equatable`) correct for *any* instance, not just
/// ones built via `fromJson`. It can either be written by hand (as in
/// plain `Equatable` usage) or derived automatically from `getter:`
/// closures on each field — see [Serializable] for both options.
///
/// ### Field Requirements ([fields] and [props])
/// [fields] must list a descriptor for every model field, and [props] must
/// list that field's current value — **both in the same order, matching
/// the constructor's parameter order.** This is critical for two reasons:
/// [SerializableHelpers.fromJson] passes parsed values to the constructor
/// positionally via [Function.apply], and [Serializable.toJson] zips
/// [fields] with [props] index-for-index to build the JSON. A length
/// mismatch between the two throws a clear [StateError] immediately, in
/// every build mode; so does a same-length but wrong-*order* mix-up,
/// **if** it produces a value of the wrong type for some slot (e.g. two
/// differently-typed fields swapped) — see [Field.acceptsValue]. Two
/// fields of the *identical* type swapped still isn't caught: nothing
/// short of an actual getter (or the model author getting `props` right)
/// can tell two same-typed values apart.
abstract interface class SerializableModelI<M extends SerializableModelI<M>> {
  /// All field descriptors, in constructor-parameter order.
  ///
  /// Declare as `static final` and override via a getter:
  /// ```dart
  /// static final ListFieldOf<User> _fields = [...];
  /// @override
  /// ListFieldOf<User> get fields => _fields;
  /// ```
  ListFieldOf<M> get fields;

  /// Serializes the instance into a JSON-compatible Map.
  Json toJson();

  /// This model's current field values, in the same order as [fields].
  ///
  /// This is the plain `Equatable` `props` list — write it the same way
  /// you would for any `Equatable` class, referencing the model's own
  /// properties directly (e.g. `[id, name, address]`) — no JSON keys or
  /// strings of any kind belong here, only the values themselves.
  /// [Serializable] builds both `toJson()` and `Equatable`'s
  /// `==`/`hashCode` from it.
  Props get props;
}

// =============================================================================
// Serializable — mixin with automatic implementation
// =============================================================================

/// Provides an automatic implementation of [toJson], built from [fields]
/// and [props].
///
/// [props] itself has two ways to be satisfied:
///
///   1. **Explicit** (original approach) — declare it yourself, exactly as
///      in plain `Equatable` usage: `Props get props => [id, name, address];`.
///      Always works, no extra setup on the fields.
///   2. **Derived** — give every field in the [Schema] a `getter:`
///      (`field<int>('user_id', getter: (m) => m.id)`), and don't override
///      `props` at all. This mixin's default implementation then builds
///      `props` from [fields] + those getters. One fewer hand-maintained
///      list that has to stay in the same order as the constructor.
///
/// Pick whichever fits — a model can even mix getter-equipped and
/// getter-less fields as long as it still overrides `props` itself in that
/// case (the derived default requires *every* field to have a getter, and
/// throws a clear [StateError] otherwise rather than silently dropping
/// fields).
///
/// ### Full Model Example (recommended style: Schema + ModelType)
///
/// See the package README for the complete picture; the shape of a single
/// model is:
/// ```dart
/// class User extends Equatable with Serializable<User> {
///   final int id;
///   final String name;
///   final String? address;
///
///   const User(this.id, this.name, this.address);
///
///   static final $ = ModelType<User>(User.new, UserSchema());
///
///   @override
///   ListFieldOf<User> get fields => $.schema.all;
///
///   // No `props` override needed here — every field below has a
///   // `getter:`, so Serializable's default derives it for you.
///
///   factory User.fromJson(Json json) => $.call(json);
///
///   // No copyWith here — this library only maps JSON ⇄ model. Write
///   // copyWith by hand on the domain entity instead.
/// }
///
/// final class UserSchema extends Schema<User> {
///   late final id = field<int>('user_id', getter: (m) => m.id);
///   late final name = field<String>('full_name', getter: (m) => m.name);
///   late final address = field<String?>('user_address', getter: (m) => m.address);
///
///   @override
///   ListFieldOf<User> get all => [id, name, address];
/// }
/// ```
mixin Serializable<M extends SerializableModelI<M>> on Equatable
    implements SerializableModelI<M> {
  @override
  Json toJson() => SerializableHelpers._buildJson<M>(fields, props);

  /// Default `props`, built from each field's `getter` (see
  /// `Schema.field(..., getter: ...)`).
  ///
  /// This is what lets a model skip declaring `props` by hand entirely —
  /// one less place where the field order has to be kept in sync with the
  /// constructor and with `Schema.all`. A model is still free to override
  /// `props` itself (the class body always wins over this mixin default);
  /// do that if some fields don't have a `getter`, or if you simply prefer
  /// the explicit list.
  ///
  /// Throws [StateError] — clearly, and only when this default is
  /// actually used — if any field in [fields] has no `getter`, rather than
  /// silently producing a `props` list with holes in it.
  @override
  Props get props =>
      SerializableHelpers._propsFromGetters<M>(fields, this as M);
}

// =============================================================================
// SerializableHelpers — serialization engine
// =============================================================================

/// Static engine: deserialization and serialization.
///
/// Not intended for direct inheritance. Use via the [Serializable] mixin
/// and the static method [fromJson].
final class SerializableHelpers {
  SerializableHelpers._();

  // ===========================================================================
  // fromJson
  // ===========================================================================

  /// Deserializes [json] into model [R].
  ///
  /// ### Algorithm
  /// 1. For each field from [fields]:
  ///    a. Extracts the value by path `[nesting..., jsonKey]` via [_readPath].
  ///    b. Applies `field.parser(raw)`.
  ///    c. If the result is `null` and the field is not nullable — throws [RequiredFieldError].
  /// 2. Passes all values as POSITIONAL arguments to [factory] via [Function.apply].
  ///
  /// ### Important: positional constructor call
  /// [Function.apply(factory, args)] passes arguments positionally.
  /// The order of fields in [fields] MUST match the order of constructor parameters.
  /// Named-dispatch (Function.apply with namedArgs) is not used — it is slower
  /// and breaks during obfuscation in `dart compile exe --obfuscate`.
  ///
  /// ```dart
  /// static User fromJson(Map<String, Object?> json) =>
  ///     SerializableHelpers.fromJson(json, _fields, User.new);
  /// ```
  static R fromJson<R extends SerializableModelI<R>>(
    Json json,
    ListFieldOf<R> fields,
    Function factory,
  ) {
    final args = <Object?>[];

    for (final f in fields) {
      // Read the value by path (supports nested keys via at()).
      final raw = _readPath(json, f.nesting, f.jsonKey);
      Object? value;

      try {
        value = f.parser(raw);
      } on SerializationError {
        // Typed errors are rethrown without wrapping — they already carry
        // the full context (modelType, fieldName, path).
        rethrow;
      } catch (e, st) {
        // Unexpected exceptions are wrapped in SerializationError with context.
        Error.throwWithStackTrace(
          SerializationError(
            modelType: R,
            jsonKey: f.jsonKey,
            path: f.path,
            rawValue: raw,
            cause: e,
          ),
          st,
        );
      }

      // ── Null guard (the only place where required fields are checked) ────────
      //
      // Cases:
      //   value == null && !nullable → RequiredFieldError
      //   value == null &&  nullable → acceptable, null is passed to the constructor
      if (value == null && !f.nullable) {
        throw RequiredFieldError(
          modelType: R,
          jsonKey: f.jsonKey,
          path: f.path,
          rawValue: raw,
        );
      }

      args.add(value);
    }

    // Call the constructor with positional arguments.
    try {
      return Function.apply(factory, args) as R;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SerializationError(
          modelType: R,
          jsonKey: '<constructor>',
          path: R.toString(),
          cause: e,
          message: _constructorFailureMessage(fields, args),
        ),
        st,
      );
    }
  }

  /// Builds a diagnostic message for a failed [Function.apply] call during
  /// [fromJson] — one line per field, showing exactly which `jsonKey`
  /// produced which runtime-typed value, so a `TypeError` like
  /// `type 'int' is not a subtype of type 'String'` (otherwise pointing
  /// only at an opaque `Function.apply` frame) can be traced straight
  /// back to the offending field instead of requiring a manual
  /// field-by-field audit of the schema.
  ///
  /// This exists because a getter/parser type mismatch on a field
  /// declared inline inside a `List<Field<M, Object?>>` literal — the
  /// common `'key'.field((m) => m.x, parser: ...)` style used directly in
  /// a `Schema.all` list — does *not* fail to compile: Dart infers the
  /// field's type parameter down to the list's own `Object?` element
  /// type rather than flagging that the getter and parser disagree, so
  /// the mismatch stays invisible until the constructor call it feeds.
  static String _constructorFailureMessage<R>(
    ListFieldOf<R> fields,
    List<Object?> args,
  ) {
    final buf = StringBuffer(
      'Positional constructor call failed. Make sure the fields in '
      '`fields` are declared in the same order as the constructor '
      "parameters, and that each field's `parser` (and `getter`, if any) "
      'agree on the same type — a mismatch there compiles silently '
      'whenever the field is declared inline inside a list literal, and '
      'only surfaces here.\n'
      'Arguments passed (jsonKey: runtimeType = value):',
    );
    for (var i = 0; i < fields.length && i < args.length; i++) {
      buf.write(
        '\n  ${fields[i].jsonKey}: ${args[i]?.runtimeType ?? 'Null'} = '
        '${args[i]}',
      );
    }
    return buf.toString();
  }

  // ===========================================================================
  // props (internal) — backs Serializable's default `props` implementation
  // ===========================================================================

  /// Builds a `props` list by calling each field's `getter` against
  /// [instance], in [fields] order.
  static Props _propsFromGetters<M>(ListFieldOf<M> fields, M instance) {
    final result = <Object?>[];
    for (final f in fields) {
      if (!f.hasGetter) {
        throw StateError(
          'Serializable.props: field "${f.jsonKey}" on $M has no getter. '
          'Either pass getter: (m) => m.yourProperty to every field in the '
          'Schema, or override `props` manually on $M as before.',
        );
      }
      result.add(f.readErased(instance));
    }
    return result;
  }

  // ===========================================================================
  // toJson (internal)
  // ===========================================================================

  /// Builds a JSON-Map from [fields] and the model's [props] — index `i`
  /// of `props` is the current value of `fields[i]`. Both must be the same
  /// length and in the same (constructor-parameter) order; see
  /// [SerializableModelI] for why.
  ///
  /// For each field:
  ///   - If there is a custom serializer → use it via the type-erased wrapper.
  ///   - Otherwise → [_serialize] with default smart logic.
  ///
  /// Fields with nesting are written via [_writeDeep] — creates nested Maps on the fly.
  ///
  /// Throws [StateError] — in every build mode, including release — if
  /// `fields` and `props` differ in length, or if some `props[i]` doesn't
  /// look like it belongs to `fields[i]` (see [Field.acceptsValue]). This
  /// used to be a debug-only `assert`; it isn't anymore, because a field
  /// *with* a custom `serializer` already throws on a type mismatch in
  /// release builds too (the unsound `as R` inside `serializeErased`), but
  /// a field *without* one doesn't — [_serialize]'s fallback case passes
  /// any unrecognized value straight through — so release builds were
  /// silently writing wrong data for exactly the fields that don't crash.
  /// Checking unconditionally costs one cheap `is` check per field and
  /// closes that gap.
  static Json _buildJson<M>(ListFieldOf<M> fields, Props props) {
    if (fields.length != props.length) {
      throw StateError(
        'Serializable.toJson(): fields has ${fields.length} entries but '
        'props has ${props.length}. Both must list every field, in the '
        "same order as the model's constructor parameters.",
      );
    }

    final result = <String, Object?>{};

    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final val = props[i];

      if (!f.acceptsValue(val)) {
        throw StateError(
          'Serializable.toJson(): props[$i] ($val: ${val.runtimeType}) '
          'does not look like it belongs to fields[$i] (jsonKey '
          '"${f.jsonKey}"). fields and props are probably out of order — '
          'both must list every field in the same order as the model\'s '
          'constructor parameters.',
        );
      }

      final serialized = f.hasSerializer
          // Use the type-erased wrapper — safe with an erased type.
          ? f.serializeErased(val)
          // Default smart serialization.
          : _serialize(val);

      // Write by the full path (account for nesting via at()).
      _writeDeep(result, [...f.nesting, f.jsonKey], serialized);
    }

    return result;
  }

  // ===========================================================================
  // _serialize — smart recursive serializer
  // ===========================================================================

  /// Recursively serializes a Dart value into a JSON-compatible type.
  ///
  /// ### Mapping Table
  /// | Dart Type          | JSON Representation                 |
  /// |--------------------|---------------------------------------|
  /// | null               | null                                  |
  /// | SerializableModelI | `.toJson()`                           |
  /// | DateTime           | ISO-8601 string (toIso8601String)     |
  /// | Duration           | milliseconds (int)                    |
  /// | Uri                | string                                |
  /// | BigInt              | string                                |
  /// | Enum               | `.name`                               |
  /// | List / Set         | recursively serialized List           |
  /// | Map                | keys via `.toString()`, values recursively |
  /// | num / bool / String| unchanged                             |
  static Object? _serialize(Object? v) => switch (v) {
    null => null,
    // Models are serialized via their own toJson.
    final SerializableModelI m => m.toJson(),
    // Collections — recursively.
    final List l => l.map(_serialize).toList(growable: false),
    final Set s => s.map(_serialize).toList(growable: false),
    final Map m => {
      for (final MapEntry(:key, :value) in m.entries)
        key.toString(): _serialize(value),
    },
    // Special types — into strings/numbers.
    final DateTime dt => dt.toIso8601String(),
    final Duration d => d.inMilliseconds,
    final Uri u => u.toString(),
    final BigInt b => b.toString(),
    final Enum e => e.name,
    // Primitives (int, double, String, bool) — unchanged.
    _ => v,
  };

  // ===========================================================================
  // Path helpers
  // ===========================================================================

  /// Reads a value from [json] by the composite path `[...nesting, key]`.
  ///
  /// Each [nesting] step is a key of a nested Map.
  /// If the value is not a Map at any step — returns null (field is missing).
  ///
  /// Example: `nesting=['meta', 'stats']`, `key='count'`
  ///   → reads `json['meta']['stats']['count']`
  ///
  /// Descends via [Map.cast] rather than [Map.from]: [Map.cast] returns an
  /// O(1) typed *view* over the same underlying map, not a copy. Every
  /// field sharing a nesting prefix (e.g. six fields all declared via
  /// `at('statistics', ...)`) calls this independently from the root —
  /// with a real copy at each level, that's an O(map size) allocation
  /// paid again per field per level, for a value that's discarded after
  /// reading exactly one key out of it. A view has none of that cost:
  /// [current[step]] on a `CastMap` only checks the *type of the one
  /// value actually read*, never touches or duplicates the rest of the
  /// map's entries.
  static Object? _readPath(Json json, List<String> nesting, String key) {
    Json current = json;
    for (final step in nesting) {
      final next = current[step];
      if (next is! Map) return null;
      current = next.cast<String, Object?>();
    }
    return current[key];
  }

  /// Writes [value] to [map] by the composite path [keys].
  ///
  /// Creates intermediate Maps if necessary.
  /// If an intermediate key is explicitly null — the write is skipped
  /// (cannot add a key to null).
  ///
  /// Example: `keys=['meta', 'stats', 'count']`, `value=42`
  ///   → `map['meta']['stats']['count'] = 42`
  ///
  /// Internal — used by [_buildJson] to write fields declared via `at(...)`
  /// to their nested position when serializing.
  static void _writeDeep(Json map, List<String> keys, Object? value) {
    var current = map;
    for (var i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      // If the value is explicitly null, there is nothing to descend into
      // by design (e.g. a nullable nested model that is currently null) —
      // skip the write rather than materializing a Map under a key that's
      // meant to represent "absent".
      if (current.containsKey(key) && current[key] == null) return;
      final next = current.putIfAbsent(key, () => <String, Object?>{});
      // Something other than a Map already occupies this slot — this is a
      // genuine key collision (e.g. two fields, one flat and one nested
      // via at(), sharing a path prefix), not an expected "absent"
      // case. Fail loudly instead of silently dropping the write — a
      // quiet no-op here previously made a write vanish with no error at
      // all.
      if (next is! Map) {
        throw StateError(
          'writeDeep: cannot write to path '
          '"${[...keys.take(i + 1)].join('.')}" — that key already holds '
          'a ${next.runtimeType}, not a nested object. Check for two '
          'fields whose paths collide (one flat, one declared via at()).',
        );
      }
      current = next as Json;
    }
    current[keys.last] = value;
  }
}
