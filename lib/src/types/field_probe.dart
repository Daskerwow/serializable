// =============================================================================
// field_probe.dart
//
// INTERNAL. Not exported from json_forge.dart — no model ever imports or
// touches this file directly.
//
// ─── Why dispatch is value-based, not Type-based ─────────────────────────────
// A field's *declared* type can be nullable (`double?`), but any *actual*
// non-null value is always a concrete, non-nullable runtime type — `25.0`
// is just a `double`, full stop. So `alternateValueFor` below switches on
// the real value's runtime type, never on the field's static `R`.
//
// ─── Why Expando is still needed, but only for one thing ─────────────────────
// Every other "alternate value" below is derived straight from the real
// value. The one piece of information that can't be recovered from a bare
// `Enum` instance is its *domain* — the full `.values` list — because an
// enum member carries no reference to its siblings. That domain is only
// known once, when a field is declared with `enumOrNull`/`Default`/
// `First`/`Last`/`Throw` (see enum_parser.dart's own Expando,
// `enumDomainOf`). `attachEnumDomain` re-tags it here, onto the `Field`
// object itself (which has a stable identity), right after `buildField`
// constructs it.
//
// ─── Why domain lookup uses a manual loop, not List.firstWhere ───────────────
// `enumDomainOf` returns `List<Enum>?`, but the object behind it is
// actually `List<DeviceStatus>` (or whatever concrete enum) — Dart's
// generics are reified, so `List<T>` assigned into an `Expando<List<Enum>>`
// slot keeps its *real* runtime element type. `List.firstWhere`'s
// `orElse` is typed by that real element type, not by the `List<Enum>`
// the variable is statically seen as — so `orElse: () => someEnumValue`
// (statically `Enum Function()`) fails its runtime type check against the
// expected `DeviceStatus Function()`. A plain `for` loop sidesteps this
// entirely: iteration only needs `Enum` (every enum implements it), no
// covariant-return closure is involved.
// =============================================================================

import 'field.dart';
import 'parser.dart' show enumDomainOf;
import 'parsers/primitives.dart';
import 'parsers/temporal.dart';

final Expando<List<Enum>> _enumDomains = Expando('_fieldEnumDomain');

/// Tags [field] with the value domain of the enum it was declared with —
/// called once, from `buildField()`, with the *original* user-supplied
/// [rawParser] (e.g. `enumOrFirst(DeviceStatus.values)`), before it gets
/// wrapped into `Field.parser`. No-op for non-enum fields.
void attachEnumDomain<M, R>(Field<M, R> field, Function? rawParser) {
  final domain = rawParser != null ? enumDomainOf(rawParser) : null;
  if (domain != null) _enumDomains[field] = domain;
}

/// The enum value domain tagged on [field] — `null` for any field that
/// isn't an enum declared via a built-in `enumOr*` combinator.
List<Enum>? enumDomainOfField<M, R>(Field<M, R> field) => _enumDomains[field];

/// First member of [domain] that isn't [current] — plain loop, not
/// `firstWhere(orElse:)`, precisely to avoid the reified-element-type
/// mismatch described in the file header. Returns [current] itself if
/// [domain] has no other member (shouldn't happen given the `length >= 2`
/// guard at the only call site, but kept total rather than throwing).
Enum _firstOtherThan(List<Enum> domain, Enum current) {
  for (final v in domain) {
    if (!identical(v, current)) return v;
  }
  return current;
}

/// A number far outside any plausible real-world value, injective in
/// [seed] — distinct seeds can never coerce to equal output below.
int _salt(int seed) => -(seed + 1) * 1000000007;

/// Produces a value "of the same kind" as [current] — guaranteed
/// different from [current], and, for unbounded types, guaranteed
/// different across distinct [seed]s too (that's what makes it safe to
/// seed a whole probe instance field-by-field — see `ModelBinder._buildProbe`).
///
/// Each unbounded-type branch is just an existing `Parser<T>` from
/// primitives.dart/temporal.dart — the same ones `extension.dart`'s
/// `_smartParse` already uses for ordinary JSON parsing — fed [_salt]
/// instead of real JSON input.
///
/// [enumDomain] — see [enumDomainOfField] — is only consulted when
/// [current] is an [Enum].
///
/// Returns [current] unchanged for kinds this library has no generator
/// for (nested models, `List`, `Map`, ...) — per [Schema.set]'s doc,
/// those are already virtually guaranteed to be distinct heap objects, so
/// no alternate is needed; the caller treats "unchanged" as "no generator".
Object? alternateValueFor(
  Object? current,
  int seed, {
  List<Enum>? enumDomain,
}) => switch (current) {
  null => null,
  final Enum e when enumDomain != null && enumDomain.length >= 2 =>
    _firstOtherThan(enumDomain, e),
  final bool b => !b,
  final double _ => doubleOrZero(_salt(seed)),
  final int _ => intOrZero(_salt(seed)),
  final String _ => stringOrEmpty(_salt(seed)),
  final DateTime _ => dateTimeOrEpoch(_salt(seed)),
  final Duration _ => durationOrZero(_salt(seed)),
  final Uri _ => uriOrEmpty('json-forge-probe:${_salt(seed)}'),
  final BigInt _ => bigIntOrZero(_salt(seed)),
  _ => current,
};
