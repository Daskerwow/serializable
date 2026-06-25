/// A zero-code-generation, declarative JSON (de)serialization engine for
/// Dart & Flutter.
///
/// This library provides a declarative approach to model serialization and
/// deserialization without requiring code-generation tools like
/// `build_runner`. It offers type safety, automatic type conversion, and
/// immutable `copyWith`.
///
/// ### Main components
/// - [Field] — a descriptor binding a JSON key to a Dart class property.
/// - [FieldSet] — the typed schema of fields for a model.
/// - [ModelType] / [ModelBinder] — bind a [FieldSet] to a constructor; the
///   engine behind `fromJson` and `copyWith`.
/// - [Serializable] — a mixin providing automatic `toJson()` and `props`.
/// - [SerializableModelI] — the interface every serializable model implements.
/// - [SerializableHelpers] — the low-level engine `fromJson`/`copyWith` build on.
/// - [SerializationError] / [RequiredFieldError] / [TypeConversionError] —
///   the typed error hierarchy raised during deserialization.
///
/// ### Highlights
/// - Zero code generation — no `.g.dart` files.
/// - Declarative field definitions, with smart default parsers for
///   primitive types.
/// - Type-safe `copyWith`, with two schema-declaration styles (named
///   properties or a concise list literal — see [FieldSet]).
/// - Integrates with `Equatable` for value equality.
/// - Recursive handling of nested models, lists, sets, and maps.
library;

export 'src/serializable_model.dart';
export 'src/extension.dart';
export 'src/errors.dart';
export 'src/types/types.dart';
export 'src/types/field.dart';
export 'src/types/field_patch.dart';
export 'src/types/model_type.dart';
export 'src/types/parser.dart';
