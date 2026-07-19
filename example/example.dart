// ignore_for_file: avoid_print
import 'package:equatable/equatable.dart';
import 'package:json_forge/json_forge.dart';

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

enum Grade { a, b, c }

// ══════════════════════════════════════════════════════════════════════════════
// Sensor / SensorData — data class + RecordedFields subclass.
//
// Note the public constructor on `Sensor` itself — RecordedFields no
// longer needs a private one. `fields` is derived once, per *type*, from
// the field(...) calls inside `Sensor.fromJson`; every `Sensor` instance
// shares that same list, regardless of how it was built.
// ══════════════════════════════════════════════════════════════════════════════

class SensorData extends Equatable {
  SensorData({
    required this.uid,
    required this.temperature,
    required this.humidity,
    required this.isActive,
    required this.isCalibrated,
    required this.isFaulty,
    required this.isOffline,
    required this.primaryGrade,
    required this.secondaryGrade,
    required this.history,
  });

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
}

class Sensor extends SensorData
    with Serializable<Sensor>, RecordedFields<Sensor> {
  // Public — a plain, ordinary constructor. Nothing about RecordedFields
  // requires this to be private any more.
  Sensor({
    required super.uid,
    required super.temperature,
    required super.humidity,
    required super.isActive,
    required super.isCalibrated,
    required super.isFaulty,
    required super.isOffline,
    required super.primaryGrade,
    required super.secondaryGrade,
    required super.history,
  });

  factory Sensor.fromJson(Json json) => recordFields(
    () => Sensor(
      uid: field<String>('sensor_uid').readFrom(json),
      temperature: field<double>('temperature').readFrom(json),
      humidity: field<double>('humidity').readFrom(json),
      isActive: field<bool>('is_active').readFrom(json),
      isCalibrated: field<bool>('is_calibrated').readFrom(json),
      isFaulty: field<bool>('is_faulty').readFrom(json),
      isOffline: field<bool>('is_offline').readFrom(json),
      primaryGrade: field<Grade>(
        'primary_grade',
        parser: enumOrFirst(Grade.values),
      ).readFrom(json),
      secondaryGrade: field<Grade>(
        'secondary_grade',
        parser: enumOrFirst(Grade.values),
      ).readFrom(json),
      history: field<List<DateTime>>(
        'history_logs',
        parser: listOf(dateTimeOrEpoch),
      ).readFrom(json),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Terminal / TerminalData — nested Sensor list + an Enum-keyed Map serializer.
//
// Exactly the shape requested: a plain TerminalData data class, and a
// Terminal subclass with a normal public constructor *and* a fromJson
// factory, both fully supported side by side. toJson() is automatic.
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
      // The default serializer keys a Map by `.toString()` — an Enum's
      // includes its type name (`"AccessLevel.write"`, not `"write"`), so
      // this one needs its own `.name`-based serializer.
      tokens: field<Map<AccessLevel, String>>(
        'access_keys',
        parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
        serializer: (map) => {
          for (final e in map.entries) e.key.name: e.value,
        },
      ).readFrom(json),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// User / UserModel — alternative style: PropsFromGetters + hand-declared
// fields (no RecordedFields here), still with a public constructor. This
// was always supported; shown for contrast with the Terminal/Sensor style
// above.
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
    with Serializable<UserModel>, PropsFromGetters<UserModel> {
  UserModel({required super.id, required super.name, super.email});

  static final _idField = 'user_id'.field<UserModel, int>(
    getter: (m) => m.id,
  );
  static final _nameField = 'full_name'.field<UserModel, String>(
    getter: (m) => m.name,
  );
  static final _emailField = 'email_address'.field<UserModel, String?>(
    getter: (m) => m.email,
  );

  @override
  ListFieldOf get fields => [_idField, _nameField, _emailField];

  factory UserModel.fromJson(Json json) => UserModel(
    id: _idField.readFrom(json),
    name: _nameField.readFrom(json),
    email: _emailField.readFrom(json),
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

  // ─── via fromJson — this is also what populates Terminal's (and
  // Sensor's) cached `fields`, the first time it runs. ────────────────────
  final terminal = Terminal.fromJson(raw);
  print(
    'id: ${terminal.id}, title: ${terminal.title}, status: ${terminal.status}',
  );
  print('terminal.toJson(): ${terminal.toJson()}');
  print('round-trips: ${terminal == Terminal.fromJson(terminal.toJson())}');

  // ─── via a perfectly ordinary public constructor — the actual fix. ─────
  // No JSON in sight, no recordFields(...), no private constructor to
  // dodge. This used to throw StateError the moment `.toJson()` (or even
  // `.fields`) was touched; now it just works, because `fields` was
  // already cached for `Terminal` above.
  final manualTerminal = Terminal(
    id: 42,
    title: 'MANUAL',
    status: DeviceStatus.maintenance,
    sensors: const [],
    tokens: const {AccessLevel.read: 'manual_key'},
  );
  print('manualTerminal.toJson(): ${manualTerminal.toJson()}');

  final user = UserModel.fromJson({
    'user_id': 7,
    'full_name': 'Ada',
    'email_address': null,
  });
  print('user.toJson(): ${user.toJson()}');

  // Same story for UserModel — plain construction, no fromJson involved:
  final manualUser = UserModel(id: 8, name: 'Grace');
  print('manualUser.toJson(): ${manualUser.toJson()}');
}
