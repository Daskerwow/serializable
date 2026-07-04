# json_forge

A zero-code-generation JSON serialization engine for Dart & Flutter.

No `build_runner`, no `.g.dart` files, no watching a terminal for codegen to
finish. You declare a model's fields once — as plain Dart objects, not
annotations — and get type-safe `fromJson`, `toJson`, and `copyWith` for
free, including for deeply nested models, lists, maps, and enums.

```dart
class User extends Equatable with Serializable<User> {
  final int id;
  final String name;
  final String? email;

  const User(this.id, this.name, this.email);

  static final $ = ModelType<User, UserSchema>(User.new, UserSchema());

  @override
  ListFieldOf<User> get fields => $.schema.all;

  factory User.fromJson(Json json) => $.call(json);
  User copyWith(FieldsBuilder<UserSchema> updates) => $.bind(this)(updates);
}

final class UserSchema extends Schema<User> {
  @override
  ListFieldOf<User> get all => [
    'user_id'.field((m) => m.id);
    'full_name'.field((m) => m.name);
    'email_address'.field((m) => m.email, nullable: true);
  ];
}
```

```dart
final user = User.fromJson({'user_id': 7, 'full_name': 'Ada', 'email_address': null});
final renamed = user.copyWith(($) => [$.set((m) => m.name, 'Ada Lovelace')]);
print(user.toJson()); // {'user_id': 7, 'full_name': 'Ada', 'email_address': null}
print(renamed.toJson()); // {'user_id': 7, 'full_name': 'Ada Lovelace', 'email_address': null}
```

That's the whole API surface for a simple model. Everything below is what
you reach for as your models get more interesting.

## Table of contents

- [Why json_forge](#why-json_forge)
- [Installation](#installation)
- [Core concepts](#core-concepts)
- [Declaring a model](#declaring-a-model)
- [Parsing values](#parsing-values)
- [Enums](#enums)
- [Collections](#collections)
- [Nested models](#nested-models)
- [Nested JSON paths — `at()`](#nested-json-paths--at)
- [Combinators](#combinators)
- [Serialization (`toJson`)](#serialization-tojson)
- [`copyWith`](#copywith)
- [Error handling](#error-handling)
- [Correctness by construction](#correctness-by-construction)
- [Gotchas](#gotchas)
- [API reference](#api-reference)
- [License](#license)

## Why json_forge

- **No code generation.** Nothing to run, nothing to check in, nothing to
  go stale after you rename a field.
- **Declarative.** A model's JSON shape lives in one `Schema` class, read
  top to bottom.
- **Smart type conversion.** `int`, `double`, `bool`, `String`, `DateTime`,
  `Duration`, `Uri`, and `BigInt` fields get a sensible default parser for
  free — messy real-world APIs (numbers as strings, timestamps as either
  seconds or milliseconds, booleans as `"yes"`/`"no"`) are handled without
  you writing anything.
- **Type-safe `copyWith`.** No stringly-typed patch maps by default —
  `$.name.set('Ada Lovelace')` is checked at compile time against the
  field's declared type.
- **Equatable integration.** Every model's `==`/`hashCode` and `toJson()`
  are built from the same `props` list, so they can never quietly drift
  apart from each other.
- **Correct even without `fromJson`.** A model built by calling its own
  constructor directly — no JSON involved at all — still serializes and
  compares correctly. See [Correctness by construction](#correctness-by-construction).

## Installation

```yaml
dependencies:
  json_forge: ^0.1.0
  equatable: ^2.0.0
```

```dart
import 'package:json_forge/json_forge.dart';
```

`equatable` is a direct dependency: every serializable model extends
`Equatable` and mixes in `Serializable<M>`.

## Core concepts

| Type                    | Role                                                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Field<M, R>`           | Descriptor for one JSON key: its parser, its serializer, whether it's nullable, and (optionally) a getter back onto the model. Carries no per-instance state. |
| `Schema<M>`             | A class you extend once per model, declaring every `Field` as a member.                                                                                       |
| `ModelType<M, S>`       | Binds a `Schema<M>` to the model's constructor. Powers both `fromJson` and `copyWith`.                                                                        |
| `ModelBinder<M, S>`     | A callable, bound to one instance, returned by `ModelType.bind` — this is what `copyWith` actually calls.                                                     |
| `Serializable<M>`       | Mixin providing `toJson()` automatically, built from `fields` + `props`.                                                                                      |
| `SerializableModelI<M>` | The interface every model implements: `fields`, `toJson()`, `props`.                                                                                          |

`fields` and `props` must list every field **in the same order as the
model's positional constructor parameters** — `fromJson` calls the
constructor positionally via `Function.apply`, and `toJson()` zips
`fields` with `props` index-for-index. A length mismatch, or a same-index
type mismatch, throws a clear `StateError` immediately rather than
silently writing the wrong value into the wrong key.

## Declaring a model

There are two ways to satisfy `props` (the standard `Equatable` list).
Pick whichever fits — a model can even mix both styles as long as it
still overrides `props` itself when it does:

**1. Explicit `props`** (works for any field, no extra setup):

```dart
class Sensor extends Equatable with Serializable<Sensor> {
  final String uid;
  final double value;

  const Sensor(this.uid, this.value);

  static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  @override
  Props get props => [uid, value]; // same order as the constructor

  factory Sensor.fromJson(Json json) => $.call(json);
  Sensor copyWith(FieldsBuilder<SensorSchema> updates) => $.bind(this)(updates);
}

final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');

  @override
  ListFieldOf<Sensor> get all => [uid, value];
}
```

**2. Getter-derived `props`** (give _every_ field a `getter:` and skip
`props` entirely — `Serializable`'s default implementation builds it for
you):

```dart
final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid', getter: (m) => m.uid);
  late final value = field<double>('last_value', getter: (m) => m.value);

  @override
  ListFieldOf<Sensor> get all => [uid, value];
}
```

The getter-derived style is also what unlocks the faster, allocation-free
`copyWith` path — see [`copyWith`](#copywith).

There's also a top-level `String.field()` extension for a field declared
outside any `Schema` — the same `Field` under the hood, useful for one-off
or dynamically-assembled field lists:

```dart
'user_id'.field<User, int>(parser: intOrZero)
'name'.field<User, String>()                 // smart inference for String
'tags'.field<User, List<String>>(parser: listOf(stringOrEmpty))
'address'.field<User, Address?>(parser: modelOrNull(Address.fromJson))
```

It also accepts an optional leading `getter`, exactly like `Schema.field`:

```dart
'sensor_uid'.field((m) => m.uid) // M and R inferred from the getter
```

## Parsing values

If you don't pass `parser:`, json_forge picks a default based on the
field's declared type `R`:

| `R`                      | Default parser                       |
| ------------------------ | ------------------------------------ |
| `int` / `int?`           | `intOrZero` / `intOrNull`            |
| `double` / `double?`     | `doubleOrZero` / `doubleOrNull`      |
| `num` / `num?`           | `numOrZero` / `numOrNull`            |
| `bool` / `bool?`         | `boolOrFalse` / `boolOrNull`         |
| `String` / `String?`     | `stringOrEmpty` / `stringOrNull`     |
| `DateTime` / `DateTime?` | `dateTimeOrEpoch` / `dateTimeOrNull` |
| `Duration` / `Duration?` | `durationOrZero` / `durationOrNull`  |
| `Uri` / `Uri?`           | `uriOrEmpty` / `uriOrNull`           |
| `BigInt` / `BigInt?`     | `bigIntOrZero` / `bigIntOrNull`      |

Anything else (`List`, `Map`, a nested model, an `Enum`) has no default —
pass an explicit `parser:`.

Every primitive parser follows the same naming convention, and each
variant is exported individually so you can use it outside a `Field` too:

- `xOrNull` — `null` on missing/incompatible input. Total, never throws.
- `xOrDefault(fallback)` — returns a `Parser<X>` that falls back to
  `fallback` instead of `null`.
- `xOrZero` / `xOrEmpty` / `xOrFalse` — a fixed, type-appropriate default.
- `xOrThrow` — throws `FormatException` on missing/incompatible input. Use
  only where a bad value is a real bug, not just messy input.

`intOrNull`, `doubleOrNull`, and `numOrNull` all accept numbers, numeric
strings, and booleans (`true`/`false` → `1`/`0`). `boolOrNull` accepts
`true`/`false`, `0`/`1`, and the strings `"true"/"false"`, `"yes"/"no"`,
`"y"/"n"`, `"on"/"off"` (case-insensitively). `dateTimeOrNull` accepts an
ISO-8601 string or a Unix timestamp in either seconds or milliseconds
(disambiguated by magnitude). `uriOrNull` parses any syntactically valid
URI; `httpUriOrNull` additionally requires an absolute `http`/`https` URI
with a non-empty host.

**Field-level `nullable`** defaults to `null is R` — a field typed `T?` is
optional out of the box, a field typed `T` is required out of the box.
Pass `nullable:` explicitly only to override that default. A required
field that comes back `null` from its parser throws `RequiredFieldError`.

## Enums

Enums always need an explicit parser, matched by member name:

```dart
enum Status { active, maintenance, offline }

late final status = field(
  'device_status',
  parser: enumOrFirst(Status.values),
  serializer: enumToJson,
);
```

- `enumOrNull(values, {caseInsensitive})` — `null` for an unrecognized name.
- `enumOrDefault(values, fallback, {caseInsensitive})`
- `enumOrFirst(values, {caseInsensitive})` — falls back to `values.first`.
- `enumOrLast(values, {caseInsensitive})` — falls back to `values.last`.
- `enumOrThrow(values, {caseInsensitive})` — throws `FormatException`.
- `enumToJson` — serializer: `Enum` → `.name`.

The default `toJson()` already serializes any bare `Enum` field via
`.name` — you only need `enumToJson` explicitly if you also want the same
symmetry made visible in the field declaration, or you're not using one of
the four `enumOr*` parsers above. See [Gotchas](#gotchas) for the one place
this needs _more_ than that.

## Collections

`listOf`, `setOf`, and `mapOf` build a total collection parser from a
per-element (or per-entry) `Parser<T>`. Each comes in three flavors:

- `xOf` — empty collection (`[]` / `{}`) on non-matching input.
- `xOrNullOf` — `null` on non-matching input.
- `xOrThrowOf` — `FormatException` on non-matching input.

```dart
late final tags = field('tags', parser: listOf(stringOrEmpty));
late final scores = field('scores', parser: setOf(intOrZero));
late final tokens = field(
  'access_keys',
  parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
  serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
);
```

An element/entry that fails to parse is wrapped with its index (for
`List`/`Set`) or key (for `Map`) so a failure deep inside a large payload
is easy to locate — e.g. `listOf<int>[3]: FormatException: ...`.

> That `tokens` field's `serializer:` isn't decorative — see
> [Gotchas](#gotchas) for why an `Enum`-keyed `Map` needs one.

## Nested models

```dart
late final address = field('user_address', parser: modelOrNull(Address.fromJson));
late final owner = field('owner', parser: modelOf(User.fromJson));
```

- `modelOf(fromJson)` — throws `FormatException` if the value isn't a `Map`.
- `modelOrNull(fromJson)` — `null` if the value isn't a `Map`.
- `modelOrThrow(fromJson)` — alias for `modelOf`, for naming symmetry.

Nested models need no `serializer:` — the default serializer calls the
nested model's own `.toJson()` recursively, including inside `List`/`Set`/`Map`.

## Nested JSON paths — `at()`

For a field that lives one or more levels deep in the JSON object:

```dart
// json['meta']['count'] as an int:
late final count = field('count', parser: at('meta', intOrZero));

// json['meta']['stats']['total'] as a double — chained at():
late final total = field('total', parser: at('meta', at('stats', doubleOrZero)));
```

`at()` only records the path; the actual traversal happens before the
parser ever runs, both for reading (`fromJson`) and for writing
(`toJson()`/`copyWith` build the intermediate `Map`s on the fly). Error
paths reported by `SerializationError` include the full dotted path, e.g.
`meta.stats.total`.

## Combinators

Small building blocks for composing parsers/serializers:

```dart
Parser<T?> oneOf<T>(List<Parser<T?>> parsers)          // first non-null result
Parser<R?> mappedOrNull<T, R>(Parser<T?> p, R? Function(T) f)
Parser<R> mappedOrDefault<T, R>(Parser<T?> p, R Function(T) f, R fallback)
Parser<T?> tryOrNull<T>(Parser<T> p)                    // catches exceptions
Parser<T> withFallback<T>(Parser<T> p, T fallback)      // catches + defaults
Serializer<T?> nullable<T>(Serializer<T> s)             // lift a serializer to T?
```

```dart
late final ts = field<DateTime?>(
  'ts',
  parser: oneOf([dateTimeOrNull, mappedOrNull<int, DateTime>(intOrNull, DateTime.fromMillisecondsSinceEpoch)]),
  serializer: nullable(dateTimeToJson),
);
```

## Serialization (`toJson`)

`toJson()` is built automatically from `fields` + `props`. For each field,
in order:

- If the field has a custom `serializer:`, that's used.
- Otherwise, the default recursive serializer handles it:

| Dart type                 | JSON representation                        |
| ------------------------- | ------------------------------------------ |
| `null`                    | `null`                                     |
| a `SerializableModelI`    | `.toJson()`                                |
| `DateTime`                | ISO-8601 string                            |
| `Duration`                | milliseconds (`int`)                       |
| `Uri`                     | string                                     |
| `BigInt`                  | string                                     |
| `Enum`                    | `.name`                                    |
| `List` / `Set`            | recursively serialized `List`              |
| `Map`                     | keys via `.toString()`, values recursively |
| `num` / `bool` / `String` | unchanged                                  |

## `copyWith`

```dart
final updated = terminal.copyWith(($) => [
  $.status.set(DeviceStatus.offline),   // resolved: $.<field>.set(value)
  $.set((m) => m.title, 'Renamed'),     // deferred: selector form
]);
```

`copyWith` picks one of two algorithms automatically, based on whether
_every_ field in the schema has a `getter:`:

- **Direct construction** (all fields have a `getter`) — no JSON
  round-trip at all: each field's new value comes from a matching patch,
  or is read straight off the current instance via its `getter`; the
  model's constructor is then called once with the resulting positional
  arguments.
- **JSON round-trip** (any field lacks a `getter`) — serializes the
  current instance via `toJson()`, writes each patch to its field's full
  path, and deserializes back via `fromJson` — every parser runs again,
  including for untouched fields.

### `$.field.set(value)` vs `$.set((m) => m.field, value)`

`$.field.set(value)` is resolved immediately — `field` already _is_ the
target `Field` object. `$.set((m) => m.field, value)` is more concise but
deferred: it's resolved later against a synthetic _probe_ instance, by
comparing what the selector reads against what each field's `getter`
reads. This works even for inline lambdas (two `(m) => m.title` literals
are never `identical` to each other, so results — not closures — are
compared), and even when two same-typed fields currently hold equal
values, by seeding the probe with a value proven distinct per field.

The one case this can't resolve: two fields of the exact same `enum` type,
both holding the same member, where _neither_ was declared through one of
the built-in `enumOr*` combinators (so their value domain is unknown) — or
any field of a type this library has no probe generator for at all
(nested models, `List`, `Map`, ...). That throws a `StateError` with a
clear explanation rather than guessing; use `$.field.set(value)` instead
in that case.

## Error handling

| Error                 | Thrown when                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| `RequiredFieldError`  | A non-nullable field parsed to `null` (missing or unparseable).                                                |
| `TypeConversionError` | A value was present but the wrong type after parsing.                                                          |
| `SerializationError`  | Base class; also used to wrap unexpected exceptions and constructor-call failures, with full context attached. |

Every one of these carries `modelType`, `jsonKey`, `path` (the full
dotted path, including any `at()` nesting), and `rawValue` where
applicable, and prints as a readable multi-line block:

```
SerializationError: [Order.amount]
  message  : expected int, got String
  path     : amount
  raw value: String (bad_value)
  expected : int
  actual   : String
```

## Correctness by construction

A model's `toJson()` and `==`/`hashCode` are built from its own `props`
— real, current field values — not from any state cached during
`fromJson`. That means a model built by calling its constructor directly,
with no JSON involved at all, still serializes and compares correctly:

```dart
final direct = Terminal(1, 'Direct', DeviceStatus.active, const [], const {}, const []);
direct.toJson();                                    // correct, not blank
direct.copyWith(($) => [$.title.set('Renamed')]);    // works too
```

## Gotchas

- **`Map<Enum, V>` fields need an explicit `.name`-based serializer.** The
  default serializer keys a `Map` by `.toString()`, and an `Enum`'s
  `.toString()` includes its type name (`"AccessLevel.write"`, not
  `"write"`). Left unfixed, that mismatched key won't be recognized by an
  `enumOr*` parser on the way back in, and `enumOrFirst`/`enumOrDefault`
  will silently substitute their fallback instead of throwing — so a
  `copyWith()` round-trip can quietly drop or corrupt every map entry
  except the one that happens to match the fallback. Always pair an
  `Enum`-keyed `Map` field with:
  ```dart
  serializer: (map) => {for (final e in map.entries) e.key.name: e.value}
  ```
- **`Schema.set` selector ambiguity** is a real, if narrow, failure mode —
  see [`copyWith`](#copywith) above. Prefer `$.field.set(value)` when in
  doubt; it never needs to disambiguate anything.
- **`fields` and `props` order must match the constructor.** Same-length,
  wrong-order lists are only caught when they produce a differently-typed
  value in some slot; two same-typed fields swapped will not be caught
  automatically.

## API reference

The package exports:

- `Field`, `Schema`, `ModelType`, `ModelBinder`, `FieldPatch`
- `Serializable`, `SerializableModelI`, `SerializableHelpers`, `undefined`
- `Json`, `JsonRaw`, `Parser<T>`, `Serializer<T>`, `FieldsBuilder<S>`, `FieldOf<M>`, `ListFieldOf<M>`, `Props`
- Primitives: `intOr*`, `doubleOr*`, `numOr*`, `boolOr*`, `stringOr*`, `bigIntOr*`, `uriOr*`, `httpUriOrNull`
- Temporal: `dateTimeOr*`, `durationOr*`
- Enums: `enumOrNull`, `enumOrDefault`, `enumOrFirst`, `enumOrLast`, `enumOrThrow`, `enumToJson`
- Collections: `listOf`/`listOrNullOf`/`listOrThrowOf`, `setOf`/`setOrNullOf`/`setOrThrowOf`, `mapOf`/`mapOrNullOf`/`mapOrThrowOf`
- Nested models: `modelOf`, `modelOrNull`, `modelOrThrow`, `jsonObjectOrNull`, `jsonObjectOrEmpty`, `jsonObjectOrDefault`, `jsonObjectOrThrow`
- Nested paths: `at`
- Combinators: `nullable`, `oneOf`, `mappedOrNull`, `mappedOrDefault`, `tryOrNull`, `withFallback`
- Errors: `SerializationError`, `RequiredFieldError`, `TypeConversionError`
- The `String.field()` extension

See `example.dart` for a complete runnable model, and
`complex_serialization_test.dart` for a larger, multi-model example
covering deep nesting, both `props` styles, and both `copyWith` paths.

## License

MIT — see `LICENSE` for details.
