/// socket.io 0.9 helpers for the control channel (port 8000) of 2014-2015
/// Samsung TVs.
const socketIoConnectFrame = '1::/com.samsung.companion';
const socketIoHeartbeat = '2::';

Uri socketIoHandshakeUri(String host, int millis) =>
    Uri(scheme: 'http', host: host, port: 8000, path: '/socket.io/1/', queryParameters: {
      't': '$millis',
    });

Uri socketIoWebSocketUri(String host, String sessionId) => Uri(
    scheme: 'ws', host: host, port: 8000, path: '/socket.io/1/websocket/$sessionId');

/// The handshake reply is `sid:heartbeatTimeout:closeTimeout:transports`.
String? socketIoSessionId(String body) {
  final sid = body.split(':').first.trim();
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(sid) ? sid : null;
}

/// How long the channel may stay silent before it is considered dead: one and a
/// half times the server's heartbeat timeout (90 s when it doesn't say).
Duration socketIoIdleTimeout(String body) {
  final parts = body.split(':');
  final seconds = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (seconds == null || seconds <= 0) return const Duration(seconds: 90);
  return Duration(milliseconds: seconds * 1500);
}

sealed class SioFrame {
  const SioFrame();
}

class SioHeartbeat extends SioFrame {
  const SioHeartbeat();
}

class SioConnected extends SioFrame {
  const SioConnected();
}

class SioDisconnect extends SioFrame {
  const SioDisconnect();
}

class SioOther extends SioFrame {
  const SioOther();
}

SioFrame parseSocketIoFrame(String raw) {
  if (raw.startsWith('2::')) return const SioHeartbeat();
  if (raw.startsWith('1::')) return const SioConnected();
  if (raw.startsWith('0::')) return const SioDisconnect();
  return const SioOther();
}
