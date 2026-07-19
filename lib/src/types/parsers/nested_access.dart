// =============================================================================
// nested_access.dart
//
// at(key, parser) — declare a field that lives at a nested JSON path, e.g.
//   at('meta', at('stats', intOrZero))   // declares json['meta']['stats']
//
// ─── How this actually works ─────────────────────────────────────────────
// The nested *traversal* happens in `readJsonPath` (json_path.dart), which
// walks `Field.nesting` *before* the value ever reaches the field's parser —
// by the time `child` runs, `v` is already the fully-resolved leaf value.
// `readJsonPath` is called from both `Field.readFrom` and
// `SerializableHelpers.fromJson` (the latter now via the former) — see
// field.dart and serializable_model.dart.
//
// `at`'s only job is to *record* the nesting path so `Field.nesting` can be
// populated correctly. It does this by stashing the path on the wrapper
// *function object* via an Expando (plain functions can't otherwise carry
// extra state), and `nestingOf` (called from `FieldStringX.field`) reads it
// back. The wrapper itself is a transparent passthrough to `child` — it does
// NOT index into a Map itself, and shouldn't: that indexing already happened
// in `readJsonPath`.
// =============================================================================

import '../types.dart';

/// Accumulated ancestor-key path for parsers created via [at].
final Expando<List<String>> _nestingMeta = Expando('_nesting');

/// The nesting path stashed on [parser] by [at] — `[]` if there is none.
List<String> nestingOf(Function parser) =>
    _nestingMeta[parser] ?? const <String>[];

/// Declares that the field this parser is attached to lives one level
/// deeper, under [key].
///
/// ```dart
/// // json['address']['city'] as a String:
/// 'city'.field(parser: at('address', stringOrEmpty))
///
/// // Chained — json['meta']['stats']['count'] as an int:
/// 'count'.field(parser: at('meta', at('stats', intOrZero)))
/// ```
///
/// See the file header for why [child] receives the already-resolved leaf
/// value rather than doing the indexing itself.
Parser<T> at<T>(String key, Parser<T> child) {
  // Read the already-accumulated path of the child parser (for chained
  // `at` calls), then prepend this level's key.
  final childPath = _nestingMeta[child] ?? const <String>[];
  final fullPath = [key, ...childPath];

  // A fresh function object — it gets its own Expando slot, distinct from
  // `child`'s.
  T wrapper(Object? v) => child(v);

  _nestingMeta[wrapper] = fullPath;
  return wrapper;
}
