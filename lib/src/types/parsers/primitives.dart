// =============================================================================
// primitives.dart
//
// Total parsers/serializers for Dart's basic scalar types: String, int,
// double, num, bool, BigInt, Uri.
//
// ─── Naming convention (applies to every parser file) ───────────────────────
//   xOrNull    — null on missing/incompatible input. Total (never throws).
//   xOrDefault — a chosen fallback instead of null. Total.
//   xOrZero / xOrEmpty / xOrFalse / ... — a fixed, type-appropriate default.
//   xOrThrow   — throws FormatException on missing/incompatible input. Use
//                only where an incorrect value is a real bug, not bad input.
// =============================================================================

import '../types.dart';

// =============================================================================
// String
// =============================================================================

/// Converts a value to [String], or returns `null`.
///
/// Accepted input: `null` → `null`; `String` → trimmed; `num`/`bool` → their
/// `.toString()`. Anything else (List, Map, custom objects) → `null` — this
/// is deliberate, so an accidental `Object` doesn't silently turn into
/// `"Instance of 'Foo'"`.
@pragma('vm:prefer-inline')
String? stringOrNull(Object? v) => switch (v) {
  null => null,
  final String s => s.trim(),
  final num n => n.toString(),
  final bool b => b.toString(),
  _ => null,
};

@pragma('vm:prefer-inline')
String stringOrEmpty(Object? v) => stringOrNull(v) ?? '';

@pragma('vm:prefer-inline')
Parser<String> stringOrDefault(String fallback) =>
    (Object? v) => stringOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
String stringOrThrow(Object? v) =>
    stringOrNull(v) ??
    (throw FormatException(
      'stringOrThrow: expected a non-null String, got ${v?.runtimeType} ($v)',
    ));

// =============================================================================
// int
// =============================================================================

@pragma('vm:prefer-inline')
int? intOrNull(Object? v) => switch (v) {
  null => null,
  final int n => n,
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()),
  final bool b => b ? 1 : 0,
  _ => null,
};

@pragma('vm:prefer-inline')
int intOrZero(Object? v) => intOrNull(v) ?? 0;

@pragma('vm:prefer-inline')
Parser<int> intOrDefault(int fallback) =>
    (Object? v) => intOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
int intOrThrow(Object? v) =>
    intOrNull(v) ??
    (throw FormatException(
      'intOrThrow: expected an int-compatible value, got ${v?.runtimeType} ($v)',
    ));

// =============================================================================
// double
// =============================================================================

@pragma('vm:prefer-inline')
double? doubleOrNull(Object? v) => switch (v) {
  null => null,
  final double n => n,
  final num n => n.toDouble(),
  final String s => double.tryParse(s.trim()),
  final bool b => b ? 1.0 : 0.0,
  _ => null,
};

@pragma('vm:prefer-inline')
double doubleOrZero(Object? v) => doubleOrNull(v) ?? 0.0;

@pragma('vm:prefer-inline')
Parser<double> doubleOrDefault(double fallback) =>
    (Object? v) => doubleOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
double doubleOrThrow(Object? v) =>
    doubleOrNull(v) ??
    (throw FormatException(
      'doubleOrThrow: expected a double-compatible value, got ${v?.runtimeType} ($v)',
    ));

// =============================================================================
// num
// =============================================================================

@pragma('vm:prefer-inline')
num? numOrNull(Object? v) => switch (v) {
  null => null,
  final num n => n,
  final String s => num.tryParse(s.trim()),
  final bool b => b ? 1 : 0,
  _ => null,
};

@pragma('vm:prefer-inline')
num numOrZero(Object? v) => numOrNull(v) ?? 0;

@pragma('vm:prefer-inline')
Parser<num> numOrDefault(num fallback) =>
    (Object? v) => numOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
num numOrThrow(Object? v) =>
    numOrNull(v) ??
    (throw FormatException(
      'numOrThrow: expected a num-compatible value, got ${v?.runtimeType} ($v)',
    ));

// =============================================================================
// BigInt
// =============================================================================

@pragma('vm:prefer-inline')
BigInt? bigIntOrNull(Object? v) => switch (v) {
  null => null,
  final num n => BigInt.from(n.toInt()),
  final String s => BigInt.tryParse(s.trim()),
  final bool b => b ? BigInt.one : BigInt.zero,
  _ => null,
};

@pragma('vm:prefer-inline')
BigInt bigIntOrZero(Object? v) => bigIntOrNull(v) ?? BigInt.zero;

@pragma('vm:prefer-inline')
Parser<BigInt> bigIntOrDefault(BigInt fallback) =>
    (Object? v) => bigIntOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
BigInt bigIntOrThrow(Object? v) =>
    bigIntOrNull(v) ??
    (throw FormatException(
      'bigIntOrThrow: expected a BigInt-compatible value, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: `BigInt` → string.
@pragma('vm:prefer-inline')
String bigIntToJson(BigInt v) => v.toString();

// =============================================================================
// bool
// =============================================================================

@pragma('vm:prefer-inline')
bool? boolOrNull(Object? v) => switch (v) {
  null => null,
  final bool b => b,
  final num n => n != 0,
  final String s => switch (s.toLowerCase().trim()) {
    'true' || '1' || 'yes' || 'y' || 'on' => true,
    'false' || '0' || 'no' || 'n' || 'off' => false,
    _ => null,
  },
  _ => null,
};

@pragma('vm:prefer-inline')
bool boolOrFalse(Object? v) => boolOrNull(v) ?? false;

@pragma('vm:prefer-inline')
bool boolOrTrue(Object? v) => boolOrNull(v) ?? true;

@pragma('vm:prefer-inline')
bool boolOrThrow(Object? v) =>
    boolOrNull(v) ??
    (throw FormatException(
      'boolOrThrow: expected a bool-compatible value, got ${v?.runtimeType} ($v)',
    ));

// =============================================================================
// Uri
// =============================================================================

/// Parses any syntactically valid URI from a string.
///
/// Need only absolute HTTP(S) URIs with a host? Use [httpUriOrNull].
@pragma('vm:prefer-inline')
Uri? uriOrNull(Object? v) => switch (stringOrNull(v)) {
  final String s when s.isNotEmpty => Uri.tryParse(s),
  _ => null,
};

/// Parses only absolute HTTP(S) URIs with a non-empty host.
///
/// Returns `null` for relative URIs, `mailto:`, `urn:`, etc. Use instead of
/// [uriOrNull] when the field must hold a real web address.
@pragma('vm:prefer-inline')
Uri? httpUriOrNull(Object? v) => switch (uriOrNull(v)) {
  final Uri u
      when (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty =>
    u,
  _ => null,
};

@pragma('vm:prefer-inline')
Uri uriOrEmpty(Object? v) => uriOrNull(v) ?? Uri();

@pragma('vm:prefer-inline')
Parser<Uri> uriOrDefault(Uri fallback) =>
    (Object? v) => uriOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
Uri uriOrThrow(Object? v) =>
    uriOrNull(v) ??
    (throw FormatException(
      'uriOrThrow: expected a valid URI string, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: `Uri` → string.
@pragma('vm:prefer-inline')
String uriToJson(Uri v) => v.toString();
