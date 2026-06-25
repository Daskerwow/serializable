// =============================================================================
// errors.dart
//
// Typed errors that occur during JSON deserialization.
//
// Hierarchy:
//   Error
//   └── SerializationError          ← base class for all serialization errors
//         ├── RequiredFieldError    ← field is required, but turned out null/missing
//         └── TypeConversionError   ← value is present, but the type doesn't match
//
// Principles:
//   • All fields are final (immutable after creation).
//   • toString() returns human-readable, multi-line output.
//   • Subclasses extend toString() with their own fields via super.
// =============================================================================

/// Base typed error raised during JSON deserialization.
///
/// Carries structured context:
///   - which model was being deserialized,
///   - which field caused the error,
///   - the full path in the JSON (dot-separated),
///   - the raw value from JSON,
///   - the original exception, if any.
///
/// Example output:
/// ```
/// SerializationError: [Terminal.t_id]
///   message  : required field is null or missing
///   path     : terminal_users.0.t_id
///   raw value: Null (null)
/// ```
final class SerializationError extends Error {
  SerializationError({
    required this.modelType,
    required this.fieldName,
    required this.path,
    this.rawValue,
    this.cause,
    this.message,
  });

  /// Dart type of the model being deserialized (e.g., `Terminal`).
  final Type modelType;

  /// Field name / JSON key where the error occurred.
  final String fieldName;

  /// Full dot-separated path to the field (e.g., `"terminal_users.0.t_id"`).
  /// Includes every nesting level introduced via `at(...)`.
  final String path;

  /// Raw JSON value that caused the error (may be `null`).
  final Object? rawValue;

  /// The original exception, if this error was provoked by another one.
  final Object? cause;

  /// Optional human-readable message.
  final String? message;

  @override
  String toString() {
    final buf = StringBuffer('SerializationError: [$modelType.$fieldName]\n');
    if (message != null) buf.writeln('  message  : $message');
    buf.writeln('  path     : $path');
    if (rawValue != null) {
      buf.writeln('  raw value: ${rawValue.runtimeType} ($rawValue)');
    }
    if (cause != null) buf.writeln('  cause    : $cause');
    return buf.toString().trimRight();
  }
}

// =============================================================================

/// Thrown when a required field is missing from the JSON, or is `null`.
///
/// Example output:
/// ```
/// SerializationError: [User.user_id]
///   message  : required field is null or missing
///   path     : user_id
/// ```
final class RequiredFieldError extends SerializationError {
  RequiredFieldError({
    required super.modelType,
    required super.fieldName,
    required super.path,
    super.rawValue,
  }) : super(message: 'required field is null or missing');
}

// =============================================================================

/// Thrown when a value is present, but can't be converted to the expected
/// type.
///
/// Additionally carries:
///   - [expectedType] — the type that was expected,
///   - [actualType]   — the type that was actually received.
///
/// Example output:
/// ```
/// SerializationError: [Order.amount]
///   message  : expected int, got String
///   path     : amount
///   raw value: String (bad_value)
///   expected : int
///   actual   : String
/// ```
final class TypeConversionError extends SerializationError {
  TypeConversionError({
    required super.modelType,
    required super.fieldName,
    required super.path,
    required this.expectedType,
    required this.actualType,
    super.rawValue,
    super.cause,
  }) : super(message: 'expected $expectedType, got $actualType');

  /// The type the parser expected.
  final Type expectedType;

  /// The actual runtime type of the value received from JSON.
  final Type actualType;

  @override
  String toString() {
    final base = super.toString();
    return '$base\n'
        '  expected : $expectedType\n'
        '  actual   : $actualType';
  }
}
