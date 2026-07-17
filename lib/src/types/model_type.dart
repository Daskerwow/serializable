// =============================================================================
// model_type.dart
//
// Typed model schema and binding to a model's constructor.
//
// Defined here:
//   Schema<M>    — abstract schema of a model's fields.
//   ModelType    — binds a Schema to the model's constructor, powering
//                  `fromJson`.
//
// `copyWith` is intentionally NOT part of this library. It used to be
// provided here via `Schema.set` + `ModelBinder`, resolving inline-lambda
// selectors (`$.set((m) => m.x, value)`) against a synthetic "probe"
// instance built by calling the model's own constructor with sentinel
// values. That machinery required every model constructor to be free of
// side effects and validation — an implicit contract this library couldn't
// enforce — and it blurred the boundary between the data layer (JSON
// mapping, which this library owns) and the domain layer (value-object
// semantics, which a model's own immutable `copyWith` belongs to). Write
// `copyWith` by hand on the domain entity instead — it's a handful of
// lines and has no dependency on this library at all.
// =============================================================================

import '../extension.dart';
import '../serializable_model.dart';
import 'field.dart';
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
  /// [getter] is optional and lets this field read its own current value
  /// off a model instance (`getter: (m) => m.uid`). It has nothing to do
  /// with parsing — it exists purely so [Serializable]'s default `props`
  /// can be built from `Schema.all` alone, without a separately
  /// hand-maintained `props` list. Skip it and keep overriding `props`
  /// yourself if you prefer; the two styles can even be mixed per field,
  /// though a model should pick one style consistently.
  Field<M, R> field<R>(
    String jsonKey, {
    R Function(M)? getter,
    R Function(Object?)? parser,
    Serializer<R>? serializer,
    bool? nullable,
  }) => buildField<M, R>(
    jsonKey: jsonKey,
    parser: parser,
    serializer: serializer,
    nullable: nullable,
    getter: getter,
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
/// Used as a single entry point for deserialization:
/// ```dart
/// // M is specified explicitly — Dart cannot infer it from the positional constructor.
/// static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());
///
/// // Deserialization:
/// final sensor = Sensor.$.call(json);
/// ```
///
/// The constructor is stored as a `Function` and invoked via [Function.apply]
/// with positional arguments (the same mechanism as in [SerializableHelpers.fromJson]).
final class ModelType<M extends SerializableModelI<M>> {
  const ModelType(this._factory, this.schema);

  final Function _factory;

  /// Typed field schema — public so a model's `fields` getter can read
  /// `schema.all`.
  final Schema<M> schema;

  /// Deserializes [json] into [M].
  ///
  /// Delegates to [SerializableHelpers.fromJson] with fields from
  /// [schema]'s `all`.
  M call(Json json) =>
      SerializableHelpers.fromJson<M>(json, schema.all, _factory);
}
