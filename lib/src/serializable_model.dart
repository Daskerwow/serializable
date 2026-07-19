// =============================================================================
// serializable_model.dart
//
// Serialization core: model interface, the Serializable/PropsFromGetters
// mixins, and the SerializableHelpers engine.
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
//
//   6. `fromJson`'s per-field work (read → parse → null-check) moved to
//      `Field.readFrom` (field.dart) — `fromJson` now just calls it once
//      per field and passes the results to `Function.apply`, instead of
//      keeping its own copy of that logic. This means the exact same
//      read-and-validate step is also available *without* `Function.apply`,
//      by calling `someField.readFrom(json)` directly as a constructor
//      argument — see the README's "Fast, Function.apply-free
//      deserialization" section. Nothing observable changes for existing
//      `fromJson`/`ModelType.call` callers: same errors, same
//      modelType/jsonKey/path/rawValue on every one of them.
//
//   7. **`Serializable<M>` no longer provides `props`.** It used to
//      contain both `toJson()` and a getter-derived default `props` —
//      correct in isolation, but a *latent bug* the moment `Serializable`
//      was mixed onto a class hierarchy that already had a *concrete*
//      `props` somewhere below it (e.g. `class Base extends Equatable {
//      Props get props => [...]; } class Model extends Base with
//      Serializable<Model> {}`). Dart's mixin linearization puts a mixin
//      *after* the class(es) it's applied on top of, so `Serializable`'s
//      `props` silently *shadowed* `Base`'s — every `Model` would use the
//      getter-derived default (throwing `StateError`, since none of its
//      fields have a `getter`) instead of the perfectly good `props`
//      `Base` already provided, with no compile error to catch it.
//      `props` is now the sole responsibility of [PropsFromGetters] — an
//      **opt-in** second mixin for models that specifically want the
//      getter-derived default. `Serializable` alone only ever provides
//      `toJson()`, and never competes with a `props` implementation
//      inherited from anywhere else. `ListFieldOf` also dropped its type
//      parameter as part of this pass — see its doc comment in
//      types/types.dart for why the list itself never actually needed to
//      pin down one exact model type for every field in it.
// =============================================================================

import 'package:equatable/equatable.dart';

import 'errors.dart';
import 'types/recording.dart';
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
/// plain `Equatable` usage, or inherited from a plain-`Equatable` base
/// class — see the README's "Fast, Function.apply-free deserialization"
/// section) or derived automatically from `getter:` closures on each
/// field via the separate, opt-in [PropsFromGetters] mixin.
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
  /// All field descriptors, in constructor-parameter order — required
  /// only by [SerializableHelpers.fromJson]'s `Function.apply` path.
  /// Calling [Field.readFrom] directly, field by field, has no order
  /// requirement of its own, but `fields` is still needed for `toJson()`
  /// either way.
  ///
  /// Declare as `static final` and expose via a getter:
  /// ```dart
  /// static final _fields = <Field<Object?, Object?>>[...];
  /// @override
  /// ListFieldOf get fields => _fields;
  /// ```
  ListFieldOf get fields;

  /// Serializes the instance into a JSON-compatible Map.
  Json toJson();

  /// This model's current field values, in the same order as [fields].
  ///
  /// This is the plain `Equatable` `props` list — write it the same way
  /// you would for any `Equatable` class, referencing the model's own
  /// properties directly (e.g. `[id, name, address]`) — no JSON keys or
  /// strings of any kind belong here, only the values themselves.
  /// [Serializable] builds `toJson()` from it; `Equatable` builds
  /// `==`/`hashCode` from it.
  Props get props;
}

// =============================================================================
// Serializable — mixin providing toJson()
// =============================================================================

/// Provides an automatic implementation of [toJson], built from [fields]
/// and [props].
///
/// This mixin does **not** provide `props` — that's `Equatable`'s own
/// abstract member, and every model still has to satisfy it somehow, same
/// as with plain `Equatable`:
///
///   1. **Declare it yourself** — exactly as in plain `Equatable` usage:
///      `Props get props => [id, name, address];`. Always works.
///   2. **Inherit it** from a plain, non-`Serializable` base class that
///      already declares it — see the README's "Fast, Function.apply-free
///      deserialization" section for why splitting a model into a plain
///      domain class plus a thin `Serializable` subclass is a good fit
///      for this.
///   3. **Derive it from `getter:`s** — mix in [PropsFromGetters] as
///      well: `with Serializable<M>, PropsFromGetters<M>`. Give every
///      field in the [Schema] a `getter:` (`field<int>('user_id', getter:
///      (m) => m.id)`) and skip declaring `props` entirely.
///
/// Options 1 and 2 need nothing from this mixin beyond `toJson()` itself.
/// Option 3 needs [PropsFromGetters] *in addition to* this mixin — see its
/// own doc comment for why that's a separate mixin rather than bundled in
/// here.
///
/// ### Full Model Example (recommended style: Schema + ModelType)
///
/// See the package README for the complete picture; the shape of a single
/// model, using option 3 above, is:
/// ```dart
/// class User extends Equatable
///     with Serializable<User>, PropsFromGetters<User> {
///   final int id;
///   final String name;
///   final String? address;
///
///   const User(this.id, this.name, this.address);
///
///   static final $ = ModelType<User>(User.new, UserSchema());
///
///   @override
///   ListFieldOf get fields => $.schema.all;
///
///   // No `props` override needed here — every field below has a
///   // `getter:`, so PropsFromGetters derives it for you.
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
///   late final all = [id, name, address];
/// }
/// ```
mixin Serializable<M extends SerializableModelI<M>> on Equatable
    implements SerializableModelI<M> {
  @override
  Json toJson() => SerializableHelpers._buildJson(fields, props);
}

// =============================================================================
// PropsFromGetters — opt-in mixin deriving props from Field getters
// =============================================================================

/// Opt-in `props` default, built from each field's `getter` (see
/// `Schema.field(..., getter: ...)` / `Schema.field(..., getter: ...)`).
///
/// Mix this in *alongside* [Serializable] — `with Serializable<M>,
/// PropsFromGetters<M>` — on a model where *every* field has a `getter:`,
/// to skip declaring `props` by hand entirely.
///
/// Deliberately a **separate** mixin from [Serializable], not bundled
/// into it: a mixin's members take precedence over whatever the class(es)
/// it's applied on top of already declared (Dart's usual linearization
/// rules), so a `props` default living inside [Serializable] would
/// silently *shadow* a perfectly good `props` inherited from a plain,
/// non-`Serializable` base class — exactly the bug described in this
/// file's header (fixed-issue #7). Requiring an explicit, separate
/// `PropsFromGetters<M>` opt-in means a model only gets the getter-derived
/// default when it actually asks for it.
///
/// Throws [StateError] — clearly, and only when actually invoked — if any
/// field in [SerializableModelI.fields] has no `getter`, rather than
/// silently producing a `props` list with holes in it.
mixin PropsFromGetters<M extends SerializableModelI<M>>
    implements SerializableModelI<M> {
  @override
  Props get props => SerializableHelpers._propsFromGetters<M>(
    fields,
    this as M,
  );
}

// =============================================================================
// RecordedFields — opt-in mixin capturing fields from field(...) calls
// =============================================================================

/// Opt-in `fields` default, captured automatically from the `field(...)`
/// calls made while this instance was constructed — no separate `fields`
/// list, `Schema`, or `ModelType` needed anywhere.
///
/// Mix this in *alongside* [Serializable] — `with Serializable<M>,
/// RecordedFields<M>` — on a model whose real constructor is only ever
/// invoked from inside [recordFields] (typically from `fromJson`):
/// ```dart
/// class UserModel extends User with Serializable<UserModel>, RecordedFields<UserModel> {
///   // Private — the only way in is recordFields(...), below. Nothing
///   // else can accidentally construct a UserModel with no fields
///   // recorded for it.
///   UserModel._({required super.id, required super.name, super.email});
///
///   factory UserModel.fromJson(Json json) => recordFields(() => UserModel._(
///     id: field<int>('user_id').readFrom(json),
///     name: field<String>('full_name').readFrom(json),
///     email: field<String?>('email_address').readFrom(json),
///   ));
/// }
/// ```
/// Every `field(...)` call above — there's exactly one for each field,
/// the same one `.readFrom(json)` is called on — is what `fields` is
/// built from; nothing about it is declared a second time anywhere.
///
/// ### Why the real constructor needs to be private
///
/// [captureRecordedFields] — what this mixin calls — has to run *eagerly*,
/// as a plain field initializer, not `late`: `late` only runs on first
/// access, and `fields`/`toJson()` are almost always accessed well after
/// construction finishes, by which point [recordFields]'s frame is long
/// gone. Eager capture is what makes this correct instead of merely
/// working by coincidence — but it also means it runs for *every*
/// construction, including one that didn't go through [recordFields] at
/// all, e.g. `UserModel(id: 1, name: 'Ada')` called directly. There's no
/// frame to capture in that case, and [captureRecordedFields] throws a
/// clear [StateError] rather than silently producing an empty or stale
/// `fields`.
///
/// A private constructor turns that mistake into a compile error instead
/// of a runtime one — nothing outside the file declaring `UserModel` can
/// call `UserModel._(...)` directly, so the only path in really is
/// `fromJson` (or any other factory that also wraps its call in
/// [recordFields]). If a model genuinely needs to be built from values
/// already in hand rather than from JSON — not from a factory at all —
/// don't use [RecordedFields] for it; declare `fields` explicitly
/// instead (see the README's "Fast, `Function.apply`-free
/// deserialization" section for that style, and for the full reasoning
/// behind this one).
mixin RecordedFields<M extends SerializableModelI<M>>
    implements SerializableModelI<M> {
  @override
  final ListFieldOf fields = captureRecordedFields(M);
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
  /// 1. For each field from [fields], [Field.readFrom] reads the value by
  ///    path (`[nesting..., jsonKey]`, supporting nested keys via `at()`),
  ///    parses it, and — if the result is `null` and the field isn't
  ///    [Field.nullable] — throws [RequiredFieldError]. See its doc comment
  ///    in field.dart for the full per-field contract; this method no
  ///    longer duplicates it.
  /// 2. Passes all values as POSITIONAL arguments to [factory] via
  ///    [Function.apply].
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
  ///
  /// Prefer this when you'd rather not hand-write `fromJson` field by
  /// field — it works for any model, with zero extra code beyond the
  /// `Schema`. On a genuine hot path, calling [Field.readFrom] directly,
  /// once per field, as a literal argument to the model's own constructor
  /// avoids `Function.apply` (and the dynamic-call overhead that comes with
  /// it) entirely — see the README's "Fast, Function.apply-free
  /// deserialization" section.
  static R fromJson<R extends SerializableModelI<R>>(
    Json json,
    ListFieldOf fields,
    Function factory,
  ) {
    // Every field knows how to read and validate itself — see
    // Field.readFrom. All that's left here is collecting the results, in
    // order, and handing them to the constructor.
    final args = [for (final f in fields) f.readFrom(json)];

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
  static String _constructorFailureMessage(
    ListFieldOf fields,
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
  // props (internal) — backs PropsFromGetters
  // ===========================================================================

  /// Builds a `props` list by calling each field's `getter` against
  /// [instance], in [fields] order.
  static Props _propsFromGetters<M>(ListFieldOf fields, M instance) {
    final result = <Object?>[];
    for (final f in fields) {
      if (!f.hasGetter) {
        throw StateError(
          'PropsFromGetters: field "${f.jsonKey}" on $M has no getter. '
          'Either pass getter: (m) => m.yourProperty to every field in the '
          'Schema, or drop PropsFromGetters and override `props` manually '
          'on $M instead.',
        );
      }
      // `f.readErased` expects the field's own `M`; through the
      // `Object?`-erased `ListFieldOf` reference, that's checked at
      // runtime (via the field's *reified* generic parameters) rather
      // than statically — sound as long as every field in `fields`
      // genuinely belongs to this model, which is the same invariant
      // `fields`/`props` already had to uphold before `ListFieldOf`
      // dropped its own type parameter (see types/types.dart).
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
  static Json _buildJson(ListFieldOf fields, Props props) {
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
  // Path helpers (write side — the read side, readJsonPath, lives in
  // types/json_path.dart and is shared with Field.readFrom)
  // ===========================================================================

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
