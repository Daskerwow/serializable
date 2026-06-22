/// A powerful, zero-code-generation serialization engine for Dart & Flutter.
///
/// This library provides a declarative approach to model serialization and deserialization
/// without requiring code generation tools like build_runner. It offers type safety,
/// automatic type conversion, and immutable copyWith functionality.
///
/// The library consists of two main components:
/// - [Field]: A descriptor that maps between JSON keys and Dart class properties
/// - [Serializable]: A mixin that provides automatic toJson() and props implementations
/// - [SerializableModelI]: An interface that all serializable models must implement
/// - [SerializableHelpers]: Core engine with fromJson and copyWith implementations
///
/// Key features:
/// - Zero code generation (no .g.dart files)
/// - Declarative field definitions
/// - Type safety with smart type conversion
/// - Powerful copyWith with undefined marker support
/// - Integration with Equatable for object comparison
/// - Recursive handling of nested models, lists, and maps
library serializable;

export 'src/serializable_model.dart';
export 'src/extension.dart';
export 'src/types/model_type.dart';
export 'src/types/parser.dart';
export 'src/types/field.dart';
export 'src/types/types.dart';
