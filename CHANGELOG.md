# Changelog

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
parsed _for_, via an `Expando` (`Field.attach`, populated only by
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
user-supplied closure _and_ a contravariant type-erasure wrapper, the same
problem `serializer` already has) means the model has to supply its
current values some other way. `props` already exists for exactly this —
`Equatable` requires it from every subclass — so `toJson()` now reads from
it instead of from a cache. The result is simpler (the `Expando`, `attach`,
and `readErased` machinery is gone from `Field` entirely) and correct
unconditionally: `toJson()`/`==` now reflect real values for _any_
instance, not only ones built via `fromJson`/`copyWith`.

### Breaking

- `Serializable<M>` no longer provides a default `props` — implement it
  yourself, listing the same fields in the same order as `fields`/`all`
  and the constructor. This is one line per model; see the README and the
  `Serializable` doc comment for the full pattern.
- `Field.attach` and `Field.readErased` are removed. Nothing in this
  package called them except the now-deleted cache-population loop in
  `fromJson` and the now-deleted default `props` getter.

## 3.0.0 — `Schema` classes, replacing the Record requirement

`ModelType<M, S>` now takes a **`Schema<M>` instance** instead of a bare
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

### Why

2.0.0's Record schema solved the problem a Record is good at — a
compiler-checked `$.value` with no string lookup — but left every model
with **two** declarations to keep in sync: the Record `typedef` (the named
accessors) and the plain field list passed to `ModelType` (the
constructor-parameter order `fromJson` actually needs). `Schema<M>` is
both at once: its members are the named accessors, and its `all` getter
_is_ the ordered field list. One declaration instead of two, with the same
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
