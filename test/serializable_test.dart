import 'package:json_forge/json_forge.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

// =============================================================================
// Complex nested models — schemas are plain Dart Records, so `copyWith`
// reads `$.field.set(...)` with no string keys anywhere.
// =============================================================================

enum DeviceStatus { active, maintenance, offline, unknown }

enum AccessLevel { read, write, execute }

enum UserRole { admin, user, guest }

/// Nested model: Sensor.
typedef SensorFields<T> = ({
  Field<T, String> uid,
  Field<T, double> value,
  Field<T, List<DateTime>> history,
});

class Sensor extends Equatable with Serializable<Sensor> {
  final String uid;
  final double value;
  final List<DateTime> history;

  const Sensor(this.uid, this.value, this.history);

  static final SensorFields<Sensor> _fields = (
    uid: 'sensor_uid'.field<Sensor, String>((m) => m.uid),
    value: 'last_value'.field((m) => m.value, parser: doubleOrZero),
    history: 'history_logs'.field(
      (m) => m.history,
      parser: listOf(dateTimeOrEpoch),
    ),
  );

  static final $ = ModelType<Sensor>(Sensor.new, [
    _fields.uid,
    _fields.value,
    _fields.history,
  ]);

  @override
  ListFieldOf<Sensor> get fields => $.all;

  factory Sensor.fromJson(Json json) => $.call(json);

  Sensor copyWith(FieldsBuilder<SensorFields> builder) =>
      $.bind(this, _fields)(builder);
}

/// Nested model: Address.
typedef AddressFields<T> = ({
  Field<T, String> street,
  Field<T, String> city,
  Field<T, String> country,
  Field<T, int> zipCode,
});

class Address extends Equatable with Serializable<Address> {
  final String street;
  final String city;
  final String country;
  final int zipCode;

  const Address(this.street, this.city, this.country, this.zipCode);

  static final AddressFields<Address> _fields = (
    street: 'street_address'.field<Address, String>((m) => m.street),
    city: 'city_name'.field<Address, String>((m) => m.city),
    country: 'country_name'.field<Address, String>((m) => m.country),
    zipCode: 'zip_code'.field<Address, int>((m) => m.zipCode),
  );

  /// The order here is exactly Address(this.street, this.city, this.country, this.zipCode)
  /// — that's all that's load-bearing; the Record above can list its named
  /// fields in any order.
  static final $ = ModelType<Address>(Address.new, [
    _fields.street,
    _fields.city,
    _fields.country,
    _fields.zipCode,
  ]);

  @override
  List<Field<Address, Object?>> get fields => $.all;

  factory Address.fromJson(Json json) => $.call(json);
  Address copyWith(FieldsBuilder<AddressFields> builder) =>
      $.bind(this, _fields)(builder);
}

typedef UserFields<T> = ({
  Field<T, int> id,
  Field<T, String> name,
  Field<T, String> email,
  Field<T, bool> isActive,
  Field<T, UserRole> role,
  Field<T, DateTime> createdAt,
  Field<T, Address?> address,
});

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

  static final UserFields<User> _fields = (
    id: 'user_id'.field<User, int>((m) => m.id),
    name: 'full_name'.field<User, String>((m) => m.name),
    email: 'email_address'.field<User, String>((m) => m.email),
    isActive: 'is_active'.field<User, bool>((m) => m.isActive),
    role: 'user_role'.field(
      (m) => m.role,
      parser: enumOrFirst(UserRole.values),
      serializer: enumToJson,
    ),
    createdAt: 'created_at'.field<User, DateTime>((m) => m.createdAt),
    // Genuinely nullable on the model (Address?) — `nullable` isn't passed
    // explicitly, it's auto-derived as `true` from the field type. See the
    // "auto-derives nullable" test below.
    address: 'user_address'.field(
      (m) => m.address,
      nullable: true,
      parser: modelOrNull(Address.fromJson),
    ),
  );

  static final $ = ModelType<User>(User.new, [
    _fields.id,
    _fields.name,
    _fields.email,
    _fields.isActive,
    _fields.role,
    _fields.createdAt,
    _fields.address,
  ]);

  @override
  ListFieldOf<User> get fields => $.all;

  factory User.fromJson(Json json) => $.call(json);
  User copyWith(FieldsBuilder<UserFields> builder) =>
      $.bind(this, _fields)(builder);
}

typedef TerminalFields = ({
  Field<Terminal, int> id,
  Field<Terminal, String> title,
  Field<Terminal, DeviceStatus> status,
  Field<Terminal, List<Sensor>> sensors,
  Field<Terminal, Map<AccessLevel, String>> tokens,
  Field<Terminal, List<User>> users,
});

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

  static final TerminalFields _fields = (
    id: 't_id'.field<Terminal, int>((m) => m.id),
    title: 'display_name'.field<Terminal, String>(
      (m) => m.title,
      parser: (v) => v as String? ?? 'Unnamed Terminal',
    ),
    status: 'device_status'.field<Terminal, DeviceStatus>(
      (m) => m.status,
      parser: enumOrFirst(DeviceStatus.values),
    ),
    sensors: 'attached_sensors'.field<Terminal, List<Sensor>>(
      (m) => m.sensors,
      parser: listOf<Sensor>(modelOf(Sensor.fromJson)),
    ),
    tokens: 'access_keys'.field<Terminal, Map<AccessLevel, String>>(
      (m) => m.tokens,
      parser: mapOf(enumOrFirst(AccessLevel.values), stringOrEmpty),
    ),
    users: 'terminal_users'.field<Terminal, List<User>>(
      (m) => m.users,
      parser: listOf<User>(modelOf(User.fromJson)),
    ),
  );

  static final $ = ModelType<Terminal>(Terminal.new, [
    _fields.id,
    _fields.title,
    _fields.status,
    _fields.sensors,
    _fields.tokens,
    _fields.users,
  ]);

  @override
  ListFieldOf<Terminal> get fields => $.all;

  factory Terminal.fromJson(Json json) => $.call(json);

  Terminal copyWith(FieldsBuilder<TerminalFields> builder) =>
      $.bind(this, _fields)(builder);
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

    test(
      'copyWith reaches a field via native Record access (Sensor.value)',
      () {
        final sensor = Sensor.fromJson({
          'sensor_uid': 'SN-100',
          'last_value': 10.5,
          'history_logs': <String>[],
        });

        // $.value is a plain Record field access — no string key, no
        // operator [], nothing reflective involved.
        final updated = sensor.copyWith(($) => [$.value.set(99.9)]);

        expect(sensor.value, 10.5);
        expect(updated.value, 99.9);
        expect(updated.uid, sensor.uid);
      },
    );
  });

  // ===========================================================================
  // Production-readiness fixes
  // ===========================================================================

  group(
    'ModelType without a Record — fromJson/toJson need no schema object',
    () {
      test(
        'a model can skip the Record entirely if it never needs copyWith',
        () {
          final gadget = Gadget.fromJson({
            'gadget_uid': 'GX-1',
            'reading': 10.5,
          });
          expect(gadget.uid, 'GX-1');
          expect(gadget.reading, 10.5);
          expect(gadget.toJson(), {'gadget_uid': 'GX-1', 'reading': 10.5});
        },
      );
    },
  );

  group('Record-based schema decouples Field name from jsonKey', () {
    test("a Record field's name is independent of the field's jsonKey", () {
      final widget = Widget.fromJson({'w_uid': 'W-1', 'w_count': 3});

      // WidgetFields' jsonKey is 'w_count'; the Record field is `count`.
      // copyWith only ever sees the latter — there's no string anywhere
      // in this call for the analyzer to fail to check.
      final updated = widget.copyWith(($) => [$.count.set(9)]);

      expect(updated.count, 9);
      expect(updated.uid, widget.uid);
    });

    test(
      'a typo in the Record field name is a compile error, not a runtime one',
      () {
        // This is exactly why there's nothing to test here at runtime:
        //   widget.copyWith(($) => [$.cuont.set(9)]);
        // doesn't compile — `cuont` isn't a member of WidgetFields. The
        // previous (1.0.0) design caught this kind of typo with a runtime
        // ArgumentError from FieldSet.operator []; Records catch it before
        // the code ever runs.
      },
      skip: 'documentation only — see the comment above',
    );
  });

  group('Field.nullable — auto-derived default', () {
    test('a nullable-typed field accepts null without an explicit flag', () {
      // UserFields.address is declared as Field<User, Address?> *without*
      // passing `nullable: true` — it must still accept a missing/null
      // value instead of throwing RequiredFieldError.
      final user = User.fromJson({
        'user_id': 1,
        'full_name': 'Ann',
        'email_address': 'ann@example.com',
        'is_active': true,
        'user_role': 'user',
        'created_at': '2026-01-07T10:00:00Z',
        'user_address': null,
      });
      expect(user.address, null);
    });

    test(
      'a non-nullable field still throws RequiredFieldError when missing',
      () {
        // Note: this needs a parser that can genuinely return `null` — the
        // smart-inferred default for `int` is `intOrZero`, which *never*
        // returns null (it falls back to 0), so it could never trigger this
        // path. `Probe` uses an explicit `intOrNull` to actually exercise it.
        expect(() => Probe.fromJson({}), throwsA(isA<RequiredFieldError>()));
      },
    );
  });

  group('Typed errors are part of the public API', () {
    test('TypeConversionError carries full context', () {
      // No explicit parser, and `Address` isn't one of the smart-inferred
      // primitives, so `_smartParse` falls through to its "unknown type"
      // branch and passes the raw value through unchanged. Feeding that a
      // String (not a Map, not an Address) makes the post-parse type check
      // fail — unlike a Map-shaped value, which `modelOrNull` would parse.
      final field = 'addr'.field<Object, Address>(
        (_) => throw UnimplementedError(),
      );

      try {
        field.parser('not an address');
        fail('expected a TypeConversionError');
      } on TypeConversionError catch (e) {
        expect(e.expectedType, Address);
        expect(e.actualType, String);
      }
    });
  });
}

// =============================================================================
// Gadget — the minimal shape: just a field list fed straight to ModelType,
// no Record at all. Fine for fromJson/toJson; only needed when a model
// genuinely wants type-safe copyWith.
// =============================================================================

class Gadget extends Equatable with Serializable<Gadget> {
  const Gadget(this.uid, this.reading);

  final String uid;
  final double reading;

  static final $ = ModelType<Gadget>(Gadget.new, [
    'gadget_uid'.field<Gadget, String>((m) => m.uid),
    'reading'.field<Gadget, double>((m) => m.reading, parser: doubleOrZero),
  ]);

  @override
  ListFieldOf<Gadget> get fields => $.all;

  static Gadget fromJson(Json json) => $.call(json);
}

// =============================================================================
// Widget — same model shape as Gadget, but *with* a Record, and a jsonKey
// that deliberately differs from the Record's field name (`w_count` vs.
// `count`), to exercise that decoupling explicitly.
// =============================================================================

typedef WidgetFields = ({Field<Widget, String> uid, Field<Widget, int> count});

class Widget extends Equatable with Serializable<Widget> {
  const Widget(this.uid, this.count);

  final String uid;
  final int count;

  static final WidgetFields _fields = (
    uid: 'w_uid'.field<Widget, String>((m) => m.uid),
    count: 'w_count'.field<Widget, int>((m) => m.count, parser: intOrZero),
  );

  static final $ = ModelType<Widget>(Widget.new, [_fields.uid, _fields.count]);

  @override
  ListFieldOf<Widget> get fields => $.all;

  static Widget fromJson(Json json) => $.call(json);

  Widget copyWith(FieldsBuilder<WidgetFields> builder) =>
      $.bind(this, _fields)(builder);
}

// =============================================================================
// Probe — a single required `int` field with an explicit `intOrNull`
// parser, used only to exercise RequiredFieldError. The smart-inferred
// default for `int` (`intOrZero`) never returns null, so it can't be used
// to test this path — a field needs an explicit null-returning parser (or
// a model parser like `modelOrNull`) to ever actually trigger it.
// =============================================================================

class Probe extends Equatable with Serializable<Probe> {
  const Probe(this.count);

  final int count;

  static final $ = ModelType<Probe>(Probe.new, [
    'count'.field<Probe, int>((m) => m.count, parser: intOrZero),
  ]);

  @override
  ListFieldOf<Probe> get fields => $.all;

  static Probe fromJson(Json json) => $.call(json);
}
