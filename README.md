# json_forge

A zero-code-generation, declarative JSON (de)serialization engine for Dart
and Flutter — type-safe fields, smart type conversion, and immutable
`copyWith`, without `build_runner`.

## Quick start

```dart
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

// A named Record listing each field by its Dart-facing name. This is what
// makes `copyWith` below read `$.value.set(...)` with no string keys and
// no reflection — `$.value` is a native, compile-time-checked Record access.
typedef SensorFields = ({
  Field<Sensor, String> uid,
  Field<Sensor, double> value,
});

class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(this.uid, this.value);

  final String uid;
  final double value;

  static final SensorFields _fields = (
    uid: 'sensor_uid'.field((m) => m.uid),
    value: 'last_value'.field((m) => m.value, parser: doubleOrZero),
  );

  // M is always explicit — Dart can't infer it from a positional
  // constructor. This order is what `Function.apply` uses internally, so
  // it must match the constructor parameter order above.
  static final $ = ModelType<Sensor>(Sensor.new, [_fields.uid, _fields.value]);

  @override
  ListFieldOf<Sensor> get fields => $.all;

  factory Sensor.fromJson(Json json) => $.call(json);

  late final copyWith = $.bind(this, _fields);
}

void main() {
  final sensor = Sensor.fromJson({'sensor_uid': 'SN-1', 'last_value': 10.5});
  final updated = sensor.copyWith(($) => [$.value.set(99.9)]);
  print(updated.toJson()); // {sensor_uid: SN-1, last_value: 99.9}
}
```

No `.g.dart` files, no `build_runner` step — `toJson`, `fromJson`, `==`/
`hashCode` (via `Equatable`), and `copyWith` are all derived from `_fields`
and the order list above.

## Why a Record, and not a string key or `Symbol`?

`copyWith`'s builder needs _some_ way to give you back the right `Field`
object for a given model property — `$.title`, ideally, not `$['title']`.
There's no codegen-free way to ask Dart "what property does `(m) => m.title`
read?": closures don't expose that at runtime, and the one tool that could
in principle inspect it (`dart:mirrors`, by walking the AST) isn't available
on Flutter/AOT in the first place.

A `String` key (`$['title']`) works, but a typo surfaces as a runtime
`ArgumentError` instead of a compile error. A `Symbol` (`$[#title]`) doesn't
actually improve on that: a `Symbol` literal isn't checked against any real
declaration either — `#tiel` "compiles" exactly as readily as `'tiel'`
would — and `Symbol`/reflection-based dispatch generally isn't safe under
`dart compile exe --obfuscate` (identifiers get renamed; `Symbol` literals
built from strings don't reliably follow along), which is also why this
package never uses named-argument `Function.apply` dispatch internally.

A plain Dart **Record** sidesteps all of this. `$.title` on a Record is
resolved by the analyzer like any other member access — a typo is a
compile error, the value type is checked, and there's no string, no lookup
table, and no obfuscation risk anywhere in the path. The cost is exactly
one declaration: list each field once, by name, in a Record literal. That's
the same amount of naming you'd do for any per-field property — it's just
expressed as Record fields instead of class members, and it drops the
abstract-class ceremony that used to come with it.

## The pieces

- **`Field<M, R>`** — a descriptor binding one JSON key to one Dart
  property: how to read it off the model (`getter`), how to parse it from
  JSON (`parser`), whether `null` is acceptable (`nullable`, defaulting to
  `null is R`), and an optional custom `serializer`.
- **A `static final` list of `Field`s, in constructor-parameter order** —
  the one thing every model needs. Fed straight into `ModelType`, this
  alone is enough for `fromJson`/`toJson`; nothing else is required if a
  model doesn't need `copyWith`.
- **A named Record (optional)** — only needed for type-safe `copyWith`.
  Give each field a name there; `ModelType.bind` hands that Record to your
  `copyWith` builder as `$`.
- **`ModelType<M>`** — binds the ordered list to the model's constructor;
  the engine behind `fromJson` (and what `toJson`/`props` iterate, via
  `Serializable`).
- **`ModelBinder<M, S>`** — what `ModelType.bind` returns; a stored,
  callable `copyWith`, generic over whatever schema (`S`) you handed it.

### Minimal — no `copyWith`

```dart
class Gadget extends Equatable with Serializable<Gadget> {
  const Gadget(this.uid, this.reading);

  final String uid;
  final double reading;

  static final $ = ModelType<Gadget>(Gadget.new, [
    'gadget_uid'.field<Gadget, String>((m) => m.uid),
    'reading'.field((m) => m.reading, parser: doubleOrZero),
  ]);

  @override
  ListFieldOf<Gadget> get fields => $.all;

  static Gadget fromJson(Json json) => $.call(json);
}
```

No Record, no `copyWith` — just `fromJson`/`toJson`. Add a Record (as in
the Quick start above) only once you actually want type-safe `copyWith`.

### Decoupling the wire format from `copyWith` call sites

A Record's field name and a field's `jsonKey` are independent by
construction — no extra parameter needed to keep them that way:

```dart
typedef TerminalFields = ({
  Field<Terminal, String> title,
  Field<Terminal, DeviceStatus> status,
});

static final TerminalFields _fields = (
  title: 'display_name'.field((m) => m.title, parser: ...),
  status: 'device_status'.field(..., serializer: enumToJson),
);

terminal.copyWith(($) => [
  $.title.set('ZONE_B'),
  $.status.set(DeviceStatus.maintenance),
]);
```

If the wire format changes (`display_name` → `name`), every `copyWith`
call site above is untouched — only the one line declaring `_fields` needs
to change.

## Field nullability

`nullable` defaults to `null is R` — a field typed `String?` is optional out
of the box, a field typed `String` is required out of the box:

```dart
// Optional, no extra flag needed:
'address'.field<User, Address?>((m) => m.address, parser: modelOrNull(Address.fromJson));

// Required by default (R is non-nullable):
'name'.field<User, String>((m) => m.name);
```

Pass `nullable:` explicitly only to override that default.

## Nested JSON paths

```dart
'count'.field((m) => m.count, parser: at('meta', intOrZero)); // json['meta']['count']
```

`at` only _records_ the path (used to read/write the value); the parser you
wrap still receives the already-resolved leaf value.

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
      model_type.dart           ModelType + ModelBinder
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
