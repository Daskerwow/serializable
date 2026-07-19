// =============================================================================
// json_path.dart
//
// One small piece of shared plumbing, used by the read direction:
//   - Field.readFrom (field.dart) — one field at a time, no Function.apply.
//   - SerializableHelpers.fromJson (serializable_model.dart) — the whole
//     `fields` list at once, via Function.apply. fromJson is implemented
//     *in terms of* Field.readFrom (one call per field) rather than
//     duplicating this walk itself — see serializable_model.dart's header.
//
// Still required: this is what makes `at('meta', ...)` nested field access
// work at all. Every `Field.nesting` path — populated by `at()` in
// nested_access.dart — is walked here before the value ever reaches a
// field's own parser. Without this file, `at(...)` would have nothing to
// resolve against and nested JSON reads would break.
//
// Lives in its own file, at the same level as types.dart, specifically so
// `field.dart` can use it without importing `serializable_model.dart` (that
// import would run the wrong way — `serializable_model.dart` already
// imports `types/types.dart`, and `Field` is meant to be a leaf type other
// things build on, not the other way around).
// =============================================================================

import 'types.dart';

/// Reads a value from [json] by the composite path `[...nesting, key]`.
///
/// Each [nesting] step is a key of a nested `Map`. If the value at any step
/// isn't a `Map`, returns `null` — the field is treated as missing rather
/// than throwing, exactly as a genuinely-absent top-level key would be.
///
/// Example: `nesting = ['meta', 'stats']`, `key = 'count'`
///   → reads `json['meta']['stats']['count']`
///
/// Descends via [Map.cast] rather than [Map.from]: [Map.cast] returns an
/// O(1) typed *view* over the same underlying map, not a copy. Every field
/// sharing a nesting prefix (e.g. six fields all declared via
/// `at('statistics', ...)`) calls this independently from the root — with a
/// real copy at each level, that's an O(map size) allocation paid again per
/// field per level, for a value that's discarded after reading exactly one
/// key out of it. A view has none of that cost: `current[step]` on a
/// `CastMap` only checks the type of the one value actually read, never
/// touches or duplicates the rest of the map's entries.
Object? readJsonPath(Json json, List<String> nesting, String key) {
  Json current = json;
  for (final step in nesting) {
    final next = current[step];
    if (next is! Map) return null;
    current = next.cast<String, Object?>();
  }
  return current[key];
}
