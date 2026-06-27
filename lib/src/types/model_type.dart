// =============================================================================
// model_type.dart
//
// Typed model schema and convenient copyWith via ModelBinder.
//
// Defined here:
//   Schema<M>    — abstract schema of a model's fields.
//   ModelType    — binds a Schema to the model's constructor.
//   ModelBinder  — stored callable copyWith for a specific instance.
//
// Used here, defined elsewhere:
//   FieldPatch / FieldPatchX (field_patch.dart, field.dart) — the
//   `$.field.set(value)` mechanism that feeds ModelBinder.call.
// =============================================================================

import '../extension.dart';
import '../serializable_model.dart';
import 'field.dart';
import 'field_patch.dart';
import 'types.dart';

// =============================================================================
// Schema — declared by extending this class and listing fields as members
// =============================================================================

abstract base class Schema<M> {
  /// [R] is inferred from [parser] (e.g. `parser: stringOrEmpty` gives
  /// `R = String` directly, with no annotation needed). If [parser] isn't
  /// given, there's nothing left to infer [R] from, so it must be supplied
  /// explicitly: `field<String>('sensor_uid')`.
  ///
  /// [nullable] defaults to `null is R` when omitted — pass it explicitly
  /// only to override that default.
  Field<M, R> field<R>(
    String jsonKey, {
    R Function(Object?)? parser,
    Serializer<R>? serializer,
    bool? nullable,
  }) => buildField<M, R>(
    jsonKey: jsonKey,
    parser: parser,
    serializer: serializer,
    nullable: nullable,
  );

  /// All fields declared via [field], in declaration order.
  ///
  /// This must list every field in the same order as the model's
  /// constructor parameters — see [ModelType] for why.
  ListFieldOf<M> get all;
}

// =============================================================================
// ModelType — Schema + constructor binding
// =============================================================================

/// Binds a [Schema] to the model [M]'s constructor.
///
/// Used as a single entry point for deserialization and copyWith:
/// ```dart
/// // M is specified explicitly — Dart cannot infer it from the positional constructor.
/// static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());
///
/// // Deserialization:
/// final sensor = Sensor.$.call(json);
///
/// // copyWith via bind:
/// late final copyWith = Sensor.$.bind(this);
/// ```
///
/// The constructor is stored as a `Function` and invoked via [Function.apply]
/// with positional arguments (the same mechanism as in [SerializableHelpers.fromJson]).
final class ModelType<M extends SerializableModelI<M>, S extends Schema<M>> {
  const ModelType(this._factory, this.schema);

  final Function _factory;

  /// Typed field schema — public so a model's `fields` getter can read
  /// `schema.all`, and so [ModelBinder] can hand it to a `copyWith` builder
  /// as `$`.
  final S schema;

  /// Deserializes [json] into [M].
  ///
  /// Delegates to [SerializableHelpers.fromJson] with fields from
  /// [schema]'s `all`.
  M call(Json json) =>
      SerializableHelpers.fromJson<M>(json, schema.all, _factory);

  /// Creates a [ModelBinder] bound to a specific [instance].
  ///
  /// It is recommended to assign it as `late final copyWith` in the model —
  /// then [ModelBinder] is created once and cached:
  ///
  /// ```dart
  /// class Sensor ... {
  ///   late final copyWith = Sensor.$.bind(this);
  /// }
  ///
  /// // Usage:
  /// final updated = sensor.copyWith(($) => [$.value.set(99.9)]);
  /// ```
  ModelBinder<M, S> bind(M instance) => ModelBinder._(instance, this);
}

// =============================================================================
// ModelBinder — stored callable copyWith
// =============================================================================

/// Callable stored as `late final copyWith` on a model instance.
///
/// ```dart
/// final updated = sensor.copyWith(($) => [$.value.set(99.9)]);
/// final cleared = user.copyWith(($) => [$.address.set(null)]);
/// ```
///
/// ### Algorithm
/// 1. Serializes the current instance via `toJson()`.
/// 2. For each [FieldPatch] from [updates]:
///    - Serializes the new value via [SerializableHelpers.serializeValue].
///    - Writes to the full path `[patch.nesting..., patch.jsonKey]`
///      via [SerializableHelpers.writeDeep].
/// 3. Deserializes the updated JSON back via `_type(json)`.
///
/// `writeDeep` with nesting is used instead of a flat
/// `json[patch.jsonKey]`. This correctly handles nested fields.
final class ModelBinder<M extends SerializableModelI<M>, S extends Schema<M>> {
  const ModelBinder._(this._instance, this._type);

  final M _instance;
  final ModelType<M, S> _type;

  M call(Iterable<FieldPatch> Function(S $) updates) {
    // Start with the current JSON state of the model.
    final json = Json.from(_instance.toJson());

    for (final patch in updates(_type.schema)) {
      // Serialize the Dart value into a JSON primitive.
      final serialized = SerializableHelpers.serializeValue(patch.value);

      // Write to the full path (nesting + jsonKey),
      // not a flat json[patch.jsonKey].
      SerializableHelpers.writeDeep(json, [
        ...patch.nesting,
        patch.jsonKey,
      ], serialized);
    }

    // Full deserialization — all parsers are executed.
    return _type(json);
  }
}
