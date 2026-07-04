// =============================================================================
// model_type.dart
//
// Typed model schema and convenient copyWith via ModelBinder.
//
// Defined here:
//   Schema<M>    — abstract schema of a model's fields.
//   ModelType    — binds a Schema to the model's constructor.
//   ModelBinder  — stored callable copyWith for a specific instance.
// =============================================================================

import '../errors.dart';
import '../extension.dart';
import '../serializable_model.dart';
import 'field.dart';
import 'field_patch.dart';
import 'field_probe.dart' show alternateValueFor, enumDomainOfField;
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
    R Function(Object?)? parser,
    Serializer<R>? serializer,
    bool? nullable,
    R Function(M)? getter,
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

  /// Builds a patch for whichever field this [selector] reads.
  ///
  /// Example — the concise inline-lambda form, fully supported:
  /// ```dart
  /// t.copyWith(($) => [
  ///   $.set((m) => m.title, 'ZONE_B'),
  ///   $.set((m) => m.status, DeviceStatus.maintenance),
  /// ]);
  /// ```
  ///
  /// ### How matching works — and why it works for inline lambdas
  ///
  /// The patch returned here is *deferred*: it carries the [selector]
  /// closure itself, not a resolved [Field]. The actual resolution happens
  /// later inside [ModelBinder.call] (see [ModelBinder._resolveSelector]),
  /// against a synthetic *probe* instance — see [ModelBinder._buildProbe]
  /// — rather than the real, live instance. There, for each field, the
  /// probe is passed through both the field's own `getter:` and the
  /// supplied [selector], and the two *results* are compared via
  /// [identical]. A match means "this selector reads the same field as
  /// that getter".
  ///
  /// Comparing the *results*, not the closures, is the whole point: Dart
  /// hands every literal lambda a brand-new closure object, so two
  /// byte-for-byte identical `(m) => m.title` are never `identical` to
  /// each other — they couldn't possibly match that way. Comparing the
  /// values they return side-steps that entirely.
  ///
  /// ### Why comparing against the real instance isn't safe
  ///
  /// Dart's `identical()` compares *by value*, not by reference, for
  /// `int`, `double`, and `bool` — small integers are unboxed, doubles are
  /// frequently unboxed too, and `true`/`false` are process-wide
  /// singletons. There's no per-field "address" for these to tell apart.
  /// So two same-typed fields that happen to hold equal values (e.g.
  /// `last_value: 25.0` and `line_value: 25.0`) are genuinely
  /// indistinguishable on the real instance.
  ///
  /// [ModelBinder] never compares against the real instance for this
  /// reason — it always resolves against a synthetic probe, where every
  /// getter-bearing field is seeded with a value proven distinct from
  /// every other field's seed (see [ModelBinder._buildProbe],
  /// and the fallback exhaustive search in
  /// [ModelBinder._disambiguateFinite] for the finite-domain types —
  /// `bool` and `Enum` — that a single seed can't always separate on
  /// its own).
  ///
  /// ### The one case that remains genuinely unresolvable
  ///
  /// Two fields of the *exact same* `enum` type, both currently the exact
  /// same member, where that field wasn't declared through one of this
  /// library's built-in `enumOr*` parser combinators (so its value domain
  /// is unknown) — or any field whose type this library has no generator
  /// for at all. In both cases, resolution fails loudly with a
  /// [StateError] rather than guessing; use the resolved-field form
  /// instead: `$.fieldName.set(value)`.
  FieldPatch set<R>(R Function(M) selector, R value) =>
      FieldPatch.deferred(selector, value);
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
/// final cleared = user.copyWith(($) => [$.set((m) => m.value, 99.9)]);
/// ```
///
/// ### Two construction algorithms, chosen automatically
///
/// **Direct construction** (used when every field in [Schema.all] has a
/// `getter:`) — no JSON, and no string paths, involved at all: for each
/// field, take the new value from the matching patch if there is one,
/// otherwise read the *current* value straight off the instance via that
/// field's `getter`, then call the model's own constructor with those
/// values positionally via [Function.apply].
///
/// **JSON round-trip** (fallback, used when *any* field lacks a `getter`)
/// — serializes the current instance via `toJson()`, writes each patch to
/// its field's full path, and deserializes back via
/// [SerializableHelpers.fromJson] — every parser runs again, including for
/// untouched fields.
///
/// Selector-style patches (`$.set((m) => m.x, value)`) are resolved to a
/// concrete [Field] *before* either algorithm runs — see
/// [_resolveSelector] and [_buildProbe] for how that resolution stays
/// correct even when several same-typed fields currently hold equal (or,
/// for `bool`/`Enum`, colliding) values.
final class ModelBinder<M extends SerializableModelI<M>, S extends Schema<M>> {
  const ModelBinder._(this._instance, this._type);

  final M _instance;
  final ModelType<M, S> _type;

  M call(FieldsBuilder<S> updates) {
    final fields = _type.schema.all;
    final raw = updates(_type.schema).toList(growable: false);

    // Only pay for building a probe instance when it's actually needed —
    // i.e. when at least one patch is deferred (`$.set((m) => m.x, v)`).
    // Resolved patches (`$.field.set(v)`) never touch it.
    final needsProbe = raw.any((p) => p.isDeferred);
    final probe = needsProbe ? _buildProbe(fields) : null;

    final patches = [
      for (final p in raw)
        p.isDeferred ? _resolveSelector(fields, p, probe as M) : p,
    ];

    return fields.every((f) => f.hasGetter)
        ? _callDirect(fields, patches)
        : _callViaJson(fields, patches);
  }

  // ===========================================================================
  // Probe construction
  // ===========================================================================

  /// Builds a synthetic "probe" instance of [M], used only to disambiguate
  /// `$.set((m) => m.someField, value)` selectors — never returned to the
  /// caller and never touches real data.
  ///
  /// For each getter-bearing field, asks its attached [FieldAltGenerator]
  /// (see field_probe.dart) for a value seeded with that field's own
  /// position — for unbounded types (`double`, `int`, `String`,
  /// `DateTime`, `Duration`, `Uri`, `BigInt`) this is provably different
  /// per field, no matter what the real instance currently holds. Fields
  /// with no generator (nested models, `List`, `Map`, ...) reuse their
  /// real current value — already virtually guaranteed to be distinct
  /// heap objects.
  ///
  /// Fields without a `getter` are never used for selector matching (see
  /// [_resolveSelector]), so they're filled with the real instance's
  /// current value (from [SerializableModelI.props], always present and
  /// index-aligned with `fields` per that interface's contract) purely to
  /// satisfy the constructor's static types.
  M _buildProbe(ListFieldOf<M> fields) {
    final current = _instance.props;

    if (current.length != fields.length) {
      throw StateError(
        '$S.set: cannot resolve a selector — $M.props has '
        '${current.length} entries but its schema declares '
        '${fields.length} fields. Both must list every field, in the same '
        "order as the model's constructor parameters.",
      );
    }

    final args = <Object?>[
      for (var i = 0; i < fields.length; i++)
        fields[i].hasGetter ? _seeded(fields[i], current[i], i) : current[i],
    ];

    return _instantiate(args, context: '<probe>');
  }

  Object? _seeded(FieldOf<M> field, Object? current, int seed) {
    if (current == null) return null;

    return alternateValueFor(
      current,
      seed,
      enumDomain: enumDomainOfField(field),
    );
  }

  // ===========================================================================
  // Selector resolution
  // ===========================================================================

  /// Turns a deferred [FieldPatch] (carrying a selector closure) into a
  /// resolved one — by applying both the selector and each field's
  /// `getter` to [probe] and comparing the results with [identical].
  FieldPatch _resolveSelector(ListFieldOf<M> fields, FieldPatch p, M probe) {
    final selector = p.selector as Object? Function(M);
    final want = selector(probe);

    final matches = <FieldOf<M>>[
      for (final f in fields)
        if (f.hasGetter && identical(f.readErased(probe), want)) f,
    ];

    if (matches.length == 1) {
      return FieldPatch(matches.single, p.value);
    }

    if (matches.isEmpty) {
      throw StateError(
        '$S.set: selector did not match any field on $M. The selector '
        'must read an existing field (one declared with `getter:`).',
      );
    }

    // Still ambiguous after seeding: `want`'s type has a finite domain
    // (bool, or an enum with a known value list) too small to have
    // separated every field during probe construction. Resolve exactly
    // via isolating probes instead of guessing, if we can prove a value
    // distinct from `want` exists for this type.
    //
    // The domain is looked up across *every* matched field, not just the
    // first — the fields colliding on `want` may have been declared
    // through a mix of built-in `enumOr*` combinators (known domain) and
    // custom parsers (unknown domain); as long as at least one carries a
    // known domain, that's enough to prove `alt` exists and disambiguate.
    // Trusting only `matches.first` would spuriously fail to resolve
    // whenever the *other* matches are the ones with a known domain.
    List<Enum>? domain;
    for (final m in matches) {
      final d = enumDomainOfField(m);
      if (d != null) {
        domain = d;
        break;
      }
    }
    final alt = alternateValueFor(want, 0, enumDomain: domain);
    if (!identical(alt, want)) {
      final resolved = _disambiguateFinite(
        fields,
        matches,
        want,
        alt,
        selector,
      );
      if (resolved != null) return FieldPatch(resolved, p.value);
    }

    final described = matches.map((f) => '"${f.jsonKey}"').join(', ');
    throw StateError(
      '$S.set: selector matched ${matches.length} fields on $M '
      '($described) — could not prove them apart. This happens only for '
      'enum fields declared with a custom parser (bypassing the built-in '
      'enumOr*/… combinators), or fields of a type this library has no '
      'probe for. Use the resolved-field form instead: '
      '`\$.fieldName.set(value)`.',
    );
  }

  /// Exactly (not heuristically) resolves a collision between several
  /// same-typed [candidates], given a proven-different [alt] value.
  ///
  /// For each candidate in turn, builds a fresh "isolating" probe where
  /// *only that candidate* holds [want] and every other candidate holds
  /// [alt]. A [selector] that genuinely reads one specific field — the
  /// whole contract of [Schema.set] — returns [want] on exactly one such
  /// probe: the one where its field was the one set to [want]. If more
  /// than one probe matches, or none does, backs off to `null` so the
  /// caller reports a clear ambiguity error instead of guessing.
  FieldOf<M>? _disambiguateFinite(
    ListFieldOf<M> fields,
    List<FieldOf<M>> candidates,
    Object? want,
    Object? alt,
    Object? Function(M) selector,
  ) {
    final current = _instance.props;
    FieldOf<M>? found;

    for (final target in candidates) {
      final args = <Object?>[
        for (var i = 0; i < fields.length; i++)
          if (!fields[i].hasGetter)
            current[i]
          else if (identical(fields[i], target))
            want
          else if (candidates.contains(fields[i]))
            alt
          else
            current[i],
      ];

      final M variant;
      try {
        variant = _instantiate(args, context: '<probe:finite>');
      } catch (_) {
        return null;
      }

      if (identical(selector(variant), want)) {
        if (found != null) return null; // still ambiguous
        found = target;
      }
    }

    return found;
  }

  // ===========================================================================
  // Construction paths
  // ===========================================================================

  M _callDirect(ListFieldOf<M> fields, List<FieldPatch> patches) {
    // Field identity decides which slot a patch fills — `patch.field` is
    // always the exact object one of `fields` already is (that's what
    // FieldPatchX.set captures), so a plain identity-keyed Map is enough:
    // Field doesn't override ==/hashCode, so this Map is identity-based
    // for free — no path-string building, and no way for two different
    // fields to collide.
    final byField = <FieldOf<M>, Object?>{
      for (final p in patches) p.field as FieldOf<M>: p.value,
    };

    final args = <Object?>[
      for (final f in fields)
        byField.containsKey(f) ? byField[f] : f.readErased(_instance),
    ];

    return _instantiate(
      args,
      context: '<constructor>',
      message:
          'copyWith (direct-construction path): positional constructor '
          "call failed. Make sure Schema.all's order matches the "
          "constructor's parameter order.",
    );
  }

  M _callViaJson(ListFieldOf<M> fields, List<FieldPatch> patches) {
    // Start with the current JSON state of the model.
    final json = Json.from(_instance.toJson());

    for (final patch in patches) {
      final field = patch.field as Field<M, Object?>;
      final serialized = SerializableHelpers.serializeValue(patch.value);

      // Write to the field's full path (nesting + jsonKey), not a flat
      // json[field.jsonKey] — handles fields declared via at(...).
      SerializableHelpers.writeDeep(json, [
        ...field.nesting,
        field.jsonKey,
      ], serialized);
    }

    // Full deserialization — all parsers run again, for every field.
    return SerializableHelpers.fromJson<M>(json, fields, _type._factory);
  }

  /// Shared [Function.apply] wrapper — used by [_buildProbe],
  /// [_disambiguateFinite], and [_callDirect]. Wraps any failure in a
  /// [SerializationError] with consistent context, rather than letting a
  /// raw `TypeError`/`NoSuchMethodError` escape from three call sites with
  /// three different shapes.
  M _instantiate(
    List<Object?> args, {
    required String context,
    String? message,
  }) {
    try {
      return Function.apply(_type._factory, args) as M;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SerializationError(
          modelType: M,
          jsonKey: context,
          path: M.toString(),
          cause: e,
          message:
              message ??
              '$S.set: failed to build a probe instance of $M while '
                  'resolving a `(m) => m.field` selector.',
        ),
        st,
      );
    }
  }
}
