import 'package:faker/faker.dart';
import 'package:flutter_nakama/api.dart' as api;
import 'package:flutter_nakama/nakama.dart';
import 'package:test/test.dart';

import '../config.dart';

void main() {
  group('[REST] Test Account', () {
    late final NakamaBaseClient client;
    late final Session session;

    setUpAll(() async {
      client = NakamaRestApiClient.init(
        host: kTestHost,
        ssl: false,
        serverKey: kTestServerKey,
      );

      session = await client.authenticateDevice(deviceId: faker.guid.guid());
    });

    test('fetching my account', () async {
      final account = await client.getAccount(session);

      expect(account, isA<api.Account>());
    });

    test('updating my account', () async {
      await client.updateAccount(session: session, displayName: 'name');
    });

    test("fetch another's account", () async {
      // create another dummy user
      final anotherUser = await client.authenticateDevice(
        deviceId: faker.guid.guid(),
      );

      // fetch this user
      final users = await client.getUsers(
        session: session,
        ids: [anotherUser.userId],
      );

      expect(users, isA<api.Users>());
      expect(users.users, hasLength(1));
    });
  });
}
