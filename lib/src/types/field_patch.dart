// =============================================================================
// FieldPatch
// =============================================================================

/// Transport object carrying a single field change for [ModelBinder.call].
///
/// Comes in two flavors, picked by which constructor built it:
///
///   * **Resolved** (`FieldPatch(field, value)`) — built by
///     [FieldPatchX.set] (`$.fieldName.set(value)`) and `$.by<R>(jsonKey)
///     .set(value)`. [field] already *is* the target [Field] object; no
///     further resolution is needed.
///
///   * **Deferred** (`FieldPatch.deferred(selector, value)`) — built by
///     [Schema.set] (`$.set((m) => m.xyz, value)`). It carries a selector
///     closure instead of a [Field], and is resolved against a concrete
///     model instance later, inside [ModelBinder.call] — see
///     [ModelBinder._resolveSelector]. That's the only place the instance
///     is known, and comparing selector results against each getter's
///     result *on that instance* is what makes inline lambdas like
///     `(m) => m.title` finally match (Dart gives every literal a fresh
///     closure, so matching the closures themselves by `identical` never
///     works — see [Schema.set]).
///
/// [field] is untyped here (`Object?`, not `Field<M, Object?>`) purely so
/// [FieldPatch] can keep being used through the schema-only `FieldsBuilder<S>`
/// typedef without adding a second (model) type parameter everywhere. It's
/// always safe to cast back: every resolved patch wraps the real
/// `Field<M, R>` belonging to whichever model is being patched, and every
/// deferred patch is turned into a resolved one before any reader sees it.
/// [ModelBinder] is the sole reader and does exactly that cast.
final class FieldPatch {
  /// Resolved patch — [field] is the exact [Field] object to patch.
  const FieldPatch(this.field, this.value) : selector = null;

  /// Deferred patch — [selector] is `R Function(M)`; resolved later by
  /// [ModelBinder._resolveSelector] against a concrete instance.
  const FieldPatch.deferred(this.selector, this.value) : field = null;

  /// The exact [Field] this patch targets — the same object instance that
  /// appears in the owning [Schema]'s `all`. `null` for deferred patches
  /// (see [selector]).
  final Object? field;

  /// For deferred patches only: the selector closure passed to
  /// [Schema.set], typed as `R Function(M)` at the call site and stored
  /// here erased as `Object?`. `null` for resolved patches.
  final Object? selector;

  /// New value for the field.
  final Object? value;

  /// `true` if this patch still needs [ModelBinder._resolveSelector].
  bool get isDeferred => selector != null;
}
