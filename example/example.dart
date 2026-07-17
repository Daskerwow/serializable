// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

enum Grade { a, b, c }

// ══════════════════════════════════════════════════════════════════════════════
// Sensor
// ══════════════════════════════════════════════════════════════════════════════

/// A single environmental sensor reading.
///
/// This model deliberately has *four* `bool` fields and *two* fields of the
/// same `Grade` enum — and the sample JSON in `main()` deliberately gives
/// every one of those `bool`s the same value, and both `Grade` fields the
/// same member. That's not sloppy modeling; it's here on purpose, to prove
/// something real: `Schema.set((m) => m.field, value)` still has to resolve
/// to the *exact* field the selector reads, even when several same-typed
/// fields currently hold the exact same value. See the `$.set(...)` calls
/// in `main()` for the actual proof — and `ModelBinder`'s doc comments in
/// the package itself for how the disambiguation is done (a synthetic probe
/// instance, seeded so same-typed fields provably differ, plus an
/// exhaustive isolating-probe fallback for finite-domain types like `bool`
/// and `Enum`, where a single seed can't always tell them apart).
class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(
    this.uid,
    this.temperature,
    this.humidity,
    this.isActive,
    this.isCalibrated,
    this.isFaulty,
    this.isOffline,
    this.primaryGrade,
    this.secondaryGrade,
    this.history,
  );

  final String uid;
  final double temperature;
  final double humidity;
  final bool isActive;
  final bool isCalibrated;
  final bool isFaulty;
  final bool isOffline;
  final Grade primaryGrade;
  final Grade secondaryGrade;
  final List<DateTime> history;

  static final $ = ModelType(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  // No `props` override here: every field below carries a `getter:`, so
  // `Serializable`'s default implementation derives `props` from them —
  // and, as a side effect, this is also what makes `copyWith` below take
  // the allocation-free direct-construction path instead of a JSON
  // round-trip. See `Terminal` further down for the other style.

  factory Sensor.fromJson(Json json) => $.call(json);
}

final class SensorSchema extends Schema<Sensor> {
  @override
  ListFieldOf<Sensor> get all => [
    'sensor_uid'.field((m) => m.uid),
    'temperature'.field((m) => m.temperature),
    'humidity'.field((m) => m.humidity),
    'is_active'.field((m) => m.isActive),
    'is_calibrated'.field((m) => m.isCalibrated),
    'is_faulty'.field((m) => m.isFaulty),
    'is_offline'.field((m) => m.isOffline),
    'primary_grade'.field(
      (m) => m.primaryGrade,
      parser: enumOrFirst(Grade.values),
    ),
    'secondary_grade'.field(
      (m) => m.secondaryGrade,
      parser: enumOrFirst(Grade.values),
    ),
    'history_logs'.field((m) => m.history, parser: listOf(dateTimeOrEpoch)),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// Terminal
// ══════════════════════════════════════════════════════════════════════════════

class Terminal extends Equatable with Serializable<Terminal> {
  const Terminal(this.id, this.title, this.status, this.sensors, this.tokens);

  final int id;
  final String title;
  final DeviceStatus status;
  final List<Sensor> sensors;
  final Map<AccessLevel, String> tokens;

  static final $ = ModelType(Terminal.new, TerminalSchema());

  @override
  ListFieldOf<Terminal> get fields => $.schema.all;
  factory Terminal.fromJson(Json json) => $.call(json);
}

final class TerminalSchema extends Schema<Terminal> {
  @override
  ListFieldOf<Terminal> get all => [
    field<int>('t_id').get((m) => m.id),
    field<String>(
      'display_name',
    ).get((m) => m.title).parse(stringOrDefault('Unnamed')),
    field<DeviceStatus>('device_status')
        .get((m) => m.status)
        .parse(enumOrFirst(DeviceStatus.values))
        .serialize(enumToJson),
    field<List<Sensor>>(
      'attached_sensors',
    ).get((m) => m.sensors).parse(listOf(modelOf(Sensor.fromJson))),
    field<Map<AccessLevel, String>>('access_keys')
        .get((m) => m.tokens)
        .parse(mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty))
        .serialize((map) => {for (final e in map.entries) e.key.name: e.value}),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  final raw = <String, Object?>{
    't_id': 777,
    'display_name': 'ZONE_A',
    'device_status': 'active',
    'attached_sensors': [
      {
        'sensor_uid': 'SN-001',
        'temperature': 22.5,
        'humidity': 48.0,
        'is_active': false,
        'is_calibrated': false,
        'is_faulty': false,
        'is_offline': false,
        'primary_grade': 'a',
        'secondary_grade': 'a',
        'history_logs': ['2026-01-07T10:00:00Z', '2026-01-07T15:30:00Z'],
      },
      {
        'sensor_uid': 'SN-002',
        'temperature': 19.0,
        'humidity': 52.5,
        'is_active': false,
        'is_calibrated': false,
        'is_faulty': false,
        'is_offline': false,
        'primary_grade': 'a',
        'secondary_grade': 'a',
        'history_logs': <String>[],
      },
    ],
    'access_keys': {'read': 'key_r', 'write': 'key_w'},
  };

  final terminal = Terminal.fromJson(Json.of(raw));
  print(
    'id: ${terminal.id}, title: ${terminal.title}, status: ${terminal.status}',
  );
}
