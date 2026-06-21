// =============================================================================
// errors.dart
//
// Typed errors that occur during JSON deserialization.
//
// Hierarchy:
//   Error
//   └── SerializationError          ← base class for all serialization errors
//         ├── RequiredFieldError    ← field is required, but turned out to be null/missing
//         └── TypeConversionError  ← value is present, but the type does not match
//
// Principles:
//   • All fields are final (immutable after creation).
//   • toString() returns a human-readable multi-line output.
//   • Subclasses extend toString() with their fields via super.
// =============================================================================

/// Base typed error that occurs during JSON deserialization.
///
/// Carries structured context:
///   - which model is being deserialized,
///   - which field caused the error,
///   - full path in JSON (dot-separated),
///   - raw value from JSON,
///   - original exception (if any).
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
  /// Includes all nesting levels via `at(...)`.
  final String path;

  /// Raw JSON value that caused the error (can be null).
  final Object? rawValue;

  /// Original exception, if the error was provoked by another exception.
  final Object? cause;

  /// Optional human-readable error message.
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

/// Thrown when a required field is missing in JSON or is null.
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

/// Thrown when a value is present, but cannot be cast
/// to the expected type.
///
/// Additionally stores:
///   - [expectedType] — the type that was expected,
///   - [actualType]   — the type that was received.
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

  /// The type that the parser expected.
  final Type expectedType;

  /// The actual type of the value received from JSON.
  final Type actualType;

  @override
  String toString() {
    // Extend the base output with information about the expected and actual types.
    final base = super.toString();
    return '$base\n'
        '  expected : $expectedType\n'
        '  actual   : $actualType';
  }
}
