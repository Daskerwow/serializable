// =============================================================================
// recording.dart
//
// The "recording" mechanism behind `RecordedFields<M>` — lets a model's
// `fields` be derived automatically from the exact same `field(...)` calls
// its `fromJson` factory already makes, with no separate `fields` list
// declared anywhere.
//
// ─── What changed vs. the original per-instance design ──────────────────
// The original version captured a fresh copy of the recorded frame into
// *every instance* built via `recordFields(...)`, and threw a `StateError`
// the moment `fields` was accessed on an instance built any other way.
// That forced the model's real constructor to be private, so `fromJson`
// was the *only* legal way to create it — a serialization concern
// dictating how ordinary Dart construction is allowed to work.
//
// The fix follows from a simple observation: field descriptors don't
// actually depend on any particular *instance*. Every `Terminal`, no
// matter how it was built, has the exact same `fields` — same jsonKey,
// same parser, same serializer. So instead of capturing a copy per
// instance, this file now captures it **once per model Type**, into a
// static cache keyed by `M` — the first time `recordFields<M>(...)` runs
// for that type (in practice, the first time `Model.fromJson` is called
// anywhere in the program). [RecordedFields.fields] just reads that cache
// back — a cheap map lookup — regardless of whether *this* instance came
// from `fromJson` or from an entirely ordinary `Model(...)` call:
// ```dart
// final t1 = Terminal.fromJson(json);  // populates the cache for Terminal
// final t2 = Terminal(id: 1, title: 'x', status: ..., sensors: [], tokens: {});
// t2.toJson();                         // works — same cached fields as t1
// ```
//
// ─── How it works ───────────────────────────────────────────────────────
// `recordFields<M>(() => Model(...))` pushes a fresh, empty frame onto a
// stack, then evaluates `Model(...)` — which means evaluating its
// constructor arguments first (ordinary Dart call semantics: arguments are
// fully evaluated before the callee runs), which is exactly where every
// `field(...)` call in them runs, registering itself into whichever frame
// is currently on top. Once `build()` returns, that frame is stored under
// `_fieldsCache[M]` — keyed by the *static* type parameter `M` supplied to
// `recordFields<M>`, not by the constructed instance — and only then is it
// popped back off the stack.
//
// A plain stack (not a `Zone`) is enough because this is synchronous,
// single-isolate code end to end: `Parser<T>` is a plain synchronous
// function, so nothing here ever awaits mid-construction. The stack (not
// just a single "current frame" variable) is what makes nested models —
// a field whose parser is `modelOf(Address.fromJson)`, itself wrapped in
// its own `recordFields` — resolve correctly: the nested model's frame is
// pushed on top, captured, and popped, before control returns to the
// outer model's own `field(...)` calls, which keep landing in the outer
// frame exactly as before.
//
// ─── The one thing this still can't do ───────────────────────────────────
// [fieldsOf] throws a clear `StateError` — never silently returns `[]` —
// if `recordFields<M>` has genuinely never run for that type anywhere in
// the program yet. There's no reflection here and no code generation: the
// *only* source of truth for "what are this model's JSON fields" is the
// `field(...)` calls inside its own `fromJson`. In practice this is nearly
// always already satisfied — any program that round-trips JSON through a
// model calls `fromJson` at least once — but a model that's *only* ever
// constructed directly, whose `fromJson` is never invoked anywhere, will
// hit that error the first time something calls `.toJson()` on it. Call
// `Model.fromJson(...)` once (e.g. during startup, or in a test) to
// populate the cache, or drop [RecordedFields] for a model that's never
// really meant to round-trip JSON and declare `fields` by hand instead.
// =============================================================================

import 'field.dart';
import 'types.dart';

/// Stack of active recording frames. Only ever mutated synchronously, in
/// strict push/pop (LIFO) order, by [recordFields] and [registerField] —
/// see the file header for why that's sufficient without a `Zone`.
final List<List<Field<Object?, Object?>>> _recordingStack = [];

/// Per-model-*type* cache of captured field descriptors.
///
/// Populated by [recordFields] every time it runs for a given `M` (cheap
/// and idempotent to repeat); read by [fieldsOf] — i.e. by
/// [RecordedFields.fields] — from any instance of that type, regardless of
/// how that particular instance was constructed.
final Map<Type, ListFieldOf> _fieldsCache = {};

/// Registers [f] into the currently-active recording frame, if any — a
/// no-op if nothing is currently being recorded, so this costs nothing for
/// code that never calls [recordFields].
///
/// Called by `buildField` (extension.dart) for every [Field] it builds,
/// regardless of which entry point created it — the bare `field<R>(jsonKey)`,
/// `'jsonKey'.field<M, R>()`, all end up here.
void registerField(Field<Object?, Object?> f) {
  if (_recordingStack.isNotEmpty) _recordingStack.last.add(f);
}

/// Runs [build] with a fresh recording frame active, returning its result.
///
/// Every `field(...)` call made while evaluating [build] — most commonly,
/// every field of the model [build] constructs — lands in that frame; it's
/// then cached under model type [M] for [fieldsOf] to read back later, from
/// *any* instance of [M] — see [RecordedFields] (serializable_model.dart).
///
/// ```dart
/// factory UserModel.fromJson(Json json) => recordFields(() => UserModel(
///   id: field<int>('user_id').readFrom(json),
///   name: field<String>('full_name').readFrom(json),
/// ));
/// ```
M recordFields<M>(M Function() build) {
  _recordingStack.add(<Field<Object?, Object?>>[]);
  try {
    final result = build();
    _fieldsCache[M] = List.unmodifiable(_recordingStack.last);
    return result;
  } finally {
    _recordingStack.removeLast();
  }
}

/// Returns the cached field list for [modelType] — whatever the most
/// recent [recordFields] call for that type captured.
///
/// Called by [RecordedFields.fields] on every access (a cheap map lookup —
/// nothing is captured per-instance any more, so this is safe to call from
/// an instance built however you like).
///
/// Throws [StateError] if [recordFields] has never run for [modelType] —
/// see this file's header, "The one thing this still can't do".
ListFieldOf fieldsOf(Type modelType) {
  final cached = _fieldsCache[modelType];
  if (cached != null) return cached;
  throw StateError(
    '$modelType: no fields recorded for this type yet. RecordedFields '
    'derives a model\'s field list from the field(...) calls made inside '
    'recordFields(...) — typically inside its fromJson factory. Call '
    '$modelType.fromJson(...) at least once (anywhere in the program — '
    'during startup, in a test, whatever runs first) before calling '
    'toJson() on an instance built directly through the constructor.\n'
    'If $modelType is never meant to round-trip JSON at all, drop the '
    'RecordedFields mixin and override `fields` yourself instead.',
  );
}
