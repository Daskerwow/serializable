// =============================================================================
// FieldPatch
// =============================================================================

/// Transport object carrying a single field change for [ModelBinder.call].
///
/// Created exclusively via [FieldPatchX.set]:
/// ```dart
/// $.price.set(9.99)   // → FieldPatch('price', ['some_nesting'], 9.99)
/// ```
final class FieldPatch {
  const FieldPatch(this.jsonKey, this.nesting, this.value);

  /// JSON key of the field (the last component of the path).
  final String jsonKey;

  /// Path of ancestor keys (empty for top-level fields).
  final List<String> nesting;

  /// New value for the field.
  final Object? value;
}
