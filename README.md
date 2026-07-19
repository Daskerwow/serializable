# json_forge

A zero-code-generation JSON serialization engine for Dart & Flutter.

No `build_runner`, no `.g.dart` files, no watching a terminal for codegen to
finish. You declare a model's fields once — as plain Dart objects, not
annotations — and get type-safe `fromJson` and `toJson` for free, including
for deeply nested models, lists, maps, and enums.

```dart
class User extends Equatable with Serializable<User>, PropsFromGetters<User> {
  final int id;
  final String name;
  final String? email;

  const User(this.id, this.name, this.email);

  static final $ = ModelType<User>(User.new, UserSchema());

  @override
  ListFieldOf get fields => $.schema.all;

  factory User.fromJson(Json json) => $.call(json);
}

final class UserSchema extends Schema<User> {
  @override
  late final all = [
    'user_id'.field(getter: (m) => m.id),
    'full_name'.field(getter: (m) => m.name),
    'email_address'.field(getter: (m) => m.email, nullable: true),
  ];
}
```

```dart
final user = User.fromJson({'user_id': 7, 'full_name': 'Ada', 'email_address': null});
print(user.toJson()); // {'user_id': 7, 'full_name': 'Ada', 'email_address': null}
```

That's the whole API surface for a simple model. Everything below is what
you reach for as your models get more interesting.

## Table of contents

- [Why json_forge](#why-json_forge)
- [Installation](#installation)
- [Core concepts](#core-concepts)
- [Declaring a model](#declaring-a-model)
- [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization)
- [Parsing values](#parsing-values)
- [Enums](#enums)
- [Collections](#collections)
- [Nested models](#nested-models)
- [Nested JSON paths — `at()`](#nested-json-paths--at)
- [Combinators](#combinators)
- [Fluent field builder](#fluent-field-builder)
- [Serialization (`toJson`)](#serialization-tojson)
- [Writing your own `copyWith`](#writing-your-own-copywith)
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
- **Rich, typed errors.** `RequiredFieldError`/`TypeConversionError` carry
  the model type, the JSON key, the full dotted path (including any
  `at(...)` nesting), and the raw value that caused the problem — no
  guessing which field broke, or digging through a generic exception.
- **Equatable integration.** Every model's `==`/`hashCode` and `toJson()`
  are built from the same `props` list, so they can never quietly drift
  apart from each other.
- **Correct even without `fromJson`.** A model built by calling its own
  constructor directly — no JSON involved at all — still serializes and
  compares correctly. See [Correctness by construction](#correctness-by-construction).
- **A `Function.apply`-free path when you need it.** `Field.readFrom`
  lets you hand-write `fromJson` as an ordinary, statically-typed
  constructor call — no dynamic dispatch, no runtime argument-type
  checking — while `toJson()` stays exactly as automatic as ever. See
  [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization).

## Installation

```yaml
dependencies:
  json_forge: ^6.1.0
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
| `Field<M, R>`           | Descriptor for one JSON key: its parser, its serializer, whether it's nullable, and (optionally) a getter back onto the model. Carries no per-instance state. `M` defaults to `Object?` when declared via the top-level `field<R>(jsonKey)` convenience. |
| `Schema<M>`             | A class you extend once per model, declaring every `Field` as a member — optional; see [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization) for the schema-free alternative. |
| `ModelType<M>`          | Binds a `Schema<M>` to the model's constructor. Powers `fromJson`.                                                                                            |
| `Serializable<M>`       | Mixin providing `toJson()` automatically, built from `fields` + `props`. Does **not** provide `props` itself — see below.                                    |
| `PropsFromGetters<M>`   | Opt-in mixin — combine with `Serializable<M>` (`with Serializable<M>, PropsFromGetters<M>`) to derive `props` from each field's `getter:` instead of writing it by hand. |
| `RecordedFields<M>`     | Opt-in mixin — combine with `Serializable<M>` to derive `fields` automatically from the `field(...)` calls made inside `fromJson`, instead of declaring a `fields`/`Schema` list. Requires building the model only through `recordFields(...)` — see [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization). |
| `SerializableModelI<M>` | The interface every model implements: `fields`, `toJson()`, `props`.                                                                                          |

`fields` and `props` must list every field **in the same order as the
model's positional constructor parameters** — `fromJson` calls the
constructor positionally via `Function.apply`, and `toJson()` zips
`fields` with `props` index-for-index. A length mismatch, or a same-index
type mismatch, throws a clear `StateError` immediately rather than
silently writing the wrong value into the wrong key.

`Serializable<M>` deliberately only provides `toJson()`, never `props` —
every model still has to satisfy `props` itself, exactly as with plain
`Equatable`: write it by hand, inherit it from a plain base class, or mix
in `PropsFromGetters<M>` as well. This is a deliberate split, not an
oversight: `props` is `Equatable`'s own abstract member, and a mixin's
members take priority over whatever the class(es) it's applied on top of
already provide — so if `Serializable` supplied a `props` default of its
own, it would silently *shadow* a perfectly good `props` inherited from
anywhere else in the hierarchy, the moment `Serializable` sat between that
class and the model in the `with` chain. See
[Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization)
for exactly this scenario.

## Declaring a model

There are three ways to satisfy `props` (the standard `Equatable` list) —
pick whichever fits:

**1. Explicit `props`** (works for any field, no extra setup):

```dart
class Sensor extends Equatable with Serializable<Sensor> {
  final String uid;
  final double value;

  const Sensor(this.uid, this.value);

  static final $ = ModelType<Sensor>(Sensor.new, SensorSchema());

  @override
  ListFieldOf get fields => $.schema.all;

  @override
  Props get props => [uid, value]; // same order as the constructor

  factory Sensor.fromJson(Json json) => $.call(json);
}

final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');

  // `late final`, not `get all => [...]` — computed once and reused, since
  // `fields` (and therefore `toJson()`) reads `schema.all` on every call.
  @override
  late final all = [uid, value];
}
```

**2. Inherited `props`** — declare it once on a plain, non-`Serializable`
base class, and let the JSON-capable subclass inherit it untouched. See
[Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization)
below for the full pattern this unlocks.

**3. Getter-derived `props`** (give _every_ field a `getter:` and mix in
`PropsFromGetters<M>` alongside `Serializable<M>` — its default
implementation builds `props` for you):

```dart
class Sensor extends Equatable with Serializable<Sensor>, PropsFromGetters<Sensor> {
  final String uid;
  final double value;

  const Sensor(this.uid, this.value);

  static final $ = ModelType<Sensor>(Sensor.new, SensorSchema());

  @override
  ListFieldOf get fields => $.schema.all;

  // No `props` override needed — PropsFromGetters derives it from the
  // `getter:` on every field below.

  factory Sensor.fromJson(Json json) => $.call(json);
}

final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid', getter: (m) => m.uid);
  late final value = field<double>('last_value', getter: (m) => m.value);

  @override
  late final all = [uid, value];
}
```

> `Serializable<M>` alone deliberately does **not** provide `props` —
> see [Core concepts](#core-concepts) for why bundling it in would be
> unsound the moment a model inherits `props` from somewhere else, which
> is exactly what style 2 above (and the pattern in the next section)
> does on purpose.

There's also a top-level `String.field()` extension for a field declared
outside any `Schema` — the same `Field` under the hood, useful for one-off
or dynamically-assembled field lists:

```dart
'user_id'.field<User, int>(parser: intOrZero)
'name'.field<User, String>()                 // smart inference for String
'tags'.field<User, List<String>>(parser: listOf(stringOrEmpty))
'address'.field<User, Address?>(parser: modelOrNull(Address.fromJson))
```

It also accepts an optional `getter:`, exactly like `Schema.field` — as a
*named* argument, since Dart doesn't allow an optional positional
parameter to sit alongside the named ones (`parser`, `serializer`,
`nullable`) already on this method:

```dart
'sensor_uid'.field<Sensor, String>(getter: (m) => m.uid)
```

And, for when there's no `Schema` (or even a concrete model type) in
scope at all — e.g. directly inside a hand-written `fromJson` — there's a
third, fully model-agnostic way to declare the exact same kind of `Field`:
bare `field<R>(jsonKey)`, with no type argument for `M` at all. See the
next section.

## Fast, `Function.apply`-free deserialization

Every `factory Model.fromJson(Json json) => $.call(json);` shown so far
goes through `ModelType.call` → `SerializableHelpers.fromJson`, which
loops over `schema.all` and invokes the model's constructor via
[`Function.apply`](https://api.dart.dev/dart-core/Function/apply.html).
That's the zero-extra-code path — nothing to write beyond the `Schema`
itself — but `Function.apply` is a *dynamic* call: Dart can't check its
argument types at compile time, can't inline it, and it costs more per
call than an ordinary one. Fine for the overwhelming majority of apps;
worth avoiding on a genuine hot path (parsing large arrays of models,
high-frequency payloads, etc.).

Every `Field<M, R>` also exposes `R readFrom(Json json)`, and there's a
bare, model-agnostic `field<R>(jsonKey)` that needs no `Schema` and no
model type in scope at all — together, they let you hand-write `fromJson`
as a normal constructor call, with no `Function.apply` anywhere. Mix in
`RecordedFields<M>` alongside `Serializable<M>` and `fields` (needed for
`toJson()`) is captured automatically from those exact same `field(...)`
calls — written once, only inside `fromJson`, nowhere else:

```dart
class User extends Equatable {
  final int id;
  final String name;
  final String? email;

  const User({required this.id, required this.name, this.email});

  @override
  List<Object?> get props => [id, name, email];
}

class UserModel extends User with Serializable<UserModel>, RecordedFields<UserModel> {
  // Private — recordFields(...) below is the only way in. See "Why the
  // real constructor needs to be private" further down.
  UserModel._({required super.id, required super.name, super.email});

  factory UserModel.fromJson(Json json) => recordFields(() => UserModel._(
    id: field<int>('user_id').readFrom(json),
    name: field<String>('full_name').readFrom(json),
    email: field<String?>('email_address').readFrom(json),
  ));
}
```

That's the whole class. No `fields` override, no `Field` list, no
`Schema`, no `ModelType` — and `props` needs nothing extra either,
since `UserModel` inherits it untouched from `User` (`Serializable<M>`
only ever contributes `toJson()`, never `props` — see
[Core concepts](#core-concepts) for why that split matters here
specifically).

### How the capture works

`recordFields(() => UserModel._(...))` opens a recording frame, then
evaluates `UserModel._(...)` — which means evaluating its arguments
first, exactly where every `field(...)` call above runs, registering
itself into that frame. `RecordedFields`'s own field initializer then
copies that frame onto the instance itself, as part of `UserModel._`'s
own construction — still *inside* `recordFields`, before its frame is
popped back off. The capture is why `fields` doesn't need declaring twice
— it's built from calls that already had to happen for `fromJson` to
work at all.

### Why the real constructor needs to be private

The capture above has to be **eager** — a plain field initializer, not
`late`. `late` only runs on first access, and `fields`/`toJson()` are
almost always accessed well after construction finishes, by which point
`recordFields`'s frame is long gone; only capturing *during* construction
sees the right frame. That correctness requirement has a cost: it runs
for *every* construction, including one that skips `recordFields`
entirely — `UserModel._(id: 1, name: 'Ada')` called directly (were it
public) has no frame to capture, and throws a clear `StateError` rather
than silently producing an empty or stale `fields`.

Making the real constructor private turns that mistake into a **compile
error** instead of a runtime one — nothing outside `UserModel`'s own file
can call `UserModel._(...)` directly, so the only path in really is
`fromJson`. If you need to build a model from values you already have in
hand, not from JSON — not through any factory at all — don't use
`RecordedFields` for it; see the next section for the alternative.

### If you'd rather keep a public constructor

`RecordedFields` trades a public raw constructor for zero `fields`
ceremony. If you want both a public constructor *and* no `Function.apply`
— accepting one `fields` declaration instead — skip `RecordedFields`
and declare it explicitly, still using the same bare `field(...)`:

```dart
class UserModel extends User with Serializable<UserModel> {
  const UserModel({required super.id, required super.name, super.email});

  static final _fields = <Field<Object?, Object?>>[
    field<int>('user_id'),
    field<String>('full_name'),
    field<String?>('email_address'),
  ];

  @override
  ListFieldOf get fields => _fields;

  factory UserModel.fromJson(Json json) => UserModel(
    id: field<int>('user_id').readFrom(json),
    name: field<String>('full_name').readFrom(json),
    email: field<String?>('email_address').readFrom(json),
  );
}
```

Here, each field's `(jsonKey, type)` genuinely is written twice —
`_fields` and `fromJson` each call `field(...)` once. That's the
unavoidable floor for this style: `fields` has to be derivable **without**
`fromJson` ever having run (so a directly-constructed `UserModel` still
serializes correctly), which means it can't be *discovered* by calling
`fromJson` — only `RecordedFields`, by making direct construction
impossible rather than merely unsupported, gets around writing it twice.
This is also, not coincidentally, exactly the failure mode `4.0.0` (see
the CHANGELOG) already fixed once for a different mechanism — a model
built by calling its own constructor directly, bypassing `fromJson`
entirely, getting an empty/stale `fields` instead of a clear error or
correct output.

### On error messages: `Object?` vs. the real model type

`field<R>(jsonKey)` (no `M`) is genuinely a `Field<Object?, R>` — there's
no model type in scope for it to know, so a `RequiredFieldError` or
`TypeConversionError` it throws reports `modelType: Object?` rather than
`UserModel`. Everything else about the error — `jsonKey`, the full
dotted `path`, the raw value — is identical either way, and is usually
the part that actually matters for debugging. If you want the real model
name in there too, declare the field through `Schema.field` or
`'key'.field<M, R>()` instead — both are registered into
`recordFields`/usable in a hand-declared `fields` list exactly the same
way as the bare `field<R>()`, so you can mix styles per field if only a
couple of fields need it.

### Composing with primary constructors

Dart's [primary constructors](https://dart.dev/language/primary-constructors)
fold a model's field declarations and constructor into one line, and
support named/`required`/defaulted parameters exactly like a normal
constructor does:

```dart
class Point(final int x, final int y);
class DatabaseIOSuccess({final String? path}) extends DatabaseIOResult;
```

> **Status check before you adopt this:** as of Dart 3.12/3.13, primary
> constructors are an **experimental preview**, gated behind the
> `primary-constructors` flag, with the old constructor syntax staying
> fully valid and supported. Confirm the current status on
> [dart.dev](https://dart.dev/language/primary-constructors) before
> depending on the exact syntax below — it's still settling.

Applied to `User` above, a primary constructor removes the `final int
id;`-style field declarations and the `const User({required this.id,
...})` line. (`UserModel`'s own constructor stays as a regular private
constructor either way — a primary constructor can be private too, but
there's nothing left to shrink on a constructor that already only forwards
to `super`.)

```dart
class User({required final int id, required final String name, final String? email})
    extends Equatable {
  @override
  List<Object?> get props => [id, name, email];
}
```

json_forge doesn't require primary constructors — every example in this
README works without them, on any Dart version this package supports.

## Parsing values

If you don't pass `parser:`, json_forge picks a default based on the
field's declared type `R`:

| `R`                      | Default parser                       |
| ------------------------ | ------------------------------------- |
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
(`toJson()` builds the intermediate `Map`s on the fly). Error paths
reported by `SerializationError` include the full dotted path, e.g.
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

## Fluent field builder

Prefer attaching a field's pieces one at a time instead of passing
`parser`/`serializer`/`nullable`/`getter` all at once? `field<R>(jsonKey)`
— with nothing else — returns a `Field` with just its `jsonKey` (and a
smart-inferred parser, same as always); each method below returns a new
`Field` with one more piece attached, and they can be chained in any
order. Works the same whether the starting `field<R>(jsonKey)` is the
bare top-level one or `Schema.field<R>(jsonKey)` inside a `Schema<M>` —
`FieldBuilderX` is a generic extension on `Field<M, R>` itself, for any
`M`:

```dart
field<int>('t_id').get((m) => m.id)

field<DeviceStatus>('device_status')
    .get((m) => m.status)
    .parse(enumOrFirst(DeviceStatus.values))
    .serialize(enumToJson)
```

- `.get(getter)` — attaches a getter. Takes it *positionally*
  (`.get((m) => m.id)`) — unlike `getter:` above, this is its own method
  with no other parameters to collide with.
- `.parse(parser)` — attaches a parser (including an `at(...)`-wrapped one).
- `.serialize(serializer)` — attaches a serializer.
- `.optional([nullable = true])` — overrides the `nullable` flag.

`Field` is immutable, so every one of these returns a *new* `Field`
rather than mutating the one it was called on.

## Serialization (`toJson`)

`toJson()` is built automatically from `fields` + `props`. For each field,
in order:

- If the field has a custom `serializer:`, that's used.
- Otherwise, the default recursive serializer handles it:

| Dart type                 | JSON representation                        |
| ------------------------- | ------------------------------------------- |
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

## Writing your own `copyWith`

json_forge deliberately stops at JSON ⇄ model mapping — it doesn't
generate `copyWith`. A model's `copyWith` is domain-layer, value-object
logic, and it's usually only a handful of lines once `toJson`/`fromJson`/
`props` already come for free:

```dart
class User extends Equatable with Serializable<User> {
  final int id;
  final String name;
  final String? email;

  const User(this.id, this.name, this.email);

  static const _unset = Object();

  User copyWith({int? id, String? name, Object? email = _unset}) => User(
    id ?? this.id,
    name ?? this.name,
    identical(email, _unset) ? this.email : email as String?,
  );

  static final $ = ModelType<User>(User.new, UserSchema());

  @override
  ListFieldOf get fields => $.schema.all;

  @override
  Props get props => [id, name, email];

  factory User.fromJson(Json json) => $.call(json);
}
```

The `Object? email = _unset` / `identical(...)` dance is only needed for
_nullable_ fields, where `null` is itself a meaningful value you want to
be able to set — a plain `email ?? this.email` can't distinguish "leave
this alone" from "set it to null". Non-nullable fields (`id`, `name`
above) don't need it — a plain `??` is enough.

## Error handling

| Error                 | Thrown when                                                                                                    |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
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
direct.toJson();                              // correct, not blank
direct == Terminal.fromJson(direct.toJson());  // true — round-trips correctly
```

## Gotchas

- **`Map<Enum, V>` fields need an explicit `.name`-based serializer.** The
  default serializer keys a `Map` by `.toString()`, and an `Enum`'s
  `.toString()` includes its type name (`"AccessLevel.write"`, not
  `"write"`). Left unfixed, that mismatched key won't be recognized by an
  `enumOr*` parser on the way back in, and `enumOrFirst`/`enumOrDefault`
  will silently substitute their fallback instead of throwing. Always pair
  an `Enum`-keyed `Map` field with:
  ```dart
  serializer: (map) => {for (final e in map.entries) e.key.name: e.value}
  ```
- **`String.field()`'s `getter` is a named argument**
  (`.field(getter: (m) => m.x)`), not positional — unlike the fluent
  `.get(...)` chain method (`field<R>(jsonKey).get((m) => m.x)`) and
  `Schema.field`'s own `getter:`, all of which behave slightly
  differently at the call site. Easy to mix up between the three.
- **`fields` and `props` order must match the constructor.** Same-length,
  wrong-order lists are only caught when they produce a differently-typed
  value in some slot; two same-typed fields swapped will not be caught
  automatically.
- **`Schema.all` (and a hand-rolled `fields` getter) should be `late
  final`, not `get`.** `toJson()` reads `fields` on every call — a plain
  `get all => [...]` rebuilds that `List` from scratch every single time
  instead of once. `late final all = [...]` computes it exactly once and
  returns the same `List` from then on.
- **`with Serializable<M>` alone doesn't satisfy `props`.** `Serializable`
  only provides `toJson()`; every model still needs `props` from
  somewhere — write it by hand, inherit it from a plain base class, or add
  `PropsFromGetters<M>` too. Forgetting this is a compile error (a
  missing implementation of `Equatable`'s abstract `props`), not a
  runtime surprise, so it's hard to miss.
- **`field<R>(jsonKey)` (the bare, model-agnostic top-level function) and
  `'jsonKey'.field<M, R>(...)` (the `String` extension) are different
  functions with the same name, resolved by call syntax** — `field<int>(
  'x')` vs. `'x'.field<M, int>()`. Easy to reach for the wrong one out of
  habit; both build the same kind of `Field`, differing only in whether
  `M` is `Object?` or something concrete.
- **`RecordedFields<M>` only sees `field(...)` calls made synchronously,
  directly inside the `recordFields(() => ...)` call that builds the
  instance.** A `field(...)` call made from an `await`-suspended callback,
  or from a helper function invoked from elsewhere for an unrelated
  reason while a recording happens to be active, either lands in the
  wrong frame or misses it entirely — this mechanism assumes (and every
  parser in this package already is) fully synchronous, non-async field
  reading. Keep every `field(...)` call for a `RecordedFields` model
  directly inside its own `recordFields(...)` closure.
- **`RecordedFields<M>` requires the real constructor to be private.** A
  public one compiles fine but throws `StateError` on every direct
  construction (`UserModel(...)`, skipping `recordFields`) — by design,
  loudly, rather than silently producing an empty `fields`. See
  [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization)
  for why the capture has to be eager, which is what makes this
  unavoidable.

## API reference

The package exports:

- `Field`, `Schema`, `ModelType`
- `Serializable`, `PropsFromGetters`, `RecordedFields`, `SerializableModelI`, `SerializableHelpers`
- `Json`, `JsonRaw`, `Parser<T>`, `Serializer<T>`, `FieldOf<M>`, `ListFieldOf`, `Props`
- Primitives: `intOr*`, `doubleOr*`, `numOr*`, `boolOr*`, `stringOr*`, `bigIntOr*`, `uriOr*`, `httpUriOrNull`
- Temporal: `dateTimeOr*`, `durationOr*`
- Enums: `enumOrNull`, `enumOrDefault`, `enumOrFirst`, `enumOrLast`, `enumOrThrow`, `enumToJson`
- Collections: `listOf`/`listOrNullOf`/`listOrThrowOf`, `setOf`/`setOrNullOf`/`setOrThrowOf`, `mapOf`/`mapOrNullOf`/`mapOrThrowOf`
- Nested models: `modelOf`, `modelOrNull`, `modelOrThrow`, `jsonObjectOrNull`, `jsonObjectOrEmpty`, `jsonObjectOrDefault`, `jsonObjectOrThrow`
- Nested paths: `at`, `readJsonPath`
- Combinators: `nullable`, `oneOf`, `mappedOrNull`, `mappedOrDefault`, `tryOrNull`, `withFallback`
- The fluent field builder: `.get`, `.parse`, `.serialize`, `.optional` (see [Fluent field builder](#fluent-field-builder))
- `Field.readFrom` — per-field, `Function.apply`-free deserialization (see [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization))
- `field<R>(jsonKey)` — bare, model-agnostic field declaration (`Field<Object?, R>`), and the `String.field<M, R>()` extension, its `M`-typed counterpart
- `recordFields`, `registerField`, `captureRecordedFields` — the mechanism behind `RecordedFields` (see [Fast, `Function.apply`-free deserialization](#fast-functionapply-free-deserialization))
- Errors: `SerializationError`, `RequiredFieldError`, `TypeConversionError`

See `example.dart` for a complete runnable model, and
`complex_serialization_test.dart` for a larger, multi-model example
covering deep nesting and multiple `props` styles.

## License

MIT — see `LICENSE` for details.
