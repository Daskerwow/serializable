// =============================================================================
// field_builder.dart
//
// Fluent alternative to passing parser/serializer/nullable/getter as named
// arguments to `field<R>(jsonKey, ...)` (Schema.field, model_type.dart) or
// `'jsonKey'.field<M, R>(...)` (FieldStringX, extension.dart) all at once —
// attach them one at a time instead:
//
//   field<int>('t_id').get((m) => m.id)
//
//   field<DeviceStatus>('device_status')
//       .get((m) => m.status)
//       .parse(enumOrFirst(DeviceStatus.values))
//       .serialize(enumToJson)
//
// `M` is whatever it already was on the `Field<M, R>` this chain starts
// from — inside a `Schema<M>`, that's already fixed by the class itself
// (see `Schema.field` in model_type.dart), so every step here only ever
// needs `<R>`, never `<M, R>`. Nothing new is inferred at any point in the
// chain: each method below is called on an already-fully-typed `Field<M,
// R>` and returns another one.
//
// ─── Why every method returns a *new* Field ──────────────────────────────────
// `Field` is immutable by design (see field.dart's header) — none of the
// methods below mutate `this`; each builds a fresh `Field<M, R>` carrying
// over everything already set, except the one aspect being replaced.
// `.get(...)`, `.serialize(...)`, and `.optional(...)` commute freely with
// each other and can be chained in any order. `.parse(...)` is the one
// exception worth knowing about — see its own doc comment for why it goes
// back through `buildField` instead of constructing a `Field` directly.
//
// ─── Why these are `get`/`parse`/`serialize`/`optional`, not `getter`/`parser`/... ─
// `Field` already declares real instance members named `jsonKey`,
// `nesting`, `parser`, `nullable`, `getter`, and `serializer` (see
// field.dart). An extension method can *never* win against an existing
// real member of the same name — Dart resolves `x.getter` to the actual
// `Field.getter` property first, full stop, no matter what an extension
// declares. Naming a fluent method `getter` doesn't shadow that property;
// it makes the extension method permanently unreachable, and
// `field<int>('id').getter((m) => m.id)` instead gets parsed as "read the
// `getter` property (an `R Function(M)?`, currently `null`), then
// unconditionally call it" — which fails at compile time exactly the way
// it sounds (`null` can't be invoked, and the property's own parameter
// type doesn't match a closure argument anyway). `get`/`parse`/`serialize`/
// `optional` are short verbs that simply don't appear anywhere in `Field`'s
// own member list, so there's nothing for them to collide with.
// =============================================================================

import '../extension.dart' show buildField;
import 'field.dart';
import 'types.dart';

extension FieldBuilderX<M, R> on Field<M, R> {
  /// Returns a new [Field], identical to `this` except for [getter] attached as
  /// its [Field.getter].
  ///
  /// ```dart
  /// field<int>('t_id').get((m) => m.id)
  /// ```
  Field<M, R> get(R Function(M) getter) => Field<M, R>(
    jsonKey: jsonKey,
    nesting: nesting,
    parser: parser,
    nullable: nullable,
    getter: getter,
    serializer: serializer,
  );

  /// Returns a new [Field], identical to `this` except for [serializer] attached as
  /// its [Field.serializer].
  ///
  /// ```dart
  /// field<Map<AccessLevel, String>>('access_keys')
  ///     .get((m) => m.tokens)
  ///     .parse(mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty))
  ///     .serialize((map) => {for (final e in map.entries) e.key.name: e.value})
  /// ```
  Field<M, R> serialize(Serializer<R> serializer) => Field<M, R>(
    jsonKey: jsonKey,
    nesting: nesting,
    parser: parser,
    nullable: nullable,
    getter: getter,
    serializer: serializer,
  );

  /// Returns a new [Field], identical to `this` except for its
  /// [Field.nullable] flag set to [nullable] (defaults to `true` — the common
  /// case of just marking a field optional) — overriding the `null is R`
  /// default.
  Field<M, R> optional([bool nullable = true]) => Field<M, R>(
    jsonKey: jsonKey,
    nesting: nesting,
    parser: parser,
    nullable: nullable,
    getter: getter,
    serializer: serializer,
  );

  /// Returns a new [Field] using [parser] as its [Field.parser].
  ///
  /// Unlike [get]/[serialize]/[optional] above, this goes back through
  /// [buildField] rather than constructing a [Field] directly — [parser]
  /// might be an `at(...)` wrapper, whose nesting path needs re-extracting
  /// from [parser] itself. [buildField] already does that; this method
  /// just hands it [parser] plus everything else already set on `this`:
  /// ```dart
  /// field<Grade>('primary_grade')
  ///     .get((m) => m.primaryGrade)
  ///     .parse(enumOrFirst(Grade.values))
  /// ```
  Field<M, R> parse(R Function(Object?) parser) => buildField<M, R>(
    jsonKey: jsonKey,
    parser: parser,
    serializer: serializer,
    nullable: nullable,
    getter: getter,
  );
}
