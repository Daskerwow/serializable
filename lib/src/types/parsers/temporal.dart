// =============================================================================
// temporal.dart
//
// Total parsers/serializers for DateTime and Duration.
// =============================================================================

import '../types.dart';
import 'primitives.dart' show intOrNull;

// =============================================================================
// DateTime
// =============================================================================

/// Smart `DateTime` parser: accepts ISO-8601 strings and Unix timestamps.
///
/// The seconds-vs-milliseconds threshold is `> 10000000000` — roughly the
/// year 2286 if read as seconds, or 1970 + ~116 days if read as
/// milliseconds — so real-world timestamps (a handful of digits short of
/// either extreme) land unambiguously on the right side.
@pragma('vm:prefer-inline')
DateTime? dateTimeOrNull(Object? v) => switch (v) {
  null => null,
  final DateTime dt => dt,
  final String s when s.isNotEmpty => DateTime.tryParse(s),
  final int n => _tsToDateTime(n),
  final num n => _tsToDateTime(n.toInt()),
  _ => null,
};

/// Picks the Unix-timestamp unit and converts to a UTC [DateTime].
@pragma('vm:prefer-inline')
DateTime _tsToDateTime(int n) {
  final ms = n > 10000000000 ? n : n * 1000;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

@pragma('vm:prefer-inline')
DateTime dateTimeOrEpoch(Object? v) =>
    dateTimeOrNull(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

@pragma('vm:prefer-inline')
DateTime dateTimeOrNow(Object? v) => dateTimeOrNull(v) ?? DateTime.now();

@pragma('vm:prefer-inline')
Parser<DateTime> dateTimeOrDefault(DateTime fallback) =>
    (Object? v) => dateTimeOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
DateTime dateTimeOrThrow(Object? v) =>
    dateTimeOrNull(v) ??
    (throw FormatException(
      'dateTimeOrThrow: expected a DateTime, an ISO-8601 string, or a Unix '
      'timestamp, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: `DateTime` → ISO-8601 string.
@pragma('vm:prefer-inline')
String dateTimeToJson(DateTime v) => v.toIso8601String();

/// Serializer: `DateTime` → Unix seconds.
@pragma('vm:prefer-inline')
int dateTimeToUnixSeconds(DateTime v) => v.millisecondsSinceEpoch ~/ 1000;

/// Serializer: `DateTime` → Unix milliseconds.
@pragma('vm:prefer-inline')
int dateTimeToUnixMillis(DateTime v) => v.millisecondsSinceEpoch;

// =============================================================================
// Duration
// =============================================================================

/// Parses [Duration] from a millisecond count (`int`/`num`), or a string
/// holding one.
@pragma('vm:prefer-inline')
Duration? durationOrNull(Object? v) => switch (v) {
  null => null,
  final int ms => Duration(milliseconds: ms),
  final num ms => Duration(milliseconds: ms.toInt()),
  final String s when s.trim().isNotEmpty => switch (intOrNull(s.trim())) {
    final int ms => Duration(milliseconds: ms),
    _ => null,
  },
  _ => null,
};

@pragma('vm:prefer-inline')
Duration durationOrZero(Object? v) => durationOrNull(v) ?? Duration.zero;

@pragma('vm:prefer-inline')
Parser<Duration> durationOrDefault(Duration fallback) =>
    (Object? v) => durationOrNull(v) ?? fallback;

@pragma('vm:prefer-inline')
Duration durationOrThrow(Object? v) =>
    durationOrNull(v) ??
    (throw FormatException(
      'durationOrThrow: expected a millisecond count or a parseable '
      'string, got ${v?.runtimeType} ($v)',
    ));

/// Serializer: `Duration` → milliseconds.
@pragma('vm:prefer-inline')
int durationToJson(Duration v) => v.inMilliseconds;
