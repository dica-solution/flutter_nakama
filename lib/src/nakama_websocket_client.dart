import 'dart:async';
import 'dart:convert';

import 'package:flutter_nakama/api.dart';
import 'package:flutter_nakama/rtapi.dart' as rtpb;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';

class NakamaWebsocketClient {
  static final _log = Logger('NakamaWebsocketClient');
  static final Map<String, NakamaWebsocketClient> _clients = {};

  /// The host address of the server.
  final String host;

  /// The port number of the server. Defaults to 7349
  final int port;
  final bool ssl;

  /// The user's access token.
  final String token;

  final void Function()? onDone;
  final void Function(dynamic error)? onError;

  final void Function()? onDisconnect;

  late final IOWebSocketChannel _channel;

  final _onChannelPresenceController =
      StreamController<rtpb.ChannelPresenceEvent>.broadcast();

  Stream<rtpb.ChannelPresenceEvent> get onChannelPresence =>
      _onChannelPresenceController.stream;

  final _onMatchmakerMatchedController =
      StreamController<rtpb.MatchmakerMatched>.broadcast();

  Stream<rtpb.MatchmakerMatched> get onMatchmakerMatched =>
      _onMatchmakerMatchedController.stream;

  final _onMatchDataController = StreamController<rtpb.MatchData>.broadcast();

  Stream<rtpb.MatchData> get onMatchData => _onMatchDataController.stream;

  final _onMatchPresenceController =
      StreamController<rtpb.MatchPresenceEvent>.broadcast();

  Stream<rtpb.MatchPresenceEvent> get onMatchPresence =>
      _onMatchPresenceController.stream;

  final _onNotificationsController =
      StreamController<rtpb.Notifications>.broadcast();

  Stream<rtpb.Notifications> get onNotifications =>
      _onNotificationsController.stream;

  final _onStatusPresenceController =
      StreamController<rtpb.StatusPresenceEvent>.broadcast();

  Stream<rtpb.StatusPresenceEvent> get onStatusPresence =>
      _onStatusPresenceController.stream;

  final _onStreamPresenceController =
      StreamController<rtpb.StreamPresenceEvent>.broadcast();

  Stream<rtpb.StreamPresenceEvent> get onStreamPresence =>
      _onStreamPresenceController.stream;

  final _onStreamDataController = StreamController<rtpb.StreamData>.broadcast();

  Stream<rtpb.StreamData> get onStreamData => _onStreamDataController.stream;

  final _onChannelMessageController =
      StreamController<ChannelMessage>.broadcast();

  Stream<ChannelMessage> get onChannelMessage =>
      _onChannelMessageController.stream;

  final List<Completer> _futures = [];

  /// Returns the default instance.
  static NakamaWebsocketClient get instance {
    return NakamaWebsocketClient.instanceFor(key: 'default');
  }

  /// Returns the instance with given key.
  static NakamaWebsocketClient instanceFor({required String key}) {
    if (!_clients.containsKey(key)) {
      throw Exception('$key has not yet been initialized');
    }

    return _clients[key]!;
  }

  factory NakamaWebsocketClient.init({
    String key = 'default',
    required String host,
    int port = 7350,
    required bool ssl,
    required String token,
    Function()? onDone,
    Function(dynamic error)? onError,
    Function()? onDisconnect,
  }) {
    // Has the client already been initialized? Then return it.
    if (_clients.containsKey(key)) {
      return instanceFor(key: key);
    }

    // Create new and return instance of this.
    return _clients[key] = NakamaWebsocketClient._(
        host: host,
        port: port,
        ssl: ssl,
        token: token,
        onDone: onDone,
        onError: onError,
        onDisconnect: onDisconnect);
  }

  NakamaWebsocketClient._({
    required this.host,
    this.port = 7350,
    required this.ssl,
    required this.token,
    this.onDone,
    this.onError,
    this.onDisconnect,
  }) {
    _log.info('Connecting ${ssl ? 'WSS' : 'WS'} to $host:$port');
    _log.info('Using token $token');
    final uri = Uri(
      host: host,
      port: port,
      scheme: ssl ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {
        'token': token,
        'format': 'protobuf',
      },
    );
    _channel = IOWebSocketChannel.connect(uri,
        pingInterval: const Duration(seconds: 2));
    _log.info('connected');

    _channel.stream.listen(
      _onData,
      onDone: () {
        _clients.clear();
        if (_channel.closeReason == 'goingAway') {
          onDisconnect?.call();
        }
        if (onDone != null) {
          onDone!();
        }
      },
      onError: (err) {
        if (onError != null) {
          onError!(err);
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> close() {
    return Future.wait([
      _onChannelPresenceController.close(),
      _onMatchmakerMatchedController.close(),
      _onMatchDataController.close(),
      _onMatchPresenceController.close(),
      _onNotificationsController.close(),
      _onStatusPresenceController.close(),
      _onStreamPresenceController.close(),
      _onStreamDataController.close(),
      _onChannelMessageController.close(),
      _channel.sink.close(),
    ]);
  }

  void _onData(msg) {
    try {
      final receivedEnvelope = rtpb.Envelope.fromBuffer(msg);
      _log.info('onData: $receivedEnvelope');

      if (receivedEnvelope.cid.isNotEmpty) {
        // get corresponding future to complete
        final waitingFuture = _futures[int.parse(receivedEnvelope.cid)];

        // ? Is there any chance to do this better with <T>?
        if (waitingFuture is Completer<rtpb.Match>) {
          return waitingFuture.complete(receivedEnvelope.match);
        } else if (waitingFuture is Completer<rtpb.MatchmakerTicket>) {
          return waitingFuture.complete(receivedEnvelope.matchmakerTicket);
        } else if (waitingFuture is Completer<rtpb.Status>) {
          return waitingFuture.complete(receivedEnvelope.status);
        } else if (waitingFuture is Completer<rtpb.Channel>) {
          return waitingFuture.complete(receivedEnvelope.channel);
        } else if (waitingFuture is Completer<rtpb.ChannelMessageAck>) {
          return waitingFuture.complete(receivedEnvelope.channelMessageAck);
        } else {
          return waitingFuture.complete();
        }
      } else {
        // map server messages
        switch (receivedEnvelope.whichMessage()) {
          case rtpb.Envelope_Message.channelPresenceEvent:
            return _onChannelPresenceController
                .add(receivedEnvelope.channelPresenceEvent);
          case rtpb.Envelope_Message.matchmakerMatched:
            return _onMatchmakerMatchedController
                .add(receivedEnvelope.matchmakerMatched);
          case rtpb.Envelope_Message.matchData:
            return _onMatchDataController.add(receivedEnvelope.matchData);
          case rtpb.Envelope_Message.matchPresenceEvent:
            return _onMatchPresenceController
                .add(receivedEnvelope.matchPresenceEvent);
          case rtpb.Envelope_Message.notifications:
            return _onNotificationsController
                .add(receivedEnvelope.notifications);
          case rtpb.Envelope_Message.statusPresenceEvent:
            return _onStatusPresenceController
                .add(receivedEnvelope.statusPresenceEvent);
          case rtpb.Envelope_Message.streamPresenceEvent:
            return _onStreamPresenceController
                .add(receivedEnvelope.streamPresenceEvent);
          case rtpb.Envelope_Message.streamData:
            return _onStreamDataController.add(receivedEnvelope.streamData);
          case rtpb.Envelope_Message.channelMessage:
            return _onChannelMessageController
                .add(receivedEnvelope.channelMessage);
          default:
            return _log.warning('Not implemented');
        }
      }
    } catch (e, s) {
      _log.warning(e);
      _log.warning(s);
    }
  }

  Future<T> _send<T>(rtpb.Envelope envelope) {
    final ticket = _createTicket<T>();
    _channel.sink.add((envelope..cid = ticket.toString()).writeToBuffer());
    return _futures[ticket].future as Future<T>;
  }

  int _createTicket<T>() {
    final completer = Completer<T>();
    _futures.add(completer);
    return _futures.length - 1;
  }

  Future updateStatus(String status) => _send<void>(rtpb.Envelope(
      statusUpdate: rtpb.StatusUpdate(status: StringValue(value: status))));

  Future<rtpb.Match> createMatch() =>
      _send<rtpb.Match>(rtpb.Envelope(matchCreate: rtpb.MatchCreate()));

  Future<rtpb.Match> joinMatch(
    String matchId, {
    String? token,
  }) =>
      _send<rtpb.Match>(rtpb.Envelope(
          matchJoin: rtpb.MatchJoin(matchId: matchId, token: token)));

  Future<void> leaveMatch(String matchId) =>
      _send<void>(rtpb.Envelope(matchLeave: rtpb.MatchLeave(matchId: matchId)));

  Future<rtpb.MatchmakerTicket> addMatchmaker({
    required int minCount,
    int? maxCount,
    String? query,
    Map<String, double>? numericProperties,
    Map<String, String>? stringProperties,
  }) {
    assert(minCount >= 2);
    assert(maxCount == null || maxCount >= minCount);

    return _send(rtpb.Envelope(
        matchmakerAdd: rtpb.MatchmakerAdd(
      maxCount: maxCount,
      minCount: minCount,
      numericProperties: numericProperties,
      stringProperties: stringProperties,
      query: query,
    )));
  }

  Future<void> removeMatchmaker(String ticket) => _send(
      rtpb.Envelope(matchmakerRemove: rtpb.MatchmakerRemove(ticket: ticket)));

  Future<Rpc> rpc({required String id, String? payload}) =>
      _send(rtpb.Envelope(rpc: Rpc(id: id, payload: payload)));

  Future<rtpb.Status> followUsers({
    List<String>? userIds,
    List<String>? usernames,
  }) =>
      _send(rtpb.Envelope(
          statusFollow: rtpb.StatusFollow(
        userIds: userIds,
        usernames: usernames,
      )));

  Future<rtpb.Status> unfollowUsers({
    List<String>? userIds,
  }) =>
      _send(rtpb.Envelope(
          statusUnfollow: rtpb.StatusUnfollow(
        userIds: userIds,
      )));

  Future<List<rtpb.UserPresence>> sendMatchData({
    required String matchId,
    required Int64 opCode,
    required List<int> data,
  }) =>
      _send(rtpb.Envelope(
          matchDataSend: rtpb.MatchDataSend(
        matchId: matchId,
        opCode: opCode,
        data: data,
      )));

  Future<rtpb.Channel> joinChannel({
    required String target,
    required rtpb.ChannelJoin_Type type,
    required bool persistence,
    required bool hidden,
  }) =>
      _send<rtpb.Channel>(rtpb.Envelope(
          channelJoin: rtpb.ChannelJoin(
        target: target,
        type: type.value,
        persistence: BoolValue(value: persistence),
        hidden: BoolValue(value: hidden),
      )));

  Future<void> leaveChannel({
    required String channelId,
  }) =>
      _send(
        rtpb.Envelope(channelLeave: rtpb.ChannelLeave(channelId: channelId)),
      );

  Future<rtpb.ChannelMessageAck> sendMessage({
    required String channelId,
    required Map<String, String> content,
  }) =>
      _send<rtpb.ChannelMessageAck>(rtpb.Envelope(
          channelMessageSend: rtpb.ChannelMessageSend(
        channelId: channelId,
        content: jsonEncode(content),
      )));

  Future<rtpb.ChannelMessageAck> updateMessage({
    required String channelId,
    required String messageId,
    required Map<String, String> content,
  }) =>
      _send<rtpb.ChannelMessageAck>(rtpb.Envelope(
          channelMessageUpdate: rtpb.ChannelMessageUpdate(
        channelId: channelId,
        messageId: messageId,
        content: jsonEncode(content),
      )));
}
