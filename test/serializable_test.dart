import 'package:serializable/serializable.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

// Complex nested models for comprehensive testing

/// Statuses for devices
enum DeviceStatus { active, maintenance, offline, unknown }

/// Access levels for terminals
enum AccessLevel { read, write, execute }

/// User role enum
enum UserRole { admin, user, guest }

/// Nested model: Sensor
class Sensor extends Equatable with Serializable<Sensor> {
  final String uid;
  final double value;
  final List<DateTime> history;

  const Sensor(this.uid, this.value, this.history);

  static final $ = ModelType<Sensor, SensorFields>(Sensor.new, SensorFields());

  @override
  ListFieldOf<Sensor> get fields => $.fields.all;

  factory Sensor.fromJson(Json json) => $.call(json);

  Sensor copyWith(FieldsBuilder<SensorFields> builder) => $.bind(this)(builder);
}

/// Fields
final class SensorFields extends FieldSet<Sensor> {
  final uid = 'sensor_uid'.field<Sensor, String>((m) => m.uid);
  final value = 'last_value'.field<Sensor, double>((m) => m.value);
  final history = 'history_logs'.field<Sensor, List<DateTime>>(
    (m) => m.history,
    parser: listOf<DateTime>(dateTimeOrEpoch),
  );

  @override
  ListFieldOf<Sensor> get all => [uid, value, history];
}

/// Nested model: Address
class Address extends Equatable with Serializable<Address> {
  final String street;
  final String city;
  final String country;
  final int zipCode;

  const Address(this.street, this.city, this.country, this.zipCode);

  static final $ = ModelType<Address, AddressField>(
    Address.new,
    AddressField(),
  );

  @override
  List<Field<Address, Object?>> get fields => $.fields.all;

  factory Address.fromJson(Json json) => $.call(json);
  Address copyWith(FieldsBuilder<AddressField> builder) =>
      $.bind(this)(builder);
}

final class AddressField extends FieldSet<Address> {
  /// Order does not matter
  final street = 'street_address'.field<Address, String>((m) => m.street);
  final city = 'city_name'.field<Address, String>((m) => m.city);
  final country = 'country_name'.field<Address, String>((m) => m.country);
  final zipCode = 'zip_code'.field<Address, int>((m) => m.zipCode);

  /// The order is exactly the same as in Address(this.street, this.city, this.country, this.zipCode)
  @override
  ListFieldOf<Address> get all => [street, city, country, zipCode];
}

class User extends Equatable with Serializable<User> {
  final int id;
  final String name;
  final String email;
  final bool isActive;
  final UserRole role;
  final DateTime createdAt;
  final Address? address;

  const User(
    this.id,
    this.name,
    this.email,
    this.isActive,
    this.role,
    this.createdAt,
    this.address,
  );

  static final $ = ModelType<User, UserField>(User.new, UserField());

  @override
  ListFieldOf<User> get fields => $.fields.all;

  factory User.fromJson(Json json) => $.call(json);
  User copyWith(FieldsBuilder<UserField> builder) => $.bind(this)(builder);
}

final class UserField extends FieldSet<User> {
  final id = 'user_id'.field<User, int>((m) => m.id);
  final name = 'full_name'.field<User, String>((m) => m.name);
  final email = 'email_address'.field<User, String>((m) => m.email);
  final isActive = 'is_active'.field<User, bool>((m) => m.isActive);
  final role = 'user_role'.field<User, UserRole>(
    (m) => m.role,
    parser: enumOrDefault(UserRole.values),
  );

  final createdAt = 'created_at'.field<User, DateTime>((m) => m.createdAt);
  final address = 'user_address'.field<User, Address?>(
    (m) => m.address,
    parser: modelOrNull(Address.fromJson),
    nullable: true,
  );

  @override
  ListFieldOf<User> get all => [
    id,
    name,
    email,
    isActive,
    role,
    createdAt,
    address,
  ];
}

class Terminal extends Equatable with Serializable<Terminal> {
  final int id;
  final String title;
  final DeviceStatus status;
  final List<Sensor> sensors;
  final Map<AccessLevel, String> tokens;
  final List<User> users;

  const Terminal(
    this.id,
    this.title,
    this.status,
    this.sensors,
    this.tokens,
    this.users,
  );

  static final $ = ModelType<Terminal, TerminalField>(
    Terminal.new,
    TerminalField(),
  );

  @override
  ListFieldOf<Terminal> get fields => $.fields.all;

  factory Terminal.fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalField> builder) =>
      $.bind(this)(builder);
}

final class TerminalField extends FieldSet<Terminal> {
  final id = 't_id'.field<Terminal, int>((m) => m.id);
  final title = 'display_name'.field<Terminal, String>(
    (m) => m.title,
    parser: (v) => v as String? ?? 'Unnamed Terminal',
  );
  final status = 'device_status'.field<Terminal, DeviceStatus>(
    (m) => m.status,
    parser: enumOrDefault(DeviceStatus.values),
  );
  final sensors = 'attached_sensors'.field<Terminal, List<Sensor>>(
    (m) => m.sensors,
    parser: listOf<Sensor>(modelOf(Sensor.fromJson)),
  );
  final tokens = 'access_keys'.field<Terminal, Map<AccessLevel, String>>(
    (m) => m.tokens,
    parser: mapOf(enumOrDefault(AccessLevel.values), stringOrEmpty),
  );
  final users = 'terminal_users'.field<Terminal, List<User>>(
    (m) => m.users,
    parser: listOf<User>(modelOf(User.fromJson)),
  );

  @override
  ListFieldOf<Terminal> get all => [id, title, status, sensors, tokens, users];
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

      final terminal = Terminal.fromJson(Json.from(rawJson));
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

      final terminal = Terminal.fromJson(Json.from(rawJson));

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
        'access_keys': {'read': 'read_key'},
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
      final updatedTerminal = originalTerminal.copyWith(
        ($) => [
          $.status.set(DeviceStatus.offline),
          $.title.set('Updated Terminal'),
        ],
      );

      expect(originalTerminal.status, DeviceStatus.active);
      expect(originalTerminal.title, 'Original Terminal');

      expect(updatedTerminal.status, DeviceStatus.offline);
      expect(updatedTerminal.title, 'Updated Terminal');

      expect(updatedTerminal.sensors.length, 1);
      expect(updatedTerminal.users.length, 1);
      expect(updatedTerminal.sensors[0].uid, 'SN-001');
      expect(updatedTerminal.users[0].name, 'John Doe');
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

      final terminal = Terminal.fromJson(Json.from(rawJson));
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

    test('Test deeply nested copyWith operations', () {
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
        'access_keys': {'read': 'read_key'},
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
        ],
      };

      final originalTerminal = Terminal.fromJson(Json.of(rawJson));

      final updatedTerminal = originalTerminal.copyWith(
        ($) => [$.id.set(2), $.status.set(DeviceStatus.maintenance)],
      );

      expect(updatedTerminal.id, 2);
      expect(updatedTerminal.status, DeviceStatus.maintenance);
      expect(updatedTerminal.sensors.length, 1);
      expect(updatedTerminal.users.length, 1);
      expect(updatedTerminal.users[0].name, 'John Doe');
      expect(updatedTerminal.users[0].address!.city, 'New York');
    });
  });
}
