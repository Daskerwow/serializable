// =============================================================================
// recording.dart
//
// The "recording" mechanism behind `RecordedFields<M>` — lets a model's
// `fields` be captured automatically from the exact same `field(...)`
// calls its `fromJson` factory already makes, with no separate `fields`
// declaration written anywhere.
//
// ─── How it works ───────────────────────────────────────────────────────
// `recordFields(() => Model(...))` pushes a fresh, empty frame onto a
// stack, then evaluates `Model(...)` — which means evaluating its
// constructor arguments first (ordinary Dart call semantics: arguments
// are fully evaluated before the callee runs), which is exactly where
// every `field(...)` call in them runs, registering itself into whichever
// frame is currently on top. Only *then* does the constructor itself run
// — and `Model`'s `RecordedFields` mixin captures that same frame via a
// plain (non-`late`) field initializer, which Dart runs as part of
// `Model`'s own construction. That happens strictly *before*
// `recordFields`'s `finally` pops the frame back off, so the capture
// always sees the fully-populated, correct frame — copied out
// (`List.unmodifiable`) onto the instance itself before the frame
// disappears, so nothing about it depends on the stack surviving past
// construction.
//
// The capture *has* to be eager (a plain field initializer, not `late`):
// `late` only runs on first access, and `fields`/`toJson()` are almost
// always accessed well after construction, by which point the frame is
// long gone. Eager capture is what makes this correct at all — see
// `RecordedFields`'s doc comment (serializable_model.dart) for what that
// implies about how a `RecordedFields` model should be constructed.
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
// ─── The failure mode this can't remove ─────────────────────────────────
// A model built by calling its own constructor directly — not through
// `recordFields` — has no frame to capture: `captureRecordedFields` throws
// a clear `StateError` rather than silently returning an empty or stale
// `fields` list. This is a deliberate trade, not an oversight — see
// `RecordedFields`'s doc comment for the full reasoning, and for why that
// constructor should usually just be made private so this can't happen
// at all, rather than merely be detected when it does.
// =============================================================================

import 'field.dart';
import 'types.dart';

/// Stack of active recording frames. Only ever mutated synchronously, in
/// strict push/pop (LIFO) order, by [recordFields] and [registerField] —
/// see the file header for why that's sufficient without a `Zone`.
final List<List<Field<Object?, Object?>>> _recordingStack = [];

/// Registers [f] into the currently-active recording frame, if any — a
/// no-op if nothing is currently being recorded, so this costs nothing for
/// code that never calls [recordFields].
///
/// Called by `buildField` (extension.dart) for every [Field] it builds,
/// regardless of which entry point created it — the bare `field<R>(jsonKey)`,
/// `'jsonKey'.field<M, R>()`, or `Schema.field<R>(jsonKey)` all end up here.
void registerField(Field<Object?, Object?> f) {
  if (_recordingStack.isNotEmpty) _recordingStack.last.add(f);
}

/// Runs [build] with a fresh recording frame active, returning its result.
///
/// Every `field(...)` call made while evaluating [build] — most commonly,
/// every field of the model [build] constructs — lands in that frame; see
/// [RecordedFields] (serializable_model.dart) for how a model captures it.
///
/// ```dart
/// factory UserModel.fromJson(Json json) => recordFields(() => UserModel._(
///   id: field<int>('user_id').readFrom(json),
///   name: field<String>('full_name').readFrom(json),
/// ));
/// ```
M recordFields<M>(M Function() build) {
  _recordingStack.add(<Field<Object?, Object?>>[]);
  try {
    return build();
  } finally {
    _recordingStack.removeLast();
  }
}

/// Captures whatever's on top of the current recording stack, for
/// [modelType] — called by [RecordedFields]'s own field initializer, so
/// once per instance, eagerly, during construction.
///
/// Throws [StateError] if there's no active recording, i.e. this instance
/// wasn't built inside [recordFields] — see this file's header for why
/// that can't be relaxed into silently returning an empty list instead.
ListFieldOf captureRecordedFields(Type modelType) {
  if (_recordingStack.isEmpty) {
    throw StateError(
      '$modelType: no active field recording. RecordedFields captures the '
      'field(...) calls made while an instance is being constructed — but '
      'this instance was not built inside recordFields(...), so there was '
      'nothing to capture.\n'
      'Construct $modelType only through a factory that wraps its '
      'constructor call in recordFields(() => ...) — typically its '
      'fromJson — and make the real constructor private so nothing else '
      'can bypass that. If you need to build $modelType from values you '
      'already have in hand, not from JSON, drop the RecordedFields mixin '
      'for this model and declare `fields` explicitly instead.',
    );
  }
  return List.unmodifiable(_recordingStack.last);
}
