/// A powerful, zero-code-generation serialization engine for Dart & Flutter.
///
/// This library provides a declarative approach to model serialization and
/// deserialization without requiring code generation tools like build_runner.
/// It offers type safety and automatic type conversion.
///
/// The library's main building blocks:
/// - [Field]: a descriptor that maps one JSON key to one Dart property.
/// - [Serializable]: a mixin providing automatic `toJson()`.
/// - [PropsFromGetters]: opt-in mixin deriving `props` from field getters.
/// - [RecordedFields]: opt-in mixin deriving `fields` from the `field(...)`
///   calls already made inside `fromJson` — no separate field list, and no
///   restriction on how the model is otherwise constructed.
/// - [SerializableModelI]: the interface every serializable model implements.
/// - [SerializableHelpers]: the core engine — `fromJson` and the
///   serialization/path-traversal helpers the rest of this library is built
///   on.
///
/// Key features:
/// - Zero code generation (no .g.dart files)
/// - Declarative field definitions
/// - Type safety with smart type conversion
/// - Integration with Equatable for object comparison
/// - Recursive handling of nested models, lists, and maps
/// - Models can be constructed either via `fromJson` or via a perfectly
///   ordinary public constructor — this library never requires a private
///   constructor to work correctly.
///
/// `copyWith` is deliberately out of scope for this library — it maps JSON
/// ⇄ model only. Write `copyWith` by hand on your domain entity; see the
/// README's "Writing your own copyWith" section for a worked example.
library json_forge;

export 'src/serializable_model.dart';
export 'src/extension.dart';
export 'src/types/parser.dart';
export 'src/types/field.dart';
export 'src/types/types.dart';
