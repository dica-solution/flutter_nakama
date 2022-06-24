import 'package:faker/faker.dart';
import 'package:flutter_nakama/api.dart' as api;
import 'package:flutter_nakama/nakama.dart';
import 'package:test/test.dart';

import '../config.dart';

void main() {
  group('[REST] Test Leaderboard', () {
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

    test('write leaderboard record', () async {
      final result = await client.writeLeaderboardRecord(
          session: session, leaderboardId: 'test', score: 10);

      expect(result, isA<api.LeaderboardRecord>());
      expect(result.score.toInt(), equals(10));
    });

    test('list leaderboard records', () async {
      final result = await client.listLeaderboardRecords(
          session: session, leaderboardId: 'test');

      expect(result, isA<api.LeaderboardRecordList>());
    });

    test('list leaderboard records around owner', () async {
      final result = await client.listLeaderboardRecordsAroundOwner(
          session: session, leaderboardId: 'test', ownerId: session.userId);

      expect(result, isA<api.LeaderboardRecordList>());
    });
  });
}
