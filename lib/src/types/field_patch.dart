// =============================================================================
// field_patch.dart
//
// FieldPatch — a transport object describing "set this field to this value",
// produced by Field.set() and consumed by ModelBinder.call (the engine
// behind copyWith).
// =============================================================================

import 'field.dart';

/// A single field change, created exclusively via [FieldPatchX.set]:
/// ```dart
/// $.price.set(9.99)   // → FieldPatch('price', [], 9.99)
/// ```
final class FieldPatch {
  const FieldPatch(this.jsonKey, this.nesting, this.value);

  /// JSON key of the field (the last component of the path).
  final String jsonKey;

  /// Ancestor keys (empty for top-level fields).
  final List<String> nesting;

  /// The new value for the field.
  final Object? value;

  @override
  String toString() =>
      'FieldPatch($jsonKey, nesting: $nesting, value: $value)';
}

/// Adds [set] to every [Field], turning it into a [FieldPatch] factory.
extension FieldPatchX<M, R> on Field<M, R> {
  /// Creates a [FieldPatch] for this field with the given [value].
  ///
  /// Usage:
  /// ```dart
  /// model.copyWith(($) => [
  ///   $.price.set(9.99),
  ///   $.title.set('New title'),
  /// ]);
  /// ```
  FieldPatch set(R value) => FieldPatch(jsonKey, nesting, value);
}
