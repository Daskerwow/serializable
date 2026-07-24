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
    required this.jsonKey,
    required this.path,
    this.rawValue,
    this.cause,
    this.message,
  });

  /// Dart type of the model being deserialized (e.g., `Terminal`).
  final Type modelType;

  /// Field name / JSON key where the error occurred.
  final String jsonKey;

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
    final buf = StringBuffer('SerializationError: [$modelType.$jsonKey]\n');
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
    required super.jsonKey,
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
    required super.jsonKey,
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

// =============================================================================

/// Thrown from [SerializableHelpers._serialize] (the *toJson* / write
/// direction — the mirror image of [TypeConversionError], which fires on
/// the *fromJson* / read direction) when a field holds a value that isn't
/// JSON-safe and has no custom `serializer` to handle it.
///
/// Unlike the other errors in this file, [path] here is not a fixed
/// `Field.path` — it's built up during recursion through nested `Map`s and
/// `List`s, so it can point past the field itself and into exactly which
/// key or index inside it held the bad value (e.g.
/// `"metadata['error']"` or `"items[2]['nested']"`).
///
/// Example output:
/// ```
/// SerializationError: [LogsModel.metadata['error']]
///   message  : value is not JSON-serializable
///   path     : metadata['error']
///   raw value: EditableArguments (Instance of 'EditableArguments')
/// ```
final class UnserializableValueError extends SerializationError {
  UnserializableValueError({
    required super.modelType,
    required String fieldPath,
    required Object value,
  }) : super(
         jsonKey: fieldPath,
         path: fieldPath,
         rawValue: value,
         message:
             'value is not JSON-serializable — add a custom `serializer:` '
             'for this field in its Schema, or make sure it only ever '
             'holds JSON-safe values (num, String, bool, null, DateTime, '
             'Duration, Uri, BigInt, Enum, List, Set, Map, or a '
             'SerializableModelI). If only a text representation is '
             'needed, call `.toString()` on the value before storing it.',
       );
}
