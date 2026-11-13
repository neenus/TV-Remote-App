import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_protocol.dart';

void main() {
  group('socket.io handshake', () {
    test('session_id_is_the_first_field', () {
      expect(socketIoSessionId('ABC123:60:60:websocket,xhr-polling'), 'ABC123');
    });

    test('idle_limit_follows_the_heartbeat_timeout', () {
      expect(socketIoIdleTimeout('ABC123:60:60:websocket'), const Duration(seconds: 90));
      expect(socketIoIdleTimeout('ABC123:20:60:websocket'), const Duration(seconds: 30));
    });

    test('bad_bodies_are_rejected_or_defaulted', () {
      expect(socketIoSessionId(''), isNull);
      expect(socketIoSessionId(':60:60:websocket'), isNull);
      expect(socketIoSessionId('<html>nope</html>'), isNull);
      expect(socketIoIdleTimeout('ABC123'), isNull);
      expect(socketIoIdleTimeout('ABC123:x:y'), isNull);
      expect(socketIoIdleTimeout('ABC123::60'), isNull);
      expect(socketIoIdleTimeout('ABC123:0:60'), isNull);
    });

    test('urls_and_frames', () {
      expect(socketIoHandshakeUri('10.0.0.5', 123).toString(), 'http://10.0.0.5:8000/socket.io/1/?t=123');
      expect(socketIoWebSocketUri('10.0.0.5', 'SID').toString(),
          'ws://10.0.0.5:8000/socket.io/1/websocket/SID');
      expect(socketIoConnectFrame, '1::/com.samsung.companion');
      expect(socketIoHeartbeat, '2::');
    });
  });

  group('frames', () {
    test('classifies_each_kind', () {
      expect(parseSocketIoFrame('2::'), isA<SioHeartbeat>());
      expect(parseSocketIoFrame('1::'), isA<SioConnected>());
      expect(parseSocketIoFrame('1::/com.samsung.companion'), isA<SioConnected>());
      expect(parseSocketIoFrame('0::'), isA<SioDisconnect>());
      expect(parseSocketIoFrame('5::/com.samsung.companion:{"name":"x"}'), isA<SioOther>());
    });

    test('garbage_is_other_not_an_error', () {
      for (final g in ['', 'x', '%%%', '9']) {
        expect(parseSocketIoFrame(g), isA<SioOther>(), reason: g);
      }
    });
  });
}
