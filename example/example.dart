// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

// ══════════════════════════════════════════════════════════════════════════════
// Sensor
// ══════════════════════════════════════════════════════════════════════════════

class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(this.uid, this.value, this.history);

  final String uid;
  final double value;
  final List<DateTime> history;

  static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  @override
  Props get props => [uid, value, history];

  factory Sensor.fromJson(Json json) => $.call(json);
  Sensor copyWith(FieldsBuilder<SensorSchema> updates) => $.bind(this)(updates);
}

final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');
  late final history = field('history_logs', parser: listOf(dateTimeOrEpoch));

  @override
  ListFieldOf<Sensor> get all => [uid, value, history];
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

  @override
  Props get props => [id, title, status, sensors, tokens];

  factory Terminal.fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalSchema> updates) =>
      $.bind(this)(updates);
}

final class TerminalSchema extends Schema<Terminal> {
  late final id = field<int>('t_id');
  late final title = field('display_name', parser: stringOrDefault('Unnamed'));
  late final status = field(
    'device_status',
    parser: enumOrFirst(DeviceStatus.values),
    // Optional here: `_serialize`'s default already handles `Enum` via
    // `.name`. Spelled out anyway to show how a custom serializer plugs in.
    serializer: enumToJson,
  );
  late final sensors = field(
    'attached_sensors',
    parser: listOf(modelOf(Sensor.fromJson)),
  );
  late final tokens = field(
    'access_keys',
    parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
    // Not optional: the default Map serializer keys by `.toString()`
    // ("AccessLevel.read"), not `.name` ("read") — this is what fixes that.
    serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
  );

  @override
  ListFieldOf<Terminal> get all => [id, title, status, sensors, tokens];
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  final raw = <String, Object?>{
    't_id': 777.0,
    'display_name': 'ZONE_A',
    'device_status': 'active',
    'attached_sensors': [
      {
        'sensor_uid': 'SN-001',
        'last_value': 25,
        'history_logs': ['2026-01-07T10:00:00Z', '2026-01-07T15:30:00Z'],
      },

      {'sensor_uid': 'SN-002', 'last_value': 14.5, 'history_logs': []},
    ],
    'access_keys': {'read': 'key_r', 'write': 'key_w'},
  };

  final t = Terminal.fromJson(raw);
  print('id: ${t.id}, title: ${t.title}, status: ${t.status}');

  final u = t.copyWith(
    ($) => [$.title.set('ZONE_B'), $.status.set(DeviceStatus.maintenance)],
  );

  print('updated: ${u.title} / ${u.status}, id same: ${u.id == t.id}');

  final s2 = t.sensors.first.copyWith(($) => [$.value.set(99.9)]);

  print(
    'sensor value: ${s2.value}, uid same: ${s2.uid == t.sensors.first.uid}',
  );

  print('round-trip: ${t == Terminal.fromJson(raw)}');
  print('changed: ${t == u}');

  // The toJson() method is implemented automatically without code generation!
  print(s2.toJson());
  print(t.toJson());

  // toJson()/== are built from `props`, so they work just as correctly on
  // a Terminal built by calling its constructor directly — no fromJson
  // involved at all — as long as `props` lists the same fields, in the
  // same order, as `fields` (and the constructor).
  final direct = Terminal(1, 'Direct', DeviceStatus.active, const [], const {});
  final directUpdated = direct.copyWith(($) => [$.title.set('Direct Updated')]);
  print('direct-construction toJson: ${direct.toJson()}');
  print('direct-construction copyWith: ${directUpdated.toJson()}');
}
