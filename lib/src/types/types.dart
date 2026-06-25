// =============================================================================
// types.dart
//
// Shared type aliases (typedefs) for the whole library.
//
// Conventions:
//   Parser<T>     — raw JSON value → T. Implementations should be "total"
//                   (never throw on normal use); to express "no value", use
//                   `T?` and return null.
//   Serializer<T> — Dart value T → JSON-compatible value.
//   Json          — alias for Map<String, Object?>.
//   JsonRaw       — alias for Map<String, dynamic>, for interop with APIs
//                   (e.g. dart:convert's jsonDecode) that hand back dynamic.
// =============================================================================

import 'field.dart';
import 'field_patch.dart';

/// `Object? → T`
///
/// Accepts an arbitrary JSON value and returns a typed [T]. Implementations
/// should be total — never throw on normal input. To express "no value",
/// make `T` nullable and return `null`.
typedef Parser<T> = T Function(Object? value);

/// `T → JSON-compatible Object?`
///
/// Converts a Dart value back into a JSON primitive, List, Map, or nested
/// object.
typedef Serializer<T> = Object? Function(T value);

/// Patch-builder function used by `copyWith` via `ModelBinder`.
///
/// Takes the field schema `$` and returns the list of changes to apply:
/// ```dart
/// sensor.copyWith(($) => [$.value.set(42.0)]);
/// ```
typedef FieldsBuilder<T> = Iterable<FieldPatch> Function(T $);

/// A field with its value type erased to `Object?`.
///
/// Used wherever the specific value type isn't known at compile time, e.g.
/// `List<FieldOf<User>>`.
typedef FieldOf<M> = Field<M, Object?>;

/// All field descriptors for model [T], in the exact order of its
/// constructor parameters.
///
/// The order matters: `SerializableHelpers.fromJson` passes parsed values as
/// *positional* arguments via `Function.apply`.
typedef ListFieldOf<T> = List<Field<T, Object?>>;

/// Field values in declaration order — feeds `Equatable.props`.
typedef Props = List<Object?>;

/// A standard JSON object: string keys, arbitrary values.
typedef Json = Map<String, Object?>;

/// A JSON object with `dynamic` values.
///
/// Useful when interacting with external APIs / `dart:convert` that return
/// `Map<String, dynamic>` instead of `Map<String, Object?>`.
typedef JsonRaw = Map<String, dynamic>;
