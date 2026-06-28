# json_forge

A zero-code-generation, declarative JSON (de)serialization engine for Dart
and Flutter — type-safe fields, smart type conversion, and immutable
`copyWith`, without `build_runner`.

## Quick start

```dart
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(this.uid, this.value);

  final String uid;
  final double value;

  // M is always explicit — Dart can't infer it from a positional
  // constructor. This order is what `Function.apply` uses internally, so
  // `SensorSchema.all` (and `props` below) must list fields in this same
  // order.
  static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  // `Equatable`'s own list — `Serializable` doesn't write this for you.
  // No JSON keys or strings here, just the values, same order as above.
  // It's what makes `toJson()` (below) and `==`/`hashCode` work correctly
  // no matter how a `Sensor` was constructed, not just via `fromJson`.
  @override
  Props get props => [uid, value];

  factory Sensor.fromJson(Json json) => $.call(json);

  Sensor copyWith(FieldsBuilder<SensorSchema> builder) => $.bind(this)(builder);
}

// A class you extend, declaring each field once as a member. This is what
// makes `copyWith` below read `$.value.set(...)` with no string keys and
// no reflection — `$.value` is a real, compile-time-checked member access.
// `all` doubles as the ordered field list `fromJson` needs.
final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');

  @override
  ListFieldOf<Sensor> get all => [uid, value];
}

void main() {
  final sensor = Sensor.fromJson({'sensor_uid': 'SN-1', 'last_value': 10.5});
  final updated = sensor.copyWith(($) => [$.value.set(99.9)]);
  print(updated.toJson()); // {sensor_uid: SN-1, last_value: 99.9}
}
```

No `.g.dart` files, no `build_runner` step — `toJson` and `copyWith` are
both derived from `SensorSchema` and `props` above (and `==`/`hashCode`
come from `Equatable`, driven by that same `props`).

> **Why `props` is required.** Without code generation or runtime
> reflection (unavailable on Flutter/AOT), nothing can read a model's
> current field values generically — something has to supply them. A
> per-field getter closure on `Field` could do it, but `props` gets the
> same result with one ordinary `Equatable` list instead — and as a bonus,
> it means `toJson()`/`==` are correct for _any_ `Sensor`, including one
> built by calling its constructor directly, not just ones built via
> `fromJson`/`copyWith`. (A JSON-keyed `Map` instead of an ordered list was
> considered, to avoid needing `props` and `fields` in the same order —
> and rejected, because it would mean writing every JSON key out as a
> string a second time, which is exactly the kind of stringly-typed
> duplication `Schema`/`Field` exist to eliminate. `toJson()` does check
> that `props` and `fields` are at least the same _length_, always, and
> — in debug builds — that each slot's value looks like it belongs to
> that slot's field.)

## Why a `Schema` class, and not a string key, `Symbol`, or Record?

`copyWith`'s builder needs _some_ way to give you back the right `Field`
object for a given model property — `$.title`, ideally, not `$['title']`.
There's no codegen-free way to ask Dart "what property does this model
expose under this name?": Dart has no runtime reflection on Flutter/AOT
(`dart:mirrors` isn't available there), so the engine can't discover field
names on its own — they have to be declared, once, somewhere.

A `String` key (`$['title']`) works, but a typo surfaces as a runtime
`ArgumentError` instead of a compile error. A `Symbol` (`$[#title]`)
doesn't actually improve on that either — a `Symbol` literal isn't checked
against any real declaration (`#tiel` "compiles" exactly as readily as
`'tiel'` would), and `Symbol`/reflection-based dispatch generally isn't
safe under `dart compile exe --obfuscate`, which is also why this package
never uses named-argument `Function.apply` dispatch internally. A Dart
_Record_ is another option (and is what earlier versions of this package
used — see the CHANGELOG) — but it's a second declaration to keep in sync
with the field list `ModelType` actually needs.

Declaring each field as a real member of a class — `late final title =
field<String>('display_name');` on a class extending `Schema<M>` — gets
the same compiler guarantees a Record does (`$.title` is resolved by the
analyzer like any other member access; a typo is a compile error, not a
runtime one), while also being the field list itself: the schema's
required `all` getter _is_ the ordered list `ModelType` feeds into
`fromJson`. One declaration covers both `fromJson`/`toJson` and type-safe
`copyWith` — there's no separate Record `typedef` to keep matching it.

## The pieces

- **`Field<M, R>`** — a descriptor for one JSON key: how to parse it from
  JSON (`parser`), whether `null` is acceptable (`nullable`, defaulting to
  `null is R`), and an optional custom `serializer`. It carries no getter
  and no per-instance state — see the "Why `props` is required" note above.
- **`Schema<M>`** — a class you extend, declaring each field once as a
  `late final` member via `field<R>(jsonKey, ...)`. The required `all`
  getter lists every field **in constructor-parameter order** — the one
  thing every model needs, fed straight into `ModelType`. Skip naming
  individual fields (just fill in `all` directly) if a model doesn't need
  `copyWith` — see "Minimal" below.
- **`ModelType<M, S>`** — binds a `Schema` instance to the model's
  constructor; the engine behind `fromJson` (and what `toJson` iterates,
  via `Serializable`, together with `props`).
- **`ModelBinder<M, S>`** — what `ModelType.bind` returns; a stored,
  callable `copyWith`.

### Minimal — no `copyWith`

```dart
class Gadget extends Equatable with Serializable<Gadget> {
  const Gadget(this.uid, this.reading);

  final String uid;
  final double reading;

  static final $ = ModelType<Gadget, GadgetSchema>(Gadget.new, GadgetSchema());

  @override
  ListFieldOf<Gadget> get fields => $.schema.all;

  @override
  Props get props => [uid, reading];

  factory Gadget.fromJson(Json json) => $.call(json);
}

final class GadgetSchema extends Schema<Gadget> {
  @override
  ListFieldOf<Gadget> get all => [
    'gadget_uid'.field<Gadget, String>(),
    'reading'.field<Gadget, double>(parser: doubleOrZero),
  ];
}
```

No named per-field members, no `copyWith` — just `fromJson`/`toJson`, via
the top-level `.field()` string extension straight inside `all`. `props`
is still required (`Equatable` always needs it); give fields names (as in
the Quick start above) only once you actually want type-safe `copyWith`.

### Decoupling the wire format from `copyWith` call sites

A field's Dart-facing name (its member name on the `Schema`) and its
`jsonKey` are independent by construction — no extra parameter needed to
keep them that way:

```dart
final class TerminalSchema extends Schema<Terminal> {
  late final title = field('display_name', parser: stringOrDefault('Unnamed'));
  late final status = field(
    'device_status',
    parser: enumOrFirst(DeviceStatus.values),
    serializer: enumToJson,
  );
  // ...

  @override
  ListFieldOf<Terminal> get all => [title, status /* , ... */];
}

terminal.copyWith(($) => [
  $.title.set('ZONE_B'),
  $.status.set(DeviceStatus.maintenance),
]);
```

If the wire format changes (`display_name` → `name`), every `copyWith`
call site above is untouched — only the one line declaring `title` inside
`TerminalSchema` needs to change. (`Terminal` itself still needs `props`
listing `title`, `status`, etc. in this same order — `Schema.all` and
`props` are two separate lists that both have to match the constructor.)

## Field nullability

`nullable` defaults to `null is R` — a field typed `String?` is optional
out of the box, a field typed `String` is required out of the box:

```dart
// Optional, no extra flag needed:
'address'.field<User, Address?>(parser: modelOrNull(Address.fromJson));

// Required by default (R is non-nullable):
'name'.field<User, String>();
```

Pass `nullable:` explicitly only to override that default.

## Nested JSON paths

```dart
// Inside a Schema<M> subclass:
late final count = field<int>('count', parser: at('meta', intOrZero));
// reads json['meta']['count']
```

`at` only _records_ the path (used to read/write the value); the parser
you wrap still receives the already-resolved leaf value. `props` doesn't
need to know about nesting at all — it's just the model's own values, in
constructor order, same as for any other field.

## Errors

Deserialization failures are typed: `RequiredFieldError` (missing/null
required field) and `TypeConversionError` (wrong type) both extend
`SerializationError`, and carry the model type, field name, full JSON path,
and raw value.

## Package layout

```
lib/
  json_forge.dart            barrel — the only import most users need
  src/
    errors.dart               SerializationError / RequiredFieldError / TypeConversionError
    extension.dart             the `.field()` String extension
    serializable_model.dart    Serializable mixin + SerializableHelpers engine
    types/
      types.dart               shared typedefs (Json, Parser, Serializer, ...)
      field.dart                Field<M, R>
      field_patch.dart          FieldPatch + Field.set()
      model_type.dart           Schema<M> + ModelType + ModelBinder
      parser.dart               barrel for parsers/
      parsers/
        primitives.dart         String, int, double, num, bool, BigInt, Uri
        temporal.dart           DateTime, Duration
        enum_parser.dart        Enum
        collections.dart        List, Set, Map
        model_parser.dart       nested models, raw JSON objects
        nested_access.dart      at(key, parser)
        combinators.dart        oneOf, mappedOrNull, tryOrNull, withFallback, nullable
```

Only `lib/json_forge.dart` is meant to be imported by consumers; everything
under `src/` is an implementation detail and may change between minor
versions without notice.
