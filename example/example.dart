// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

class Sensor extends Equatable with Serializable<Sensor> {
  const Sensor(this.uid, this.value, this.history);

  final String uid;
  final double value;
  final List<DateTime> history;

  static final $ = ModelType<Sensor>(Sensor.new, [
    'sensor_uid'.field<Sensor, String>((m) => m.uid),
    'last_value'.field((m) => m.value, parser: doubleOrZero),
    'history_logs'.field((m) => m.history, parser: listOf(dateTimeOrEpoch)),
  ]);

  @override
  ListFieldOf<Sensor> get fields => $.all;
  static Sensor fromJson(Json json) => $.call(json);
}

// ══════════════════════════════════════════════════════════════════════════════
// Terminal — same idea, with an enum, a nested model list, and a Map field.
// Notice `name`/`jsonKey` decoupling falls out for free here: the Record's
// field is called `title`, the wire key is `display_name` — nothing extra
// needed to keep `copyWith` call sites independent of the JSON shape.
// ══════════════════════════════════════════════════════════════════════════════

typedef TerminalFields = (
  Field<Terminal, int> id,
  Field<Terminal, String> title,
  Field<Terminal, DeviceStatus> status,
  Field<Terminal, List<Sensor>> sensors,
  Field<Terminal, Map<AccessLevel, String>> tokens,
);

class Terminal extends Equatable with Serializable<Terminal> {
  const Terminal(this.id, this.title, this.status, this.sensors, this.tokens);

  final int id;
  final String title;
  final DeviceStatus status;
  final List<Sensor> sensors;
  final Map<AccessLevel, String> tokens;

  static final TerminalFields _fields = (
    't_id'.field((m) => m.id, parser: intOrZero),
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
    'access_keys'.field(
      (m) => m.tokens,
      parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
      serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
    ),
  );

  static final $ = ModelType<Terminal>(Terminal.new, [
    _fields.$1,
    _fields.$2,
    _fields.$3,
    _fields.$4,
    _fields.$5,
  ]);

  @override
  ListFieldOf<Terminal> get fields => $.all;

  static Terminal fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalFields> builder) =>
      $.bind(this, _fields)(builder);
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
    ],
    'access_keys': {'read': 'key_r', 'write': 'key_w'},
  };

  final t = Terminal.fromJson(raw);
  print('id: ${t.id}, title: ${t.title}, status: ${t.status}');

  // $.title / $.status are native Record field accesses — no string keys,
  // no custom lookup operator, nothing to misspell without the analyzer
  // catching it immediately.
  final u = t.copyWith(
    ($) => [$.$2.set('ZONE_B'), $.$3.set(DeviceStatus.maintenance)],
  );
  print('updated: ${u.title} / ${u.status}, id same: ${u.id == t.id}');

  final s2 = t.sensors.first;
  print(
    'sensor value: ${s2.value}, uid same: ${s2.uid == t.sensors.first.uid}',
  );
  print(s2.toJson());

  print('round-trip: ${t == Terminal.fromJson(raw)}');
  print('changed: ${t == u}');

  // toJson() is fully automatic — no code generation involved.
  print(t.toJson());
}
