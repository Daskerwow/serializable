// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

enum Greed { boss, user }

// ══════════════════════════════════════════════════════════════════════════════
// Sensor
// ══════════════════════════════════════════════════════════════════════════════

class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(
    this.uid,
    this.value,
    this.line,
    this.sore,
    this.space,
    this.krope,
    this.fillipe,
    this.boss1,
    this.boss2,
    this.history,
  );

  final String uid;
  final double value;
  final double line;
  final bool sore;
  final bool space;
  final bool krope;
  final bool fillipe;
  final Greed boss1;
  final Greed boss2;
  final List<DateTime> history;

  static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  factory Sensor.fromJson(Json json) => $.call(json);
  Sensor copyWith(FieldsBuilder<SensorSchema> updates) => $.bind(this)(updates);
}

final class SensorSchema extends Schema<Sensor> {
  @override
  ListFieldOf<Sensor> get all => [
    'sensor_uid'.field((m) => m.uid),
    'last_value'.field((m) => m.value),
    'line_value'.field((m) => m.line),
    'sore'.field((m) => m.sore),
    'space'.field((m) => m.space),
    'krope'.field((m) => m.krope),
    'fillipe'.field((m) => m.fillipe),
    'boos1'.field((m) => m.boss1, parser: enumOrFirst(Greed.values)),
    'boos2'.field((m) => m.boss2, parser: enumOrFirst(Greed.values)),
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

  static final $ = ModelType<Terminal, TerminalSchema>(
    Terminal.new,
    TerminalSchema(),
  );

  @override
  ListFieldOf<Terminal> get fields => $.schema.all;

  factory Terminal.fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalSchema> updates) =>
      $.bind(this)(updates);
}

final class TerminalSchema extends Schema<Terminal> {
  @override
  ListFieldOf<Terminal> get all => [
    't_id'.field((m) => m.id),
    'display_name'.field((m) => m.title, parser: stringOrDefault('Unnamed')),
    'device_status'.field(
      (m) => m.status,
      parser: enumOrFirst(DeviceStatus.values),
      serializer: enumToJson,
    ),
    'attached_sensors'.field(
      (m) => m.sensors,
      parser: listOf(modelOf(Sensor.fromJson)),
    ),
    'access_keys'.field<Terminal, Map<AccessLevel, String>>(
      (m) => m.tokens,
      parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
      serializer: (map) => {
        for (final MapEntry(:key, :value) in map.entries) key.name: value,
      },
    ),
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
        'last_value': 25.0,
        'line_value': 25.0,
        'sore': false,
        'space': false,
        'krope': false,
        'fillipe': false,
        'boos1': 'boss',
        'boos2': 'boss',
        'history_logs': ['2026-01-07T10:00:00Z', '2026-01-07T15:30:00Z'],
      },

      {
        'sensor_uid': 'SN-002',
        'last_value': 14.5,
        'line_value': 189.0,
        'sore': false,
        'space': false,
        'krope': false,
        'fillipe': false,
        'boos1': 'boss',
        'boos2': 'boss',
        'history_logs': [],
      },
    ],
    'access_keys': {'read': 'key_r', 'write': 'key_w'},
  };

  final t = Terminal.fromJson(raw);
  print('id: ${t.id}, title: ${t.title}, status: ${t.status}');

  final u = t.copyWith(
    ($) => [
      $.set((m) => m.title, 'ZONE_B'),
      $.set((m) => m.status, DeviceStatus.maintenance),
    ],
  );
  // Terminal's fields don't declare `getter:`, so this copyWith went through
  // the JSON round-trip path: toJson() -> writeDeep() -> fromJson() ->
  // every parser (stringOrDefault, enumOrFirst, ...) ran again, even for
  // `sensors` and `tokens`, which weren't touched.
  print('updated: ${u.title} / ${u.status}, id same: ${u.id == t.id}');

  final s2 = t.sensors.first.copyWith(($) => [$.set((m) => m.value, 99.9)]);
  // Every field in SensorSchema has a `getter:`, so this copyWith skipped
  // JSON entirely: `uid` and `history` were read straight off the current
  // Sensor via their getters, `value` came from the patch as-is (already a
  // typed `double`, no re-parsing needed), and Sensor.new was called
  // directly with the three resulting positional arguments.

  print(
    'sensor value: ${s2.value}, uid same: ${s2.uid == t.sensors.first.uid}',
  );

  final s3 = t.sensors.first.copyWith(
    ($) => [
      $.set((m) => m.line, 139.0),
      $.set((m) => m.space, true),
      $.set((m) => m.krope, false),
      $.set((m) => m.boss2, Greed.user),
    ],
  );
  print(
    'sensor value: ${s3.value}, line: ${s3.line}, space ${s3.space} krope ${s3.krope}',
  );

  print('round-trip: ${t == Terminal.fromJson(raw)}');
  print('changed: ${t == u}');

  // The toJson() method is implemented automatically without code generation!
  print(s3.toJson());
  print(s2.toJson());
  print(t.toJson());

  // toJson()/== are built from `props`, so they work just as correctly on
  // a Terminal built by calling its constructor directly — no fromJson
  // involved at all — as long as `props` lists the same fields, in the
  // same order, as `fields` (and the constructor).
  final direct = Terminal(1, 'Direct', DeviceStatus.active, const [], const {});
  final directUpdated = direct.copyWith(
    ($) => [$.set((m) => m.title, 'Direct Updated')],
  );
  print('direct-construction toJson: ${direct.toJson()}');
  print('direct-construction copyWith: ${directUpdated.toJson()}');
}
