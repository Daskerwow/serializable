# Changelog

## 0.2.0

### Initial Release

A powerful, zero-code-generation serialization engine for Dart and Flutter. This version introduces a declarative, type-safe approach to handling JSON without the need for `build_runner`.

### Features

- **Zero Code-Gen Architecture**: Eliminate `.g.dart` files and wait times for `build_runner`. Models are defined purely in Dart.
- **Declarative Field Mapping**: Intuitive string extension API (`'json_key'.field(...)`) for clean, readable, and strongly-typed model definitions.
- **Total Parsers & Smart Casting**:
  - Graceful, non-throwing parsers following the strict `xOrNull`, `xOrDefault`, and `xOrThrow` naming conventions.
  - Automatic type coercion (e.g., `num` to `int`/`double`, Unix timestamps to `DateTime`, ISO-8601 strings).
- **Deep Nested Access**: The `at('key', parser)` combinator allows seamless reading and writing of deeply nested JSON structures without manual map traversal.
- **Advanced Collection Parsing**:
  - `listOf<T>()`, `setOf<T>()`, and `mapOf<K, V>()` provide recursive, strongly-typed parsing.
  - Precise, index-aware error reporting for failed collection elements.
- **Robust Enum Integration**: `enumOrDefault` and `enumOrNull` utilities for seamless string-to-enum mapping, with optional case-insensitive support.
- **Fluent `copyWith` & Patching**:
  - `ModelBinder` enables expressive updates using the `$.field.set(value)` syntax.
  - Built-in `undefined` sentinel safely distinguishes between "omit field" and "set to null" in `copyWith` operations.
- **State Management Friendly**:
  - `Serializable` mixin automatically generates `props` for `Equatable`.
  - Standardized, highly optimized `toJson()` and `fromJson()` patterns.

### Architecture & Reliability

- **Context-Rich Error Handling**: Typed exceptions (`SerializationError`, `RequiredFieldError`, `TypeConversionError`) provide full debugging context, including the exact dot-separated JSON path, model type, and raw value.
- **Type-Erasure Safety**: Internal type-erased wrappers ensure custom serializers work flawlessly even when field types are erased to `Object?` in generic lists.
- **Positional Constructor Invocation**: Uses `Function.apply` for fast, obfuscation-safe model instantiation without relying on slow named-argument dispatch.
- **Enhanced IDE IntelliSense**: Strict generic typing ensures excellent autocompletion and compile-time safety throughout the API.
