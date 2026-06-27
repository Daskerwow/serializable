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
/// Use the [Serializable] mixin for automatic implementation of [toJson] and [props].
///
/// ### Field Requirements ([fields])
/// The [fields] list must contain descriptors for ALL model fields
/// in the same order as the constructor parameters. This is critical: [SerializableHelpers.fromJson]
/// passes values as positional arguments via [Function.apply].
abstract interface class SerializableModelI<M extends SerializableModelI<M>> {
  /// All field descriptors in the order of constructor parameters.
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

  /// Field values in the order of declaration — used by [Equatable].
  Props get props;
}

// =============================================================================
// Serializable — mixin with automatic implementation
// =============================================================================

/// Provides automatic implementations of [toJson] and [props] via [fields].
///
/// ### Full Model Example
///
/// This shows the engine's two lowest-level building blocks directly: a
/// plain [ListFieldOf] and the `undefined`-sentinel `copyWith`. Most models
/// instead declare a [Schema] and go through [ModelType]/[ModelBinder],
/// which wrap both of these and add type-safe, name-based field access —
/// see the package README.
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
  Json toJson() => SerializableHelpers._buildJson<M>(fields, this as M);

  @override
  Props get props => [for (final f in fields) f.readErased(this)];
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
            path: [...f.nesting, f.jsonKey].join('.'),
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
          path: [...f.nesting, f.jsonKey].join('.'),
          rawValue: raw,
        );
      }

      args.add(value);
    }

    // Call the constructor with positional arguments.
    try {
      final instance = Function.apply(factory, args) as R;

      // Attach the already-parsed args back onto their fields — strictly
      // positional, the same order used when building args. No re-parsing.
      for (var i = 0; i < fields.length; i++) {
        fields[i].attach(instance as Object, args[i]);
      }

      return instance;
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

  /// Builds a JSON-Map from the model fields.
  ///
  /// For each field:
  ///   - If there is a custom serializer → use it via the type-erased wrapper.
  ///   - Otherwise → [_serialize] with default smart logic.
  ///
  /// Fields with nesting are written via [_writeDeep] — creates nested Maps on the fly.
  static Json _buildJson<M>(ListFieldOf<M> fields, M instance) {
    final result = <String, Object?>{};

    for (final f in fields) {
      final val = f.readErased(instance as Object);

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
      for (final e in m.entries) e.key.toString(): _serialize(e.value),
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
  // ignore: library_private_types_in_public_api
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
      current = next as Json;
    }
    current[keys.last] = value;
  }
}
