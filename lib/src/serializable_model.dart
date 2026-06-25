// =============================================================================
// serializable_model.dart
//
// Serialization core: the model interface, the Serializable mixin, and the
// SerializableHelpers engine (fromJson / toJson / copyWith).
// =============================================================================

import 'package:equatable/equatable.dart';

import 'errors.dart';
import 'types/types.dart';

// =============================================================================
// Sentinel — marker for "value not passed"
// =============================================================================

/// Marker meaning "this parameter wasn't passed — keep the original value".
///
/// Conceptually different from `null`:
/// ```dart
/// SerializableHelpers.copyWith(user, {'address': null}, User.new);  // clears address
/// SerializableHelpers.copyWith(user, {'name': 'Bob'}, User.new);    // address untouched
/// ```
///
/// Used by the low-level, Map-based `SerializableHelpers.copyWith`. Check
/// with [identical]:
/// ```dart
/// if (!identical(value, undefined)) { /* value was actually passed */ }
/// ```
///
/// If your model uses [ModelType]/[ModelBinder] for `copyWith` (the
/// recommended setup), you won't need this: `copyWith(($) => [...])` only
/// ever touches the fields you explicitly `.set(...)`.
const Object undefined = _Undefined();

/// Internal singleton backing [undefined]. Private — can't be instantiated
/// from outside this library.
final class _Undefined {
  const _Undefined();

  @override
  String toString() => 'undefined';
}

// =============================================================================
// SerializableModelI — the model contract
// =============================================================================

/// The contract every serializable model must implement.
///
/// Use the [Serializable] mixin for an automatic [toJson] and [props].
///
/// ### [fields]
/// Must list a descriptor for *every* model field, in the same order as the
/// constructor parameters. This is load-bearing:
/// `SerializableHelpers.fromJson` passes parsed values as positional
/// arguments via `Function.apply`.
abstract interface class SerializableModelI<M extends SerializableModelI<M>> {
  /// All field descriptors, in constructor-parameter order.
  ///
  /// Typically backed by a `static final` [ModelType]:
  /// ```dart
  /// static final $ = ModelType<User>(User.new, [...]);
  /// @override
  /// ListFieldOf<User> get fields => $.all;
  /// ```
  ListFieldOf<M> get fields;

  /// Serializes this instance into a JSON-compatible [Map].
  Json toJson();

  /// Field values in declaration order — feeds [Equatable.props].
  Props get props;
}

// =============================================================================
// Serializable — mixin with automatic toJson / props
// =============================================================================

/// Supplies automatic [toJson] and [props] implementations, derived from
/// [SerializableModelI.fields].
///
/// ### A complete model, end to end
/// ```dart
/// class Sensor extends Equatable with Serializable<Sensor> {
///   const Sensor(this.uid, this.value);
///
///   final String uid;
///   final double value;
///
///   // A named Record, listing each field by its Dart-facing name — this
///   // is what lets `copyWith` read `$.value.set(...)` with no string keys
///   // and no reflection. See `ModelType.bind`'s doc comment for why.
///   static final _fields = (
///     uid: 'sensor_uid'.field<Sensor, String>((m) => m.uid),
///     value: 'last_value'.field<Sensor, double>((m) => m.value, parser: doubleOrZero),
///   );
///
///   // M is explicit — Dart can't infer it from a positional constructor.
///   // The order here is what `Function.apply` uses — it must match the
///   // constructor parameter order above.
///   static final $ = ModelType<Sensor>(Sensor.new, [_fields.uid, _fields.value]);
///
///   @override
///   ListFieldOf<Sensor> get fields => $.all;
///
///   factory Sensor.fromJson(Json json) => $.call(json);
///
///   late final copyWith = $.bind(this, _fields);
/// }
///
/// // sensor.copyWith(($) => [$.value.set(99.9)]);
/// ```
///
/// Don't need type-safe `copyWith` for a particular model? Skip the Record
/// entirely and feed `ModelType` a plain list literal — see `ModelType`'s
/// own doc comment for that minimal shape.
mixin Serializable<M extends SerializableModelI<M>> on Equatable
    implements SerializableModelI<M> {
  @override
  Json toJson() => SerializableHelpers._buildJson<M>(fields, this as M);

  @override
  Props get props => [for (final f in fields) f.getter(this)];
}

// =============================================================================
// SerializableHelpers — the serialization engine
// =============================================================================

/// Static engine behind deserialization, serialization, and `copyWith`.
///
/// Not meant to be subclassed. Used via the [Serializable] mixin, and via
/// `ModelType`/`ModelBinder` for the field-schema-driven workflow.
final class SerializableHelpers {
  SerializableHelpers._();

  // ===========================================================================
  // fromJson
  // ===========================================================================

  /// Deserializes [json] into model [R].
  ///
  /// ### Algorithm
  /// 1. For each field in [fields]:
  ///    a. Reads the raw value at `[...nesting, jsonKey]` via [_readPath].
  ///    b. Runs `field.parser(raw)`.
  ///    c. If the result is `null` and the field isn't `Field.nullable` —
  ///       throws [RequiredFieldError].
  /// 2. Passes every value as a *positional* argument to [factory] via
  ///    `Function.apply`.
  ///
  /// ### Why positional
  /// `Function.apply(factory, args)` is always a positional call. The order
  /// of [fields] must match the constructor's parameter order exactly.
  /// Named-argument dispatch isn't used — it's slower, and it breaks under
  /// `dart compile exe --obfuscate`.
  static R fromJson<R extends SerializableModelI<R>>(
    Json json,
    ListFieldOf<R> fields,
    Function factory,
  ) {
    final args = <Object?>[];

    for (final f in fields) {
      final raw = _readPath(json, f.nesting, f.jsonKey);
      Object? value;

      try {
        value = f.parser(raw);
      } on SerializationError {
        // Typed errors already carry full context — propagate as-is.
        rethrow;
      } catch (e, st) {
        // Anything else gets wrapped, with context attached.
        Error.throwWithStackTrace(
          SerializationError(
            modelType: R,
            fieldName: f.fieldName,
            path: [...f.nesting, f.jsonKey].join('.'),
            rawValue: raw,
            cause: e,
          ),
          st,
        );
      }

      // ── Null guard — the one place required fields are enforced ─────────
      //   value == null && !nullable → RequiredFieldError
      //   value == null &&  nullable → fine, null is passed to the constructor
      if (value == null && !f.nullable) {
        throw RequiredFieldError(
          modelType: R,
          fieldName: f.fieldName,
          path: [...f.nesting, f.jsonKey].join('.'),
          rawValue: raw,
        );
      }

      args.add(value);
    }

    try {
      return Function.apply(factory, args) as R;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SerializationError(
          modelType: R,
          fieldName: '<constructor>',
          path: R.toString(),
          cause: e,
          message:
              'Positional constructor call failed. Make sure the fields '
              'passed to `ModelType` are declared in exactly the same '
              'order as the constructor parameters of $R.',
        ),
        st,
      );
    }
  }

  // ===========================================================================
  // copyWith (low-level, Map-based)
  // ===========================================================================

  /// Creates a copy of [instance] with selectively replaced fields.
  ///
  /// This is the low-level building block. If your model uses [ModelType]/
  /// [ModelBinder] (the recommended setup), prefer the type-safe
  /// `instance.copyWith(($) => [$.field.set(value)])` instead — it doesn't
  /// need the [undefined] sentinel, and a misspelled field name is a
  /// compile error rather than something you find at runtime.
  ///
  /// ### Algorithm
  /// 1. Serializes [instance] via `toJson()`.
  /// 2. For each entry in [patch] whose value isn't [undefined]: serializes
  ///    it via [_serialize] and writes it under that key.
  /// 3. Deserializes the updated JSON back into [R] via [fromJson] — so
  ///    every parser and required-field check runs again.
  ///
  /// ### Serialization contract
  /// [_serialize] and the field parsers must agree on a wire format:
  ///   - `DateTime` → ISO-8601 string → `dateTimeOrNull` reads ISO-8601 ✓
  ///   - `Enum`     → `.name`         → `enumOrDefault` compares by name ✓
  ///   - model      → `.toJson()`     → `modelOf(fromJson)` ✓
  ///
  /// ### Values in [patch]
  /// | Value       | Effect                                    |
  /// |-------------|---------------------------------------------|
  /// | [undefined] | field is untouched                          |
  /// | `null`      | field is set to `null` (only if nullable)   |
  /// | anything    | field is overwritten with that value        |
  ///
  /// Keys in [patch] are JSON keys, not Dart property names.
  static R copyWith<R extends SerializableModelI<R>>(
    R instance,
    Json patch,
    Function factory,
  ) {
    final json = instance.toJson();

    for (final entry in patch.entries) {
      if (identical(entry.value, undefined)) continue;
      json[entry.key] = _serialize(entry.value);
    }

    return fromJson<R>(json, instance.fields, factory);
  }

  // ===========================================================================
  // toJson (internal)
  // ===========================================================================

  /// Builds a JSON map from a model's fields.
  ///
  /// Each field is serialized via its custom serializer (through the
  /// type-erased wrapper) if it has one, or via [_serialize] otherwise.
  /// Fields declared with nesting (via `at(...)`) are written through
  /// [_writeDeep], which creates the intermediate maps on the fly.
  static Json _buildJson<M>(ListFieldOf<M> fields, M instance) {
    final result = <String, Object?>{};

    for (final f in fields) {
      final val = f.getter(instance);
      final serialized = f.hasSerializer
          ? f.serializeErased(val)
          : _serialize(val);

      _writeDeep(result, [...f.nesting, f.jsonKey], serialized);
    }

    return result;
  }

  // ===========================================================================
  // _serialize — smart recursive serializer
  // ===========================================================================

  /// Recursively serializes a Dart value into a JSON-compatible value.
  ///
  /// | Dart type                 | JSON representation                      |
  /// |----------------------------|-------------------------------------------|
  /// | `null`                     | `null`                                    |
  /// | `SerializableModelI`       | `.toJson()`                               |
  /// | `DateTime`                 | ISO-8601 string (`toIso8601String`)       |
  /// | `Duration`                 | milliseconds (`int`)                      |
  /// | `Uri`                      | string                                    |
  /// | `BigInt`                   | string                                    |
  /// | `Enum`                     | `.name`                                   |
  /// | `List` / `Set`             | recursively-serialized `List`             |
  /// | `Map`                      | keys via `.toString()`, values recursive  |
  /// | `num` / `bool` / `String`  | unchanged                                 |
  ///
  /// Public alias: [serializeValue] — used by `ModelBinder`.
  static Object? serializeValue(Object? v) => _serialize(v);

  static Object? _serialize(Object? v) => switch (v) {
    null => null,
    final SerializableModelI m => m.toJson(),
    final List l => l.map(_serialize).toList(growable: false),
    final Set s => s.map(_serialize).toList(growable: false),
    final Map m => {
      for (final e in m.entries) e.key.toString(): _serialize(e.value),
    },
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

  /// Reads a value from [json] at the composite path `[...nesting, key]`.
  ///
  /// Each [nesting] step must itself be a `Map`; if it isn't, the field is
  /// treated as missing and `null` is returned.
  ///
  /// Example: `nesting = ['meta', 'stats']`, `key = 'count'` reads
  /// `json['meta']['stats']['count']`.
  static Object? _readPath(Json json, List<String> nesting, String key) {
    Json current = json;
    for (final step in nesting) {
      final next = current[step];
      if (next is! Map) return null;
      current = Json.from(next);
    }
    return current[key];
  }

  /// Writes [value] into [map] at the composite path [keys], creating any
  /// missing intermediate maps along the way.
  ///
  /// If an intermediate key is explicitly `null`, the write is skipped (you
  /// can't add a key to `null`).
  ///
  /// Example: `keys = ['meta', 'stats', 'count']`, `value = 42` writes
  /// `map['meta']['stats']['count'] = 42`.
  ///
  /// Public so `ModelBinder` can write patches for nested fields (those
  /// declared via `at(...)`).
  static void writeDeep(Json map, List<String> keys, Object? value) =>
      _writeDeep(map, keys, value);

  static void _writeDeep(Json map, List<String> keys, Object? value) {
    var current = map;
    for (var i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      if (current.containsKey(key) && current[key] == null) return;
      current = current.putIfAbsent(key, () => <String, Object?>{}) as Json;
    }
    current[keys.last] = value;
  }
}
