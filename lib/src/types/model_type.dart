// =============================================================================
// model_type.dart
//
// Typed model schema and convenient copyWith via ModelBinder.
//
// Components:
//   FieldPatch   — transport object for a single field change.
//   FieldPatchX  — extension Field<M,R>.set(value) → FieldPatch.
//   FieldSet<M>  — abstract schema of model fields.
//   ModelType    — binds FieldSet to the model constructor.
//   ModelBinder  — stored callable copyWith for a specific instance.
// =============================================================================

import 'field.dart';
import '../serializable_model.dart';
import 'types.dart';

// =============================================================================
// FieldPatch
// =============================================================================

/// Transport object carrying a single field change for [ModelBinder.call].
///
/// Created exclusively via [FieldPatchX.set]:
/// ```dart
/// $.price.set(9.99)   // → FieldPatch('price', ['some_nesting'], 9.99)
/// ```
final class FieldPatch {
  const FieldPatch(this.jsonKey, this.nesting, this.value);

  /// JSON key of the field (the last component of the path).
  final String jsonKey;

  /// Path of ancestor keys (empty for top-level fields).
  final List<String> nesting;

  /// New value for the field.
  final Object? value;
}

// =============================================================================
// FieldPatchX — Field extension for creating a patch
// =============================================================================

extension FieldPatchX<M, R> on Field<M, R> {
  /// Creates a [FieldPatch] for this field with the given value.
  ///
  /// Usage:
  /// ```dart
  /// model.copyWith(($) => [
  ///   $.price.set(9.99),
  ///   $.title.set('New title'),
  /// ]);
  /// ```
  FieldPatch set(R value) => FieldPatch(jsonKey, nesting, value);
}

// =============================================================================
// FieldSet — abstract schema of model fields
// =============================================================================

/// Typed schema of fields for model [M].
///
/// Declare one subclass per model; each field is a final property.
/// The [all] list must contain all fields in the order of constructor parameters.
///
/// ```dart
/// final class _SensorFields extends FieldSet<Sensor> {
///   final uid = 'sensor_uid'.field<Sensor, String>((m) => m.uid);
///
///   final value = 'last_value'.field<Sensor, double>(
///     (m) => m.value,
///     parser: doubleOrZero,
///   );
///
///   final history = 'history_logs'.field<Sensor, List<DateTime>>(
///     (m) => m.history,
///     parser: listOf(dateTimeOrEpoch),
///   );
///
///   @override
///   late final all = <FieldOf<Sensor>>[uid, value, history];
/// }
/// ```
///
/// `late final all` — lazy initialization: the list is created once
/// on first access, not on every getter call.
abstract base class FieldSet<M> {
  /// Все поля в порядке параметров конструктора модели [M].
  ListFieldOf<M> get all;
}

// =============================================================================
// ModelType — FieldSet + constructor binding
// =============================================================================

/// Binds the [FieldSet] schema to the model [M] constructor.
///
/// Used as a single entry point for deserialization and copyWith:
/// ```dart
/// // M is specified explicitly — Dart cannot infer it from the positional constructor.
/// static final $ = ModelType<Sensor, _SensorFields>(Sensor.new, _SensorFields());
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
final class ModelType<M extends SerializableModelI<M>, S extends FieldSet<M>> {
  const ModelType(this._factory, this.fields);

  final Function _factory;

  /// Typed field schema — public for access from [ModelBinder].
  final S fields;

  /// Deserializes [json] into [M].
  ///
  /// Delegates to [SerializableHelpers.fromJson] with fields from [fields.all].
  M call(Json json) =>
      SerializableHelpers.fromJson<M>(json, fields.all, _factory);

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
final class ModelBinder<
  M extends SerializableModelI<M>,
  S extends FieldSet<M>
> {
  const ModelBinder._(this._instance, this._type);

  final M _instance;
  final ModelType<M, S> _type;

  M call(Iterable<FieldPatch> Function(S $) updates) {
    // Start with the current JSON state of the model.
    final json = Json.from(_instance.toJson());

    for (final patch in updates(_type.fields)) {
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
