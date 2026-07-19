# Changelog

## 6.1.0 — `RecordedFields`: `fields` captured from `fromJson`, not declared separately

The one piece `6.0.0`'s Schema-free `field()` still needed a second,
explicit declaration for — `fields`, for `toJson()` — no longer does,
for models that opt in.

### Added

- `RecordedFields<M extends SerializableModelI<M>>` — opt-in mixin
  providing `fields`, captured automatically from the `field(...)` calls
  made while an instance is constructed. Combine with `Serializable<M>`:
  `with Serializable<M>, RecordedFields<M>`. The model's real constructor
  must be built only through `recordFields(() => ...)` (typically wrapped
  around the body of `fromJson`) — see the README's rewritten "Fast,
  `Function.apply`-free deserialization" section for the full pattern,
  the reasoning behind the eager-capture requirement, and why that means
  the real constructor should be private.
- `recordFields<M>(M Function() build)` — runs `build`, capturing every
  `field(...)` call made while evaluating it into a fresh frame that
  `RecordedFields` then reads. Correctly nests for models embedded inside
  other recorded models (e.g. via `modelOf`).
- `registerField`, `captureRecordedFields` — the two smaller pieces
  `field(...)`/`RecordedFields` are each built from; not usually called
  directly, but exported for anyone building their own field-declaration
  helper on top of this package.

### Fixed (documentation)

- The README's `field()`-based examples from `6.0.0` still declared a
  separate `static final _fields = [...]` list, duplicating the exact
  `field(...)` calls already made in `fromJson`. That style is kept —
  it's the right choice for a model that wants to keep a public raw
  constructor — but `RecordedFields` (above) is now the lead example for
  models that don't need one.

### Compatibility

Fully additive: nothing about `Field`, `Schema`, `ModelType`,
`Serializable`, `PropsFromGetters`, or existing `field(...)` call sites
changed. `registerField` is called by `buildField` for every `Field` it
ever builds, but is a no-op — zero cost, zero behavior change — unless
`recordFields` is actually active, which no existing code triggers.

## 6.0.0 — Schema-free deserialization: a model-agnostic `field()`, and a real `Serializable`/`props` bug fix

Two things prompted this release, together: making `Field.readFrom`
usable with **zero** per-model setup (no `Schema`, no per-class helper
method), and a genuine correctness bug that surfaced while designing the
model split that makes that possible.

### The bug

`Serializable<M>` used to provide *both* `toJson()` and a getter-derived
default `props`. That's fine in isolation, but unsound the moment
`Serializable` is mixed onto a class hierarchy that already has a
*concrete* `props` implementation somewhere below it — e.g. a plain
domain class `User` with a hand-written `props`, and a thin
`UserModel extends User with Serializable<UserModel>` on top, adding JSON
support. Dart's mixin linearization puts `Serializable` *after* `User` in
`UserModel`'s effective hierarchy, so `Serializable`'s `props` **silently
shadowed** `User`'s — every `UserModel` used the getter-derived default
instead of `User`'s real `props`, throwing `StateError` the moment
anything touched `.props` (`toJson()`, `==`, `hashCode`), since none of
its fields have a `getter`. No compile error, no warning — just a runtime
throw the first time it mattered.

### The fix

`props` is no longer `Serializable`'s to provide. It's split into two
mixins:

- `Serializable<M>` — `toJson()` only, same as always.
- `PropsFromGetters<M>` — the getter-derived `props` default, now opt-in:
  `with Serializable<M>, PropsFromGetters<M>`.

A model that doesn't explicitly ask for `PropsFromGetters` gets exactly
what plain `Equatable` usage always required: declare `props` yourself,
or inherit it from somewhere that does. `Serializable` never competes
with either option again.

### What this unlocked

With `props` handled by ordinary inheritance, `fields` (needed for
`toJson()` regardless of how `fromJson` is implemented) became the last
thing standing between a model and zero `Schema`/`ModelType` boilerplate.
A new top-level `field<R>(jsonKey)` — no `M` to supply, unlike
`Schema.field`/`'key'.field<M, R>()` — makes that genuinely `Schema`-free:

```dart
class User extends Equatable {
  final int id;
  final String name;
  const User({required this.id, required this.name});
  @override
  List<Object?> get props => [id, name];
}

class UserModel extends User with Serializable<UserModel> {
  const UserModel({required super.id, required super.name});

  static final _fields = <Field<Object?, Object?>>[
    field<int>('user_id'),
    field<String>('full_name'),
  ];

  @override
  ListFieldOf get fields => _fields;

  factory UserModel.fromJson(Json json) => UserModel(
    id: field<int>('user_id').readFrom(json),
    name: field<String>('full_name').readFrom(json),
  );
}
```

See the README's rewritten "Fast, `Function.apply`-free deserialization"
section for the full pattern, including an honest answer to "why doesn't
`field(...)` just collect `fields` for you too?" (short version: it would
reintroduce the exact bug `4.0.0` already fixed once, for instances built
without ever calling `fromJson`).

### Breaking

- **`Serializable<M>` no longer provides `props`.** Any model relying on
  its old getter-derived default must add `PropsFromGetters<M>`:
  `with Serializable<M>` → `with Serializable<M>, PropsFromGetters<M>`.
  Models with an explicit, hand-written `props` override are unaffected.
- **`ListFieldOf<T>` is now `ListFieldOf`, with no type parameter.**
  Nothing that consumes a `ListFieldOf` — `SerializableHelpers.fromJson`,
  `Serializable.toJson()` — ever actually needed every element to share
  one exact model type; only individual `Field`s needed their own `M`
  (for their `getter`'s parameter type, and for the `modelType` on any
  error they throw), and they keep it regardless of how the list holding
  them is typed. Update `ListFieldOf<User>` → `ListFieldOf` at every
  `fields`/`Schema.all` override.
- `SerializableModelI<M>.fields` and `Schema<M>.all` changed accordingly:
  `ListFieldOf<M> get fields;` → `ListFieldOf get fields;` (same for
  `all`).

### Added

- Top-level `field<R>(String jsonKey, {parser, serializer, nullable})` —
  builds a `Field<Object?, R>`, usable anywhere with no `Schema` and no
  model type in scope, including directly inside a hand-written `factory
  Model.fromJson(...)`. The only cost versus a `Schema`/`'key'.field<M,
  R>()`-declared field: errors it throws report `modelType: Object?`
  instead of the real model name (everything else — `jsonKey`, `path`,
  `rawValue` — is identical). Both kinds of field can sit in the same
  `fields`/`ListFieldOf` list, mixed freely.
- `PropsFromGetters<M extends SerializableModelI<M>>` — the getter-derived
  `props` default `Serializable<M>` used to provide, now a separate,
  explicit opt-in mixin. See "The fix" above for why.

## 5.1.0 — `Field.readFrom`: per-field deserialization without `Function.apply`

Every `Field<M, R>` now exposes `R readFrom(Json json)` — reads, parses,
and null-checks exactly one field, statically typed, with none of
`Function.apply`'s dynamic-call overhead or its loss of compile-time
argument-type checking. `SerializableHelpers.fromJson` (and therefore
`ModelType.call`) is unchanged in observable behavior — same errors, same
`modelType`/`jsonKey`/`path`/`rawValue` on every one of them — but is now
*implemented in terms of* `readFrom`, called once per field, instead of
duplicating that logic inline.

This is additive and fully backward compatible: nothing about `ModelType`,
`Schema`, or `toJson()` changed, and no existing model needs to change.
`ModelType.call`'s `Function.apply`-based path remains available and is
still the right default when you'd rather not write `fromJson` by hand for
every model. `readFrom` is for the hand-written, no-`Function.apply`
alternative — see the README's new "Fast, `Function.apply`-free
deserialization" section, including how it composes with Dart's
(experimental, as of this writing) primary constructors.

### Added

- `Field<M, R>.readFrom(Json json)` — reads this field's raw value out of
  `json` (honoring `nesting`/`at(...)`), parses it via `parser`, and
  applies the same required-field check `fromJson` already did, throwing
  `RequiredFieldError`/`TypeConversionError`/`SerializationError` with the
  same context as before. Meant to be called once per field, directly as a
  positional argument to a hand-written factory constructor:
  ```dart
  factory User.fromJson(Json json) => User(
    id: field<int>('user_id').readFrom(json),
    name: field<String>('full_name').readFrom(json),
  );
  ```
- `readJsonPath(Json json, List<String> nesting, String key)` — the path
  walk `readFrom` and `SerializableHelpers.fromJson` both now share,
  extracted out of `serializable_model.dart`'s former private `_readPath`
  into its own file (`types/json_path.dart`) so `field.dart` doesn't have
  to import `serializable_model.dart` (or duplicate the walk) to use it.
  Exported from the package root alongside `at`.

### Changed

- `SerializableHelpers.fromJson`'s per-field loop (read → parse → null
  check → collect into `args`) is now just `[for (final f in fields)
  f.readFrom(json)]` — that loop body moved to `Field.readFrom` itself,
  so there's exactly one implementation of "read and validate one field"
  for both the `Function.apply` path and the direct-call path to share,
  instead of two copies that could silently drift apart.

### Fixed

- **The README's `readFrom` examples kept a `Schema` subclass (and, at
  first, a `ModelType` too) around even though neither earns its keep
  once you're calling `readFrom` yourself, field by field, by name.**
  `Schema`/`ModelType` exist to give the `Function.apply` path a field
  list to loop over blind, and to support `getter:`-derived `props`;
  neither applies here. Replaced with the pattern the README now leads
  with: a one-line, per-class, curried `static Field<M, R> field<R>(String
  jsonKey, {...})` helper, called directly — `field<int>('user_id')
  .readFrom(json)` — with `fields` built from a `static final` list of
  the same calls. Also added a "Why doesn't `field(...)` just collect
  `fields`/`props` for you?" section explaining, concretely — by pointing
  at this file's own `4.0.0` entry — why that last step can't be
  automated away without reintroducing the exact bug `4.0.0` fixed (a
  model built by calling its constructor directly, bypassing `fromJson`
  entirely, would get an empty/stale `fields`/`props` instead of a
  `StateError` or correct output).
- **`Schema.all` (and any hand-rolled `fields` getter reading it) was
  shown as `get all => [...]`** throughout the README — a plain getter,
  rebuilding the `List` on every access, including every `toJson()` call.
  Every example now uses either `late final all = [...]` (on a `Schema`)
  or a `static final` list read through a `get fields => _fields;`
  one-liner (on a model using the flat pattern above), both computed
  once. Purely a documentation fix — nothing in the library needed to
  change.

## 5.0.0 — Remove `copyWith`, `Schema.set`, and `ModelBinder`; fix the `getter:` regression

`copyWith` is no longer part of this library's public API. json_forge maps
JSON ⇄ model and nothing else; a model's `copyWith` is domain-layer,
value-object logic, and it's a handful of lines to write by hand once you
already have `toJson`/`fromJson`/`props` for free — see the README's
"Writing your own copyWith" section for a worked example.

### Breaking

- Removed `Schema.set`, `ModelBinder`, `FieldsBuilder<S>`, `FieldPatch`,
  and the `undefined` sentinel entirely. There is no library-provided
  `copyWith` path anymore — `ModelType` only ever powers `fromJson`.
- `ModelType<M, S extends Schema<M>>` is now `ModelType<M extends
  SerializableModelI<M>>` — the second type parameter is gone.
  `ModelType.schema` was always typed as the erased `Schema<M>`, never the
  concrete `S` — nothing except `bind`/`ModelBinder` (both removed above)
  ever actually needed `S`. Update construction call sites:
  ```dart
  // before
  static final $ = ModelType<User, UserSchema>(User.new, UserSchema());
  // after
  static final $ = ModelType<User>(User.new, UserSchema());
  ```

### Fixed

- **`FieldStringX.field` (the top-level `String.field()` extension) still
  had `getter` as a required positional parameter**, even though the
  `4.1.0` entry below already claimed this exact regression was fixed,
  and every usage example in that same file's own header comment
  (`'name'.field<User, String>()`, no arguments at all) assumed it was
  optional. It wasn't: Dart doesn't allow mixing an optional-positional
  parameter with named ones in a single signature, so "optional *and*
  positional, alongside `parser:`/`serializer:`/`nullable:`" was never
  actually reachable here — the 4.1.0 fix could only have made it
  optional by dropping it from the parameter list, and it didn't. `getter`
  is now a named parameter, `getter: (m) => m.x`, matching `Schema.field`
  in `model_type.dart`, which had this right all along. Update call sites
  that passed a getter positionally (`'sensor_uid'.field((m) => m.uid)`)
  to the named form (`'sensor_uid'.field(getter: (m) => m.uid)`).
- The doc comments on `ModelType` (`model_type.dart`) and `Serializable`
  (`serializable_model.dart`) demonstrated construction as
  `ModelType<Sensor, SensorSchema>(...)` / `ModelType<User,
  UserSchema>(...)` — the two-type-parameter form, which hasn't compiled
  since `S` was dropped from `ModelType`. Both now show the correct
  `ModelType<Sensor>(...)` / `ModelType<User>(...)`.
- **README.md's main example separated `Schema.all` list entries with
  `;` instead of `,`** (`'user_id'.field(...); 'full_name'.field(...);`)
  — not valid Dart list-literal syntax, so the example didn't compile.
- `modelOf`/`modelOrNull`/`jsonObjectOrNull` copied the incoming `Map` via
  `Map.from` before handing it to a nested model's `fromJson` (or
  returning it as a `Json`) — the same needless O(map size) copy that
  `_readPath` was already fixed, in `4.1.0` below, to avoid, for a value
  that's only ever read from afterward, never mutated. Replaced with
  `Map.cast`, an O(1) typed view, matching `_readPath`'s reasoning.
- **This file's own version ordering was wrong.** The entry now numbered
  `4.1.0` below was previously labeled `0.3.0` and listed *above* — i.e.
  more recent than — `4.0.0`, `3.0.0`, `2.0.0`, and `1.0.0`, despite
  `0.3.0 < 4.0.0` and despite that entry's own text describing itself as
  building on `4.0.0` ("the counterpart to 4.0.0's requirement").
  Renumbered to `4.1.0` and left in its correct, chronological position
  below.
- README.md documented `copyWith`, `ModelBinder`, `Schema.set`,
  `FieldsBuilder<S>`, and the `undefined` sentinel throughout its
  examples, core-concepts table, and API reference — none of which have
  existed since this version (or, per the entry below, arguably ever
  correctly). Rewritten to match the library's actual public surface, as
  already correctly described by `json_forge.dart`'s own library doc
  comment and `model_type.dart`'s header comment.

## 4.1.0 — Optional getter-derived `props`, and three correctness fixes

> **Note:** The `copyWith`-related additions described in this entry —
> `Schema.set`, the allocation-free `copyWith` path unlocked by full
> `getter:` coverage, `field_probe.dart`, and the `enumOr*` `Expando`
> tagging that supported selector resolution — were all removed in
> `5.0.0` above. The `getter:` parameter itself, and the `props` it
> derives, are unaffected and still current.

Adds back an *optional* way to satisfy `props` without writing it by hand
— the counterpart to 4.0.0's requirement that every model declare it
explicitly. Give every field in a `Schema` a `getter:` and skip
overriding `props` entirely; `Serializable`'s default implementation
builds it from `fields` + those getters. Models that prefer 4.0.0's
explicit style are unaffected — nothing about this is required.

```dart
final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid', getter: (m) => m.uid);
  late final value = field<double>('last_value', getter: (m) => m.value);

  @override
  ListFieldOf<Sensor> get all => [uid, value];
}
// Sensor no longer needs to override `props` at all.
```

The same `getter:` also unlocked an allocation-free `copyWith` path: when
*every* field in a schema had one, `ModelBinder` built the updated
instance directly from current getter values + patches, instead of
round-tripping through `toJson()`/`fromJson()`. It also enabled
`Schema.set((m) => m.field, value)` — a selector-based patch, resolved
against a synthetic probe instance rather than a `Field` reference, so
`$.set((m) => m.title, 'x')` worked even for models assembled with inline
lambdas. New internal module: `field_probe.dart` (probe seeding,
finite-domain disambiguation for `bool`/`Enum` collisions).

### Added

- `getter:` parameter on `Schema.field` and `String.field()`.
- ~~`Schema.set(selector, value)` — deferred, selector-resolved patches,
  alongside the existing `$.field.set(value)` resolved form.~~ Removed in
  `5.0.0`.
- ~~`enumOrNull`/`enumOrDefault`/`enumOrFirst`/`enumOrLast`/`enumOrThrow`
  now tag the parser they return with the `values` list it was built
  from (via an `Expando`), so `ModelBinder` can recover a field's enum
  domain purely from the parser it already has.~~ Removed in `5.0.0`
  along with `ModelBinder` itself.

### Fixed

- **`String.field()`'s `getter` was a required positional parameter**,
  contradicting this same file's own doc comments (`'name'.field<User,
  String>()` — no positional argument at all) and 3.0.0's changelog entry
  below, which describes exactly this as a fixed bug once already. It
  regressed back to required when `getter:` was reintroduced. Believed
  fixed here — **it wasn't**; see `5.0.0` above for why, and for the fix
  that actually stuck.
- **`ModelBinder._resolveSelector` only checked the first colliding
  field's enum domain**, not every colliding field's. Two same-valued
  enum fields could fail to resolve via `Schema.set` even when a *second*
  colliding field (not the first) was declared through a built-in
  `enumOr*` combinator — contradicting this method's own documented
  contract, which only promises failure when *no* colliding field has a
  known domain. Domain lookup now scans every match.
  > **Superseded in 5.0.0** — `Schema.set` and `ModelBinder` are gone.
- **`SerializableHelpers._readPath` copied an entire nested `Map` via
  `Map.from` at every level of `at(...)` nesting, for every field
  independently.** Six fields sharing one `at('stats', ...)` prefix
  copied that sub-map six times per parse. Replaced with `Map.cast` — an
  O(1) typed view instead of an O(map size) copy — matching how
  `_writeDeep` already handled the write side (a plain `as` cast, no
  copy).
- **Constructor-call failures inside `Function.apply` gave no indication
  of which field's value was at fault** — a bare "positional constructor
  call failed" message wrapping an opaque `TypeError`. This matters more
  than it used to: a `getter`/`parser` type mismatch on a field declared
  inline inside a `List<Field<M, Object?>>` literal (the common
  `'key'.field((m) => m.x, parser: ...)` style used directly in a
  `Schema.all` list) does not fail to compile — Dart infers the field's
  type parameter down to the list's own `Object?` element type instead of
  flagging the disagreement — so it only ever surfaces here. The error
  message now lists every argument as `jsonKey: runtimeType = value`.
  Applies to `fromJson` and to all three `ModelBinder` construction paths.
  > `ModelBinder`'s two construction paths are gone as of `5.0.0`; the
  > diagnostic still applies to `fromJson`.
- **`AccessLevel`-keyed `Map` fields (`Map<Enum, V>`) needed an explicit
  `.name`-based `serializer:`** that the test suite's `Terminal` fixture
  was missing (`example.dart`'s equivalent field already had it). Without
  it, `toJson()` keyed the map by `AccessLevel.write.toString()`
  (`"AccessLevel.write"`) instead of `.name` (`"write"`), and
  `enumOrFirst` silently substituted its fallback on the way back in
  instead of raising an error — so `copyWith()` quietly dropped or
  corrupted every token except the one matching the fallback, with
  nothing to signal it. Fixed the fixture and extended the `copyWith`
  test to cover a second key so this can't hide again.
- Removed the unused `collection` dependency from `pubspec.yaml`.

## 4.0.0 — `toJson()` built from `props`, not a per-instance cache

`Serializable` no longer auto-implements `props`. Every model must declare
it itself — the same plain `Equatable` list you'd write with or without
this package — and `Serializable.toJson()` is now built by zipping that
list with `fields`, index for index:

```dart
class Terminal extends Equatable with Serializable<Terminal> {
  // ...
  @override
  ListFieldOf<Terminal> get fields => $.schema.all;

  @override
  Props get props => [id, title, status, sensors, tokens]; // ← new requirement
}
```

### Why

`Field` previously cached each parsed value against the instance it was
parsed *for*, via an `Expando` (`Field.attach`, populated only by
`fromJson`), and `toJson()`/`props` read that cache back instead of
calling a getter. That cache was only ever populated by `fromJson` — so
for any model built by calling its own constructor directly (a perfectly
normal thing to do with a public, often `const`, constructor), every field
came back `null`:

- `toJson()` silently produced an all-`null` JSON object, no exception.
- `==`/`hashCode` (via `Equatable`, also reading the same cache) treated
  every such instance as equal to every other one, regardless of actual
  field values.
- Worse, a field with a custom `serializer` crashed outright —
  `serializer(null as R)` for a non-nullable `R` threw a raw
  `type 'Null' is not a subtype of type '...'` `TypeError`, surfacing deep
  inside `Field`'s type-erasure wrapper with no useful context. This is
  exactly what happens the moment such an instance's `copyWith` is called,
  since `copyWith` starts by calling `toJson()` on the current instance.

Fixing this without a per-field getter on `Field` (which would need both a
user-supplied closure *and* a contravariant type-erasure wrapper, the same
problem `serializer` already has) means the model has to supply its
current values some other way. `props` already exists for exactly this —
`Equatable` requires it from every subclass — so `toJson()` now reads from
it instead of from a cache. The result is simpler (the `Expando`, `attach`,
and `readErased` machinery is gone from `Field` entirely) and correct
unconditionally: `toJson()`/`==` now reflect real values for *any*
instance, not only ones built via `fromJson`/`copyWith`.

A `Map<String, Object?>` keyed by JSON key — looked up by key instead of
matched by position — was also tried, specifically to remove the
requirement that `props` and `fields` stay in the same *order*. It was
reverted: every entry would have needed its JSON key spelled out as a
string literal a second time (it's already on the matching `Field` in
`fields`), which is exactly the stringly-typed duplication `Schema`/`Field`
exist to eliminate in the first place — trading one footgun for a worse
one. `props` stays a plain, string-free list. What *did* survive from that
detour, and is checked in **every** build mode, including release, not
just debug: `fields` and `props` differing in length throws a
`StateError` immediately (previously nothing checked this at all), and so
does any single slot whose value is the wrong *type* for that slot's field
(`Field.acceptsValue`, `value is R`). The per-slot check was originally a
debug-only `assert`, then made unconditional too: a field *with* a custom
`serializer` already throws on a type mismatch in release builds (the
unsound `as R` inside `serializeErased`), but a field *without* one
doesn't — `_serialize`'s fallback case passes any unrecognized value
straight through — so release builds were silently writing wrong data for
exactly the fields that don't crash. Neither check catches two same-typed
fields swapped (nothing short of an actual getter can), but together they
catch everything else, immediately, instead of producing silently-wrong
JSON.

### Breaking

- `Serializable<M>` no longer provides a default `props` — implement it
  yourself, listing the same fields in the same order as `fields`/`all`
  and the constructor. This is one line per model; see the README and the
  `Serializable` doc comment for the full pattern.
- `Field.attach` and `Field.readErased` are removed. Nothing in this
  package called them except the now-deleted cache-population loop in
  `fromJson` and the now-deleted default `props` getter.
- Added `Field.path` (`nesting` joined with `jsonKey`, e.g. `'meta.count'`
  for a field declared via `at('meta', ...)` with jsonKey `'count'`) and
  `Field.acceptsValue` (`value is R`, used by the unconditional check
  above). `fromJson`'s error-path construction now uses `Field.path`
  instead of computing the same join inline in two places.

## 3.0.0 — `Schema` classes, replacing the Record requirement

`ModelType<M, S>` now took a **`Schema<M>` instance** instead of a bare
`List<Field<M, Object?>>`, with `S` constrained to `extends Schema<M>`. A
`Schema` is a small class you extend, declaring each field once as a
`late final` member via `field<R>(jsonKey, ...)`, with a required `all`
getter listing every field **in constructor-parameter order**:

```dart
final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');

  @override
  late final all = [uid, value];
}

static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());
late final copyWith = $.bind(this);
```

```dart
sensor.copyWith(($) => [$.value.set(99.9)]); // $.value — a real member access
```

> **Note:** `ModelType`'s second type parameter (`S`) described below was
> removed again in `5.0.0`, once `copyWith`/`bind` (the only members that
> ever needed it) were removed. `ModelType<M, S>` here is accurate history
> for this version, not the current signature.

### Why

2.0.0's Record schema solved the problem a Record is good at — a
compiler-checked `$.value` with no string lookup — but left every model
with **two** declarations to keep in sync: the Record `typedef` (the named
accessors) and the plain field list passed to `ModelType` (the
constructor-parameter order `fromJson` actually needs). `Schema<M>` is
both at once: its members are the named accessors, and its `all` getter
*is* the ordered field list. One declaration instead of two, with the same
guarantee a Record gave — a typo in `$.vlaue` is still a compile error,
not a runtime one.

### Breaking

- `ModelType<M>` is now `ModelType<M, S extends Schema<M>>` — the bare
  `List<Field<M, Object?>>` constructor argument is replaced by a
  `Schema<M>` instance.
- `ModelType.bind(instance, schema)` is now `ModelType.bind(instance)` —
  the schema is already known from `ModelType<M, S>`'s `S`, so it doesn't
  need to be passed again at the call site.
- Models that previously declared only a field list (no Record, no
  `copyWith`) now declare a minimal `Schema<M>` subclass overriding just
  `all` — see the README's "Minimal — no copyWith" section. One small
  wrapper class instead of a bare list literal; the `'jsonKey'.field(...)`
  calls inside it are unchanged.
- **`FieldStringX.field`'s `parser` is now a named, optional parameter**
  (`{R Function(Object?)? parser, ...}`), matching `Schema.field` and
  `buildField`. It used to be a required (if nullably-typed) positional
  parameter, which made `'name'.field()` — passing no parser at all, for
  smart-inferred primitives — fail to compile, contradicting the
  "smart inference, no parser needed" behavior this same file's own doc
  comments described.

### Fixed

- **An unsound `null as R` cast had crept back into the field-parsing
  path.** `Field.parser` had regressed to `R Function(Object?)` — the
  exact shape the 1.0.0 entry above describes replacing — so a
  missing/`null` value for a non-nullable `R` triggered a raw, unsound
  cast inside the parser closure instead of cleanly falling through to
  `fromJson`'s `RequiredFieldError` check. `Field.parser` is
  `Object? Function(Object?)` again; the parser closure returns `null`
  directly, with no cast.
- **`nullable` wasn't actually defaulting to `null is R`.** Despite the
  README and the 1.0.0 entry above both documenting that default,
  `buildField` (and `.field()`, and `Schema.field`) all hard-coded
  `nullable: false` unless the caller passed `nullable: true` explicitly —
  so a field typed `String?` was, in practice, still treated as required.
  The default is now actually computed: `nullable ?? (null is R)`.
- **`httpUriOrNull` accepted any absolute URI with a host**, including
  non-HTTP schemes (`ftp://`, `ws://`, ...), contradicting its name and
  documentation. It now also checks `scheme == 'http' || scheme == 'https'`.
- **`bigIntOrNull` didn't accept `double`**, only `int` — a JSON number
  like `42.0` (which decodes to `double`) fell through to `null` instead
  of becoming `BigInt.from(42)`, unlike every sibling parser in the file
  (`intOrNull`, `doubleOrNull`, `numOrNull`), which all match on `num`.
- `SerializableHelpers._writeDeep` could throw a raw, uninformative
  `TypeError` if a non-`Map` value already occupied an intermediate path
  segment (e.g. from a malformed patch). It now skips the write instead.
- Library directive renamed from `library serializable;` to
  `library json_forge;` to match the actual package name.
- Removed stale documentation (this file's own usage examples, and the
  README) describing a `getter` and `name:` parameter on `.field(...)`.
  Neither has been part of `Field`/`buildField`'s real signature for a
  while — a field's value is recovered via a parse-time cache
  (`Field.attach`), not a getter closure. See that doc comment for what
  this implies about constructing models directly vs. via
  `fromJson`/`copyWith`.

## 2.0.0 — Record-based schemas, replacing `FieldSet`

`FieldSet` (the abstract class, `operator []`, `byJsonKey`, and the
`name:`-for-lookup mechanism introduced in 1.0.0) is gone. In its place:
`ModelType<M>` now just takes a plain ordered `List<Field<M, Object?>>`, and
`ModelType.bind` takes a second argument — any schema you like, almost
always a plain Dart **Record** listing each field by name:

```dart
typedef SensorFields = (
  {Field<Sensor, String> uid, Field<Sensor, double> value}
);

static final SensorFields _fields = (
  uid: 'sensor_uid'.field<Sensor, String>((m) => m.uid),
  value: 'last_value'.field<Sensor, double>((m) => m.value, parser: doubleOrZero),
);

static final $ = ModelType<Sensor>(Sensor.new, [_fields.uid, _fields.value]);

late final copyWith = $.bind(this, _fields);
```

```dart
sensor.copyWith(($) => [$.value.set(99.9)]); // $.value — native Record access
```

### Why

`FieldSet.operator []` (1.0.0) replaced the wire JSON key with a
Dart-facing `name:` for `copyWith` lookups, but it was still a runtime
`String` lookup underneath — a typo in `$['title']` was a runtime
`ArgumentError`, not a compile error. There's no codegen-free way to turn a
getter closure into a named getter on some other object (closures don't
expose what property they read, and the one thing that could inspect that —
`dart:mirrors` — isn't available on Flutter/AOT and wouldn't survive
`--obfuscate` either way). A Record sidesteps the problem instead of working
around it: `$.title` on a Record is a real, compiler-checked member access,
with no string and no lookup table anywhere in the path.

### Breaking

- `FieldSet`, `FieldSet.operator []`, and `FieldSet.byJsonKey` are removed.
- `ModelType<M, S extends FieldSet<M>>` is now `ModelType<M>` — drop the
  second type argument.
- `ModelType.bind(instance)` is now `ModelType.bind(instance, schema)` —
  pass the Record (or whatever schema) explicitly; `ModelBinder<M, S>`'s
  `S` is no longer constrained to `extends FieldSet<M>`, so it works with
  any shape.
- `Field`'s `name:` parameter and `fieldName` property are unchanged in
  signature, but `fieldName` is now purely cosmetic (error messages) — it
  no longer does anything for `copyWith` lookup, since there's no lookup
  anymore.
- Models that don't need `copyWith` get _simpler_: skip the Record
  entirely and pass `ModelType` a plain field list — see the README's
  "Minimal — no copyWith" section.

### Bonus

Two fields can no longer accidentally share a name: a Record literal with a
duplicate named field (`(title: a, title: b)`) is a compile error in Dart
itself. The `StateError`-based duplicate-name check 1.0.0 added to
`FieldSet` is gone because the problem it guarded against is no longer
reachable — the language already rejects it.

## 1.0.0 — Production-readiness pass

### Fixed

- **`copyWith` on a `FieldSet` declared as an anonymous field list.**
  `$.field.set(value)` only ever worked when every field was _also_ a named
  property — `$.value` simply has no meaning on a class whose fields exist
  only as anonymous elements of a list literal; that's a property of Dart's
  static typing, not something the library could route around. Added
  `FieldSet.operator []`, keyed by each field's Dart-facing `name` (not its
  JSON key — see the next point), so the concise list-literal style can now
  reach `copyWith` via `$['title'].set(99.9)`. Added `FieldSet.byJsonKey()`
  as an explicit, separate lookup for the rarer case that's actually about
  the wire key rather than the domain name.
  > **Superseded in 2.0.0** — see above. `FieldSet` and this whole
  > mechanism were replaced by plain Records.
- **An unsound `null as R` cast** in the field-parsing path. A custom parser
  that legitimately returned `null` for a non-nullable `R` (a fairly common
  pattern — e.g. an explicit `xOrNull` parser meant to make a field
  required) could throw a raw `TypeError` instead of a clean
  `RequiredFieldError`. `Field.parser` is now typed
  `Object? Function(Object?)` instead of `R Function(Object?)`, so `null`
  can be returned directly, with no cast.
- **`Field.nullable` now defaults to `null is R`** instead of unconditionally
  `false`. A field typed `T?` is optional out of the box; you no longer also
  have to remember to pass `nullable: true`. Pass it explicitly only to
  override the default.
- **`mapOrNullOf` now wraps entry errors with the offending key**, matching
  `mapOf` / `mapOrThrowOf` and the `List`/`Set` equivalents (previously the
  only collection parser that didn't).
- **`errors.dart` is exported from the package root.** `SerializationError`,
  `RequiredFieldError`, and `TypeConversionError` were previously only
  reachable via a `package:json_forge/src/...` import — outside the
  package's intended public surface.
- **`FieldSet` now rejects duplicate JSON keys** with a clear `StateError`
  instead of silently dropping one of the clashing fields.
  > **Superseded in 2.0.0** — Records make this unreachable at the
  > language level instead (see above).

### Changed

- Reorganized into small, single-purpose files (see the README's "Package
  layout") — `types/parser.dart` in particular went from one ~600-line file
  to a barrel over seven focused ones. No public API or import path changed:
  `import 'package:json_forge/json_forge.dart';` still exposes everything.
- All comments and error messages normalized to English.
- Added `analysis_options.yaml` and filled in `pubspec.yaml` for a
  publishable package shape.

### Notes

- Considered `Symbol`-keyed lookup (`#title`) instead of a `String` `name:`
  for `operator []`, since the field already closes over the model property
  via its getter. Didn't adopt it: a `Symbol` literal isn't checked against
  any real declaration either (`#tiel` "compiles" exactly as readily as
  `'title'` would), and `Symbol`/reflection-based dispatch is generally not
  safe under `dart compile exe --obfuscate` — which is also why this
  package never used named-argument `Function.apply` dispatch for
  `fromJson`. A plain `String` has neither downside.
- `at(key, parser)` was re-documented, not changed: its wrapper is a
  deliberate passthrough — the actual nested-key traversal happens once, in
  `SerializableHelpers._readPath`, driven by `Field.nesting`. `at` only
  records that path; this is easy to misread as a bug (the wrapper "doesn't
  index into anything"), so the new file header spells out why.
