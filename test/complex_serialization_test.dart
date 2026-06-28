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
class Sensor extends Equatable with Serializable<Sensor> {
  final String uid;
  final double value;
  final List<DateTime> history;

  const Sensor(this.uid, this.value, this.history);

  static final $ = ModelType<Sensor, SensorSchema>(Sensor.new, SensorSchema());

  @override
  ListFieldOf<Sensor> get fields => $.schema.all;

  @override
  Props get props => [uid, value, history];

  factory Sensor.fromJson(Json json) => $.call(json);
  Sensor copyWith(FieldsBuilder<SensorSchema> builder) => $.bind(this)(builder);
}

/// Schema
final class SensorSchema extends Schema<Sensor> {
  late final uid = field<String>('sensor_uid');
  late final value = field<double>('last_value');
  late final history = field(
    'history_logs',
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

  static final $ = ModelType<Address, AddressSchema>(
    Address.new,
    AddressSchema(),
  );

  @override
  ListFieldOf<Address> get fields => $.schema.all;

  @override
  Props get props => [street, city, country, zipCode];

  factory Address.fromJson(Json json) => $.call(json);
  Address copyWith(FieldsBuilder<AddressSchema> builder) =>
      $.bind(this)(builder);
}

final class AddressSchema extends Schema<Address> {
  /// Declaration order does not matter here.
  late final street = field<String>('street_address');
  late final city = field<String>('city_name');
  late final country = field<String>('country_name');
  late final zipCode = field<int>('zip_code');

  /// The order here is exactly the same as in
  /// `Address(this.street, this.city, this.country, this.zipCode)`.
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

  static final $ = ModelType<User, UserSchema>(User.new, UserSchema());

  @override
  ListFieldOf<User> get fields => $.schema.all;

  @override
  Props get props => [id, name, email, isActive, role, createdAt, address];

  factory User.fromJson(Json json) => $.call(json);
  User copyWith(FieldsBuilder<UserSchema> builder) => $.bind(this)(builder);
}

final class UserSchema extends Schema<User> {
  late final id = field<int>('user_id');
  late final name = field<String>('full_name');
  late final email = field<String>('email_address');
  late final isActive = field<bool>('is_active');
  late final role = field('user_role', parser: enumOrFirst(UserRole.values));

  late final createdAt = field<DateTime>('created_at');

  // `nullable: true` is spelled out here even though it'd default to
  // `null is R` (`Address?`) anyway — exercising the explicit override path
  // alongside the implicit one used by the fields above.
  late final address = field(
    'user_address',
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

  static final $ = ModelType<Terminal, TerminalSchema>(
    Terminal.new,
    TerminalSchema(),
  );

  @override
  ListFieldOf<Terminal> get fields => $.schema.all;

  @override
  Props get props => [id, title, status, sensors, tokens, users];

  factory Terminal.fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalSchema> builder) =>
      $.bind(this)(builder);
}

final class TerminalSchema extends Schema<Terminal> {
  late final id = field<int>('t_id');
  late final title = field(
    'display_name',
    parser: (v) => v as String? ?? 'Unnamed Terminal',
  );
  late final status = field(
    'device_status',
    parser: enumOrFirst(DeviceStatus.values),
    // A custom serializer here is what makes the "direct construction"
    // regression test below meaningful: without one, a missing cached
    // value used to come back as a quiet `null` (still wrong, but not a
    // crash). With one, `serializer(null as DeviceStatus)` is exactly the
    // unsound cast that used to throw — see that test for details.
    serializer: enumToJson,
  );
  late final sensors = field(
    'attached_sensors',
    parser: listOf<Sensor>(modelOf(Sensor.fromJson)),
  );
  late final tokens = field(
    'access_keys',
    parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
  );
  late final users = field(
    'terminal_users',
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
      final updated = terminal.copyWith(($) => [$.title.set('Renamed')]);

      expect(updated.title, 'Renamed');
      expect(updated.id, 5);
      expect(updated.status, DeviceStatus.active);
      expect(terminal.title, 'Direct Terminal'); // original is untouched
    });

    test('== reflects real values for directly-constructed instances', () {
      final a = buildDirectly(raw);
      final b = buildDirectly(raw);
      final renamed = a.copyWith(($) => [$.title.set('Different')]);

      expect(a, b); // same inputs → equal, not just "both blank"
      expect(a == renamed, false);
    });
  });
}
