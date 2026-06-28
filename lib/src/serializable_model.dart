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
//      `fromJson`/`copyWith` (and threw a raw cast TypeError on a custom
//      `serializer` instead, since `null as R` is unsound for non-nullable
//      `R`). `toJson()` is now built from `fields` + `props` (see
//      [Serializable] below) — real values, regardless of how the instance
//      was constructed, with no per-field getter required. A length
//      mismatch between `fields` and `props` is now a clear `StateError`
//      (not a debug-only assert), and a per-slot `is R` check (debug-only;
//      see `Field.acceptsValue`) catches many — not all — cases of the two
//      lists being out of order.
// =============================================================================

import 'package:equatable/equatable.dart';

import 'errors.dart';
import 'types/types.dart';

// =============================================================================
// Sentinel — marker for "value not passed"
// =============================================================================

/// Marker indicating "parameter not passed — keep the original value".
///
/// Conceptually different from `null`:
/// ```dart
/// user.copyWith(address: null)   // explicitly sets address to null
/// user.copyWith(name: 'Bob')     // address remains the same
/// ```
///
/// Used only in copyWith signatures. Check via [identical]:
/// ```dart
/// if (!identical(value, undefined)) { /* value was passed */ }
/// ```
const Object undefined = _Undefined();

/// Internal singleton class for the marker. Private — cannot be instantiated outside.
final class _Undefined {
  const _Undefined();

  @override
  String toString() => 'undefined';
}

// =============================================================================
// SerializableModelI — model interface
// =============================================================================

/// Contract that every serializable model must implement.
///
/// Use the [Serializable] mixin for an automatic implementation of
/// [toJson] — built from [fields] and [props] together. [props] itself is
/// **not** automatic: it's the standard `Equatable` list, and it's what
/// makes [toJson] (and `==`/`hashCode`, via `Equatable`) correct for *any*
/// instance, not just ones built via `fromJson`/`copyWith`.
///
/// ### Field Requirements ([fields] and [props])
/// [fields] must list a descriptor for every model field, and [props] must
/// list that field's current value — **both in the same order, matching
/// the constructor's parameter order.** This is critical for two reasons:
/// [SerializableHelpers.fromJson] passes parsed values to the constructor
/// positionally via [Function.apply], and [Serializable.toJson] zips
/// [fields] with [props] index-for-index to build the JSON. A length
/// mismatch between the two throws a clear [StateError] immediately; an
/// `is`-compatible-but-wrong-order mix-up (two fields of the same type
/// swapped) is checked best-effort in debug mode — see
/// [Field.acceptsValue].
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
/// This mixin does **not** implement [props] for you — `Equatable` still
/// requires you to declare it, exactly as in plain `Equatable` usage. The
/// reason is fundamental, not a missing feature: without code generation
/// or runtime reflection (unavailable on Flutter/AOT), there is no way to
/// read a model's current field values generically. A per-field getter
/// closure on [Field] could do it, but would need to be both declared by
/// the user *and* threaded through `Field<M, R>`'s type erasure — `props`
/// gets the same result (real values, for any instance, however it was
/// built) from a single, ordinary `Equatable` list instead, with no
/// strings anywhere in it (a JSON-keyed `Map` was considered and rejected
/// for exactly this reason — it would reintroduce the same stringly-typed
/// duplication `Schema`/`Field` exist to get rid of in the first place).
///
/// ### Full Model Example
///
/// Most models declare a [Schema] and go through [ModelType]/[ModelBinder]
/// instead of the plain field list shown here — see the package README —
/// but `props` is required either way.
/// ```dart
/// class User extends Equatable with Serializable<User> {
///   final int    id;
///   final String name;
///   final String? address;
///
///   const User(this.id, this.name, this.address);
///
///   static final ListFieldOf<User> _fields = [
///     'id'     .field<User, int>(parser: intOrZero),
///     'name'   .field<User, String>(),
///     'address'.field<User, String?>(), // nullable: defaults to `null is R` → true
///   ];
///
///   @override
///   ListFieldOf<User> get fields => _fields;
///
///   // The one manual line `Serializable` doesn't write for you — same
///   // order as `_fields` above, same order as the constructor.
///   @override
///   Props get props => [id, name, address];
///
///   static User fromJson(Map<String, Object?> json) =>
///       SerializableHelpers.fromJson(json, _fields, User.new);
///
///   User copyWith({Object? id = undefined, Object? name = undefined, Object? address = undefined}) =>
///       SerializableHelpers.copyWith(
///         this,
///         {'id': id, 'name': name, 'address': address},
///         User.new,
///       );
/// }
/// ```
mixin Serializable<M extends SerializableModelI<M>> on Equatable
    implements SerializableModelI<M> {
  @override
  Json toJson() => SerializableHelpers._buildJson<M>(fields, props);
}

// =============================================================================
// SerializableHelpers — serialization engine
// =============================================================================

/// Static engine: deserialization, serialization, copyWith.
///
/// Not intended for direct inheritance. Use via the [Serializable] mixin
/// and static methods [fromJson] / [copyWith].
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
          message:
              'Positional constructor call failed. Make sure the fields in '
              '`fields` are declared in the same order as the constructor '
              'parameters.',
        ),
        st,
      );
    }
  }

  // ===========================================================================
  // copyWith
  // ===========================================================================

  /// Creates a copy of [instance] with selectively replaced fields.
  ///
  /// ### Algorithm
  /// 1. Serializes [instance] via `toJson()`.
  /// 2. For each [patch] entry with a value other than [undefined]:
  ///    - Applies [_serialize] to the value (Dart object → JSON primitive).
  ///    - Writes the result to JSON by `jsonKey`.
  /// 3. Deserializes the updated JSON back into [R] via [fromJson].
  ///
  /// ### Serialization Contract
  /// [_serialize] and parsers must be consistent:
  ///   - DateTime → ISO-8601 string → dateTimeOrNull understands ISO-8601 ✓
  ///   - Enum     → `.name`         → enumOrDefault compares by name ✓
  ///   - Model    → `.toJson()`     → modelOf(fromJson) ✓
  ///
  /// ### Advantages over Symbol-based approach
  /// - No Symbol — does not break with `--obfuscate`.
  /// - No positional list — adding a field does not shift arguments.
  /// - Order-independence — patch-Map is indexed by jsonKey.
  ///
  /// ### Values in [patch]
  /// | Value           | Effect                                          |
  /// |-----------------|-------------------------------------------------|
  /// | `undefined`     | field is not changed (original value)           |
  /// | `null`          | field is set to null (only for nullable)        |
  /// | any other       | field is overwritten by this value              |
  ///
  /// Keys in [patch] are **jsonKey** (strings from JSON), not Dart names.
  static R copyWith<R extends SerializableModelI<R>>(
    R instance,
    Json patch,
    Function factory,
  ) {
    // Start with the current JSON state of the model.
    final json = instance.toJson();

    for (final entry in patch.entries) {
      // undefined = "do not touch". Skip such entries.
      if (identical(entry.value, undefined)) continue;

      // Serialize the Dart value into a JSON-compatible type.
      // This ensures consistency with parsers during repeated fromJson.
      json[entry.key] = _serialize(entry.value);
    }

    // Full deserialization — all parsers and type checks are executed.
    return fromJson<R>(json, instance.fields, factory);
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
  /// Throws [StateError] (in every build mode, not just debug) if `fields`
  /// and `props` differ in length — the single most common way the two get
  /// out of sync (a field added to one but not the other). A same-length
  /// but wrong-*order* mistake is checked best-effort in debug mode only,
  /// via [Field.acceptsValue] — see the `assert` below.
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
  /// | BigInt             | string                                |
  /// | Enum               | `.name`                               |
  /// | List / Set         | recursively serialized List           |
  /// | Map                | keys via `.toString()`, values recursively |
  /// | num / bool / String| unchanged                             |
  ///
  /// Public alias: [serializeValue] — for use in [ModelBinder].
  static Object? serializeValue(Object? v) => _serialize(v);

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
  static Object? _readPath(Json json, List<String> nesting, String key) {
    Json current = json;
    for (final step in nesting) {
      final next = current[step];
      if (next is! Map) return null;
      current = Json.from(next);
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
  /// Public method — used in [ModelBinder] to write patches
  /// of nested fields (declared via `at(...)`).
  /// ignore: library_private_types_in_public_api
  static void writeDeep(Json map, List<String> keys, Object? value) =>
      _writeDeep(map, keys, value);

  static void _writeDeep(Json map, List<String> keys, Object? value) {
    var current = map;
    for (var i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      // If the value is explicitly null — cannot enter it as a Map, skip.
      if (current.containsKey(key) && current[key] == null) return;
      final next = current.putIfAbsent(key, () => <String, Object?>{});
      // Something other than a Map already occupies this slot — there's
      // nothing sensible to descend into. Skip rather than letting an
      // unrelated `as Json` cast fail with a raw, uninformative TypeError.
      if (next is! Map) return;
      current = Json.from(next);
    }
    current[keys.last] = value;
  }
}
