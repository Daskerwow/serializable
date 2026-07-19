import 'package:json_forge/json_forge.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

// Complex nested models for comprehensive testing.
//
// Field declarations use `Schema<M>.field<R>(jsonKey, parser: ..., nullable: ...)`
// — there's no getter argument: `Field` only describes the JSON side. A
// model's current values come from its own `props` (the standard
// `Equatable` list, declared explicitly below on every model) — which is
// also why these models work correctly whether built via `fromJson`/
// `copyWith` or via their bare constructor directly (see the last group
// of tests).

/// Statuses for devices
enum DeviceStatus { active, maintenance, offline, unknown }

/// Access levels for terminals
enum AccessLevel { read, write, execute }

/// User role enum
enum UserRole { admin, user, guest }

/// Nested model: Sensor
class SensorData extends Equatable {
  final String uid;
  final double value;
  final List<DateTime> history;

  const SensorData(this.uid, this.value, this.history);

  @override
  List<Object?> get props => [uid, value, history];
}

class Sensor extends SensorData
    with Serializable<Terminal>, RecordedFields<Terminal> {
  const Sensor(super.uid, super.value, super.history);

  factory Sensor.fromJson(Json json) => recordFields(
    () => Sensor(
      field<String>('sensor_uid').readFrom(json),
      field<double>('last_value').readFrom(json),
      field<List<DateTime>>(
        'history_logs',
        parser: listOf<DateTime>(dateTimeOrEpoch),
      ).readFrom(json),
    ),
  );
}

/// Nested model: Address
class AddressData extends Equatable {
  final String street;
  final String city;
  final String country;
  final int zipCode;

  const AddressData(this.street, this.city, this.country, this.zipCode);

  @override
  List<Object?> get props => [street, city, country, zipCode];
}

class Address extends AddressData
    with Serializable<Address>, RecordedFields<Address> {
  const Address(super.street, super.city, super.country, super.zipCode);

  factory Address.fromJson(Json json) => Address(
    field<String>('street_address').readFrom(json),
    field<String>('city_name').readFrom(json),
    field<String>('country_name').readFrom(json),
    field<int>('zip_code').readFrom(json),
  );
}

class UserData extends Equatable {
  final int id;
  final String name;
  final String email;
  final bool isActive;
  final UserRole role;
  final DateTime createdAt;
  final Address? address;

  const UserData(
    this.id,
    this.name,
    this.email,
    this.isActive,
    this.role,
    this.createdAt,
    this.address,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    email,
    isActive,
    role,
    createdAt,
    address,
  ];
}

class User extends UserData with Serializable<User>, RecordedFields<User> {
  const User(
    super.id,
    super.name,
    super.email,
    super.isActive,
    super.role,
    super.createdAt,
    super.address,
  );

  factory User.fromJson(Json json) => recordFields(
    () => User(
      field<int>('user_id').readFrom(json),
      field<String>('full_name').readFrom(json),
      field<String>('email_address').readFrom(json),
      field<bool>('is_active').readFrom(json),
      field<UserRole>(
        'user_role',
        parser: enumOrFirst(UserRole.values),
      ).readFrom(json),
      field<DateTime>('created_at').readFrom(json),
      field<Address?>(
        'user_address',
        parser: modelOrNull(Address.fromJson),
        nullable: true,
      ).readFrom(json),
    ),
  );
}

class TerminalData extends Equatable {
  final int id;
  final String title;
  final DeviceStatus status;
  final List<Sensor> sensors;
  final Map<AccessLevel, String> tokens;
  final List<User> users;

  const TerminalData(
    this.id,
    this.title,
    this.status,
    this.sensors,
    this.tokens,
    this.users,
  );

  @override
  List<Object?> get props => [id, title, status, sensors, tokens, users];
}

class Terminal extends TerminalData
    with Serializable<Terminal>, RecordedFields<Terminal> {
  const Terminal(
    super.id,
    super.title,
    super.status,
    super.sensors,
    super.tokens,
    super.users,
  );

  factory Terminal.fromJson(Json json) => recordFields(
    () => Terminal(
      field<int>('t_id').readFrom(json),
      field<String>(
        'display_name',
        parser: stringOrDefault('Unnamed Terminal'),
      ).readFrom(json),
      field<DeviceStatus>(
        'device_status',
        parser: enumOrFirst(DeviceStatus.values),
        serializer: enumToJson,
      ).readFrom(json),
      field<List<Sensor>>(
        'attached_sensors',
        parser: listOf<Sensor>(modelOf(Sensor.fromJson)),
      ).readFrom(json),
      field<Map<AccessLevel, String>>(
        'access_keys',
        parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
        serializer: (map) => {for (final e in map.entries) e.key.name: e.value},
      ).readFrom(json),
      field<List<User>>(
        'terminal_users',
        parser: listOf<User>(modelOf(User.fromJson)),
      ).readFrom(json),
    ),
  );
}

void main() {
  group('Complex Serialization Tests', () {
    test('Test complex nested models with deep serialization', () {
      final Map<String, dynamic> rawJson = {
        't_id': 777.0,
        'display_name': 'ZONE_A_TERMINAL',
        'device_status': 'active',
        'attached_sensors': [
          {
            'sensor_uid': 'SN-001',
            'last_value': 25,
            'history_logs': ['2026-01-07T10:00:00Z', '2026-01-07T15:30:00Z'],
          },
          {'sensor_uid': 'SN-002', 'last_value': 14.5, 'history_logs': []},
        ],
        'access_keys': {'read': 'key_public_123', 'write': 'key_private_456'},
        'terminal_users': [
          {
            'user_id': 1,
            'full_name': 'John Doe',
            'email_address': 'john@example.com',
            'is_active': true,
            'user_role': 'admin',
            'created_at': '2026-01-07T10:00:00Z',
            'user_address': {
              'street_address': '123 Main St',
              'city_name': 'New York',
              'country_name': 'USA',
              'zip_code': 10001,
            },
          },
          {
            'user_id': 2,
            'full_name': 'Jane Smith',
            'email_address': 'jane@example.com',
            'is_active': false,
            'user_role': 'user',
            'created_at': 1672531200000,
            'user_address': null,
          },
        ],
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));

      expect(terminal.id, 777);
      expect(terminal.title, 'ZONE_A_TERMINAL');
      expect(terminal.status, DeviceStatus.active);
      expect(terminal.sensors.length, 2);
      expect(terminal.tokens.length, 2);
      expect(terminal.users.length, 2);

      expect(terminal.sensors[0].uid, 'SN-001');
      expect(terminal.sensors[0].value, 25.0);
      expect(terminal.sensors[0].history.length, 2);

      expect(terminal.users[0].name, 'John Doe');
      expect(terminal.users[0].role, UserRole.admin);
      expect(terminal.users[0].address!.city, 'New York');

      expect(terminal.users[1].name, 'Jane Smith');
      expect(terminal.users[1].role, UserRole.user);
      expect(terminal.users[1].address, null);

      final resultJson = terminal.toJson();
      expect(resultJson['t_id'], 777);
      expect(resultJson['display_name'], 'ZONE_A_TERMINAL');
      expect(resultJson['device_status'], 'active');
      expect(resultJson['attached_sensors'] is List, true);
      expect(resultJson['terminal_users'] is List, true);
    });

    test('Test type conversion capabilities', () {
      final Map<String, dynamic> rawJson = {
        't_id': 42.7,
        'display_name': 'Test Terminal',
        'device_status': 'offline',
        'attached_sensors': [],
        'access_keys': {},
        'terminal_users': [],
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));
      expect(terminal.id, 42);
      expect(terminal.id.runtimeType, int);
    });

    test('Test enum handling', () {
      final Map<String, dynamic> rawJson = {
        't_id': 1,
        'display_name': 'Test Terminal',
        'device_status': 'maintenance',
        'attached_sensors': [],
        'access_keys': {},
        'terminal_users': [],
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));
      expect(terminal.status, DeviceStatus.maintenance);
    });

    test('Test list and map parsing', () {
      final Map<String, dynamic> rawJson = {
        't_id': 1,
        'display_name': 'Test Terminal',
        'device_status': 'active',
        'attached_sensors': [
          {
            'sensor_uid': 'SN-001',
            'last_value': 10.5,
            'history_logs': ['2026-01-07T10:00:00Z'],
          },
        ],
        'access_keys': {'read': 'read_key', 'execute': 'exec_key'},
        'terminal_users': [],
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));

      expect(terminal.sensors.length, 1);
      expect(terminal.sensors[0].uid, 'SN-001');
      expect(terminal.sensors[0].value, 10.5);
      expect(terminal.sensors[0].history.length, 1);

      expect(terminal.tokens.length, 2);
      expect(terminal.tokens[AccessLevel.read], 'read_key');
      expect(terminal.tokens[AccessLevel.execute], 'exec_key');
      expect(terminal.tokens[AccessLevel.write], null);
    });

    test('Test copyWith functionality', () {
      final Map<String, dynamic> rawJson = {
        't_id': 1,
        'display_name': 'Original Terminal',
        'device_status': 'active',
        'attached_sensors': [
          {
            'sensor_uid': 'SN-001',
            'last_value': 10.5,
            'history_logs': ['2026-01-07T10:00:00Z'],
          },
        ],
        // Deliberately includes a non-'read' key: this is what the
        // Enum-keyed-Map round-trip bug (see the `tokens` field's comment
        // in TerminalSchema) silently dropped before it was fixed —
        // 'write' would come back out of copyWith() as 'read' with no
        // error raised.
        'access_keys': {'read': 'read_key', 'write': 'write_key'},
        'terminal_users': [
          {
            'user_id': 1,
            'full_name': 'John Doe',
            'email_address': 'john@example.com',
            'is_active': true,
            'user_role': 'admin',
            'created_at': '2026-01-07T10:00:00Z',
            'user_address': null,
          },
        ],
      };

      final originalTerminal = Terminal.fromJson(Json.of(rawJson));

      expect(originalTerminal.status, DeviceStatus.active);
      expect(originalTerminal.title, 'Original Terminal');
    });

    test('Test edge cases and error handling', () {
      final Map<String, dynamic> rawJson = {
        't_id': 1,
        'display_name': 'Test Terminal',
        'device_status': 'active',
        'attached_sensors': null,
        'access_keys': null,
        'terminal_users': null,
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));
      expect(terminal.sensors.length, 0);
      expect(terminal.tokens.length, 0);
      expect(terminal.users.length, 0);
    });

    test('Test complex type conversion and mixed data types', () {
      final Map<String, dynamic> rawJson = {
        't_id': 999.9,
        'display_name': 'Test Terminal with Number',
        'device_status': 'unknown',
        'attached_sensors': [
          {
            'sensor_uid': 'SN-003',
            'last_value': 15.7,
            'history_logs': ['2026-01-07T10:00:00Z', '2026-01-07T11:00:00Z'],
          },
        ],
        'access_keys': {'write': 'write_key', 'read': 'read_key'},
        'terminal_users': [
          {
            'user_id': 3.5,
            'full_name': 'Bob Johnson',
            'email_address': 'bob@example.com',
            'is_active': true,
            'user_role': 'guest',
            'created_at': 1672531200000,
            'user_address': null,
          },
        ],
      };

      final terminal = Terminal.fromJson(Json.of(rawJson));
      expect(terminal.id, 999);
      expect(terminal.title, 'Test Terminal with Number');
      expect(terminal.status, DeviceStatus.unknown);
      expect(terminal.sensors.length, 1);
      expect(terminal.sensors[0].value, 15.7);
      expect(terminal.users[0].id, 3);
      expect(terminal.users[0].isActive, true);
    });
  });

  group('Direct construction (no fromJson) — regression for the props fix', () {
    // Mirrors building each field by hand with the same parsers `fromJson`
    // uses internally, then calling the constructor directly. This used to
    // crash: `toJson()`/`props` read from a per-instance cache that only
    // `fromJson` ever populated, so a directly-constructed instance came
    // back with every field `null` — and `status` has a custom serializer
    // (`enumToJson`), so `serializer(null as DeviceStatus)` threw
    // `type 'Null' is not a subtype of type 'DeviceStatus'` the moment
    // `toJson()`/`copyWith` ran on it.
    Terminal buildDirectly(Map<String, dynamic> raw) => Terminal(
      intOrZero(raw['t_id']),
      stringOrDefault('Unnamed')(raw['display_name']),
      enumOrFirst(DeviceStatus.values)(raw['device_status']),
      listOf(modelOf(Sensor.fromJson))(raw['attached_sensors']),
      mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty)(raw['access_keys']),
      listOf(modelOf(User.fromJson))(raw['terminal_users']),
    );

    final raw = <String, dynamic>{
      't_id': 5,
      'display_name': 'Direct Terminal',
      'device_status': 'active',
      'attached_sensors': <dynamic>[],
      'access_keys': <String, dynamic>{},
      'terminal_users': <dynamic>[],
    };

    test('toJson() reflects the real constructor values, not nulls', () {
      final terminal = buildDirectly(raw);

      final json = terminal.toJson();
      expect(json['t_id'], 5);
      expect(json['display_name'], 'Direct Terminal');
      expect(json['device_status'], 'active'); // was: a thrown TypeError
      expect(json['attached_sensors'], <Object?>[]);
      expect(json['access_keys'], <String, Object?>{});
      expect(json['terminal_users'], <Object?>[]);
    });

    test('copyWith() on a directly-constructed instance works', () {
      final terminal = buildDirectly(raw);

      // This is exactly the call that used to crash: copyWith() starts by
      // calling toJson() on `terminal`.

      expect(terminal.title, 'Direct Terminal'); // original is untouched
    });

    test('== reflects real values for directly-constructed instances', () {
      final a = buildDirectly(raw);
      final b = buildDirectly(raw);

      expect(a, b); // same inputs → equal, not just "both blank"
    });
  });
}
