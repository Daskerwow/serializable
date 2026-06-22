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

  // M is always explicit — Dart cannot infer it from a positional constructor.
  static final $ = ModelType<Sensor, SensorFields>(Sensor.new, SensorFields());

  @override
  List<FieldOf<Sensor>> get fields => $.fields.all;

  static Sensor fromJson(Json json) => $.call(json);

  Sensor copyWith(Iterable<FieldPatch> Function(SensorFields $) updates) =>
      $.bind(this)(updates);
}

final class SensorFields extends FieldSet<Sensor> {
  final uid = 'sensor_uid'.field<Sensor, String>((m) => m.uid);
  final value = 'last_value'.field<Sensor, double>((m) => m.value);
  final history = 'history_logs'.field<Sensor, List<DateTime>>(
    (m) => m.history,
    parser: listOf(dateTimeOrEpoch),
  );

  @override
  late final all = <FieldOf<Sensor>>[uid, value, history];
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

  static final $ = ModelType<Terminal, TerminalFields>(
    Terminal.new,
    TerminalFields(),
  );

  @override
  List<FieldOf<Terminal>> get fields => $.fields.all;

  static Terminal fromJson(Json json) => $.call(json);

  Terminal copyWith(Iterable<FieldPatch> Function(TerminalFields $) updates) =>
      $.bind(this)(updates);
}

final class TerminalFields extends FieldSet<Terminal> {
  final id = 't_id'.field<Terminal, int>((m) => m.id, parser: intOrZero);
  final title = 'display_name'.field<Terminal, String>(
    (m) => m.title,
    parser: (v) {
      final s = stringOrEmpty(v);
      return s.isNotEmpty ? s : 'Unnamed';
    },
  );
  final status = 'device_status'.field<Terminal, DeviceStatus>(
    (m) => m.status,
    parser: enumOrDefault(DeviceStatus.values),
    serializer: enumToJson,
  );
  final sensors = 'attached_sensors'.field<Terminal, List<Sensor>>(
    (m) => m.sensors,
    parser: listOf(modelOf(Sensor.fromJson)),
  );
  final tokens = 'access_keys'.field<Terminal, Map<AccessLevel, String>>(
    (m) => m.tokens,
    parser: mapOf(enumOrDefault(AccessLevel.values), stringOrEmpty),
    serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
  );

  @override
  late final all = <FieldOf<Terminal>>[id, title, status, sensors, tokens];
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
}
