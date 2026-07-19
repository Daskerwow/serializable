// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

enum Grade { a, b, c }

// ══════════════════════════════════════════════════════════════════════════════
// Sensor — single class, RecordedFields, hand-written props
// ══════════════════════════════════════════════════════════════════════════════

class Sensor extends Equatable
    with Serializable<Sensor>, RecordedFields<Sensor> {
  Sensor._(
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

  @override
  List<Object?> get props => [
    uid,
    temperature,
    humidity,
    isActive,
    isCalibrated,
    isFaulty,
    isOffline,
    primaryGrade,
    secondaryGrade,
    history,
  ];

  factory Sensor.fromJson(Json json) => recordFields(
    () => Sensor._(
      field<String>('sensor_uid').readFrom(json),
      field<double>('temperature').readFrom(json),
      field<double>('humidity').readFrom(json),
      field<bool>('is_active').readFrom(json),
      field<bool>('is_calibrated').readFrom(json),
      field<bool>('is_faulty').readFrom(json),
      field<bool>('is_offline').readFrom(json),
      field<Grade>(
        'primary_grade',
        parser: enumOrFirst(Grade.values),
      ).readFrom(json),
      field<Grade>(
        'secondary_grade',
        parser: enumOrFirst(Grade.values),
      ).readFrom(json),
      field<List<DateTime>>(
        'history_logs',
        parser: listOf(dateTimeOrEpoch),
      ).readFrom(json),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Terminal — nested Sensor list + an Enum-keyed Map serializer
// ══════════════════════════════════════════════════════════════════════════════

class TerminalData extends Equatable {
  TerminalData({
    required this.id,
    required this.title,
    required this.status,
    required this.sensors,
    required this.tokens,
  });

  final int id;
  final String title;
  final DeviceStatus status;
  final List<Sensor> sensors;
  final Map<AccessLevel, String> tokens;

  @override
  List<Object?> get props => [id, title, status, sensors, tokens];
}

class Terminal extends TerminalData
    with Serializable<Terminal>, RecordedFields<Terminal> {
  Terminal({
    required super.id,
    required super.title,
    required super.status,
    required super.sensors,
    required super.tokens,
  });

  factory Terminal.fromJson(Json json) => recordFields(
    () => Terminal(
      id: field<int>('t_id').readFrom(json),
      title: field<String>(
        'display_name',
        parser: stringOrDefault('Unnamed'),
      ).readFrom(json),
      status: field<DeviceStatus>(
        'device_status',
        parser: enumOrFirst(DeviceStatus.values),
      ).readFrom(json),
      sensors: field<List<Sensor>>(
        'attached_sensors',
        parser: listOf(modelOf(Sensor.fromJson)),
      ).readFrom(json),
      tokens: field<Map<AccessLevel, String>>(
        'access_keys',
        parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
        serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
      ).readFrom(json),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// User / UserModel — domain object + a thin JSON-capable subclass
// ══════════════════════════════════════════════════════════════════════════════

class User extends Equatable {
  const User({required this.id, required this.name, this.email});

  final int id;
  final String name;
  final String? email;

  @override
  List<Object?> get props => [id, name, email];
}

class UserModel extends User
    with Serializable<UserModel>, RecordedFields<UserModel> {
  UserModel._({required super.id, required super.name, super.email});

  factory UserModel.fromJson(Json json) => recordFields(
    () => UserModel._(
      id: field<int>('user_id').readFrom(json),
      name: field<String>('full_name').readFrom(json),
      email: field<String?>('email_address').readFrom(json),
    ),
  );
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
        'history_logs': [],
      },
    ],
    'access_keys': {'read': 'key_r', 'write': 'key_w'},
  };

  final terminal = Terminal.fromJson(raw);
  print(
    'id: ${terminal.id}, title: ${terminal.title}, status: ${terminal.status}',
  );
  print('terminal.toJson(): ${terminal.toJson()}');
  print('round-trips: ${terminal == Terminal.fromJson(terminal.toJson())}');

  final user = UserModel.fromJson({
    'user_id': 7,
    'full_name': 'Ada',
    'email_address': null,
  });
  print('user.toJson(): ${user.toJson()}');
}
