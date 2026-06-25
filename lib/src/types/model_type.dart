// =============================================================================
// model_type.dart
//
// ModelType   — binds the ordered list of a model's fields to its
//               constructor; the single entry point for fromJson, and what
//               Serializable.toJson/props iterate.
// ModelBinder — a stored, callable copyWith for one specific instance,
//               parameterized over a caller-supplied *schema* — typically a
//               named Record exposing each field by its Dart-facing name,
//               so `copyWith` reads `$.title.set(...)` with zero strings and
//               zero custom lookup machinery. See field.dart's file header
//               for why a Record (rather than a class hierarchy, Symbol, or
//               string key) is the right tool here.
// =============================================================================

import '../serializable_model.dart';
import 'types.dart';

/// Binds the ordered list of [M]'s fields to its constructor.
///
/// The single entry point for deserialization:
/// ```dart
/// static final $ = ModelType<Sensor>(Sensor.new, [_fields.uid, _fields.value]);
///
/// final sensor = Sensor.$.call(json);
/// ```
///
/// [all] is also exactly what `Serializable.toJson`/`Serializable.props`
/// iterate, via `SerializableModelI.fields` — see that mixin's doc comment
/// for a complete, end-to-end example.
///
/// The constructor is stored as a `Function` and invoked via
/// `Function.apply` with positional arguments. [all]'s order must match the
/// model constructor's parameter order exactly — `SerializableHelpers.fromJson`
/// is what actually enforces/uses this.
final class ModelType<M extends SerializableModelI<M>> {
  const ModelType(this._factory, this.all);

  final Function _factory;

  /// Every field, in the order of the model's constructor parameters.
  final ListFieldOf<M> all;

  /// Deserializes [json] into [M].
  M call(Json json) => SerializableHelpers.fromJson<M>(json, all, _factory);

  /// Creates a [ModelBinder] bound to a specific [instance], for type-safe
  /// `copyWith`.
  ///
  /// [schema] carries whatever you want `copyWith`'s builder lambda to see
  /// as `$`. In practice that's almost always a named Record listing each
  /// field by its Dart-facing name:
  /// ```dart
  /// typedef SensorFields = (Field<Sensor, String> uid, Field<Sensor, double> value);
  ///
  /// static final SensorFields _fields = (
  ///   uid: 'sensor_uid'.field<Sensor, String>((m) => m.uid),
  ///   value: 'last_value'.field<Sensor, double>((m) => m.value, parser: doubleOrZero),
  /// );
  ///
  /// static final $ = ModelType<Sensor>(Sensor.new, [_fields.uid, _fields.value]);
  ///
  /// late final copyWith = $.bind(this, _fields);
  /// ```
  ///
  /// `$.uid` / `$.value` inside a `copyWith` builder are then native, fully
  /// checked Record field accesses — there's no string key, no
  /// `Map`/`operator []` lookup, and no reflection involved; [ModelBinder]
  /// only ever calls `updates(schema)` and reads `FieldPatch`es out of
  /// whatever comes back.
  ModelBinder<M, S> bind<S>(M instance, S schema) =>
      ModelBinder<M, S>._(instance, this, schema);
}

/// A callable, stored as `late final copyWith` on a model instance.
///
/// ```dart
/// final updated = sensor.copyWith(($) => [$.value.set(99.9)]);
/// final cleared = user.copyWith(($) => [$.address.set(null)]);
/// ```
///
/// ### Algorithm
/// 1. Serializes the current instance via `toJson()`.
/// 2. For each `FieldPatch` produced by `updates(schema)`:
///    - Serializes the new value via `SerializableHelpers.serializeValue`.
///    - Writes it at the full path `[...patch.nesting, patch.jsonKey]` via
///      `SerializableHelpers.writeDeep` — this is what makes nested fields
///      (declared via `at(...)`) work correctly, unlike a flat
///      `json[patch.jsonKey]` write.
/// 3. Deserializes the updated JSON back via [ModelType.call], so every
///    parser and required-field check runs again.
///
/// [S] is whatever was passed to [ModelType.bind] as `schema` — `ModelBinder`
/// itself doesn't know or care about its shape; it only calls `updates(schema)`
/// and reads `FieldPatch`es out of the result. A named Record is the natural
/// choice (see [ModelType.bind]'s doc comment), but nothing here is Record-specific.
final class ModelBinder<M extends SerializableModelI<M>, S> {
  const ModelBinder._(this._instance, this._type, this._schema);

  final M _instance;
  final ModelType<M> _type;
  final S _schema;

  M call(FieldsBuilder<S> updates) {
    // toJson() always returns a fresh map, so no defensive copy is needed
    // before mutating it below.
    final json = _instance.toJson();

    for (final patch in updates(_schema)) {
      final serialized = SerializableHelpers.serializeValue(patch.value);
      SerializableHelpers.writeDeep(
        json,
        [...patch.nesting, patch.jsonKey],
        serialized,
      );
    }

    return _type(json);
  }
}
