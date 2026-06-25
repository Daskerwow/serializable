# Changelog

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
