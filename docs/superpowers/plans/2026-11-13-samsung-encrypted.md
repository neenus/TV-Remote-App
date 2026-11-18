# Samsung 2014-2015 (H/J series, encrypted PIN pairing) Plan

> Executed inline, same process and review lessons as the other Samsung plans.

**Goal:** Control the owner's UN50HU7000 (2014) and similar 2014-2015 Samsung TVs, which answer on ports 8000/8001/8080 but refuse 55000 and 8002.

**Evidence (probed, with the owner's permission, from this machine):** TV at 172.20.0.187: ports 8000, 8001, 8080 open; 55000 and 8002 refused. `GET :8001/api/v2/` returns device info (UN50HU7000, version 2.0.24, wireless; no wifiMac). `GET :8080/ws/apps/CloudPINPage` returns the DIAL app description with state "stopped". This matches the encrypted protocol of the `samsungtvws` library.

**Reference:** `samsungtvws` (xchwarze/samsung-tv-ws-api), package `samsungtvws.encrypted` (`authenticator.py`, `session.py`, `remote.py`). A scratch virtualenv with the library is used to generate golden test vectors; each Dart crypto step is checked against it.

## Protocol summary
1. **Pairing (HTTP, port 8080):** read `GET /ws/apps/CloudPINPage`; if state is "stopped", `POST` it with body `pin4` to make the TV show a PIN. `GET /ws/pairing?step=0&app_id=12345&device_id=<id>&type=1`. `POST /ws/pairing?step=1&...` with `{"auth_Data":{"auth_type":"SPC","GeneratorServerHello":"<hex>"}}`, where the hello is built from the SHA-1 of the PIN (AES-CBC with a built-in public key, then a fixed-key block transform). The reply contains `GeneratorClientHello`; check the PIN by verifying a hash over a Diffie-Hellman style secret (`pow(Gx, privateKey, prime)`), derive the key: SHA-1 chain then a **3-round** AES (Rijndael) transform. `POST step=2` with a server acknowledge; the reply has the client acknowledge (verified) and a `session_id`. Finally `DELETE /ws/apps/CloudPINPage/run`.
2. **Control (socket.io 0.9, port 8000):** `GET /socket.io/1/?t=<ms>` gives `<sid>:...`; open `ws://<ip>:8000/socket.io/1/websocket/<sid>`; send `1::/com.samsung.companion`. Commands are `5::/com.samsung.companion:{"name":"callCommon","args":[{"Session_Id":<id>,"body":"[<bytes>]"}]}` where the bytes are the AES-128-ECB (key = the derived token, PKCS-style padding) encryption of `{"method":"POST","body":{"plugin":"RemoteControl","param1":"uuid:12345","param2":"Click","param3":"KEY_X","param4":false,"api":"SendRemoteKey","version":"1.000"}}`. Reply to `2::` heartbeats with `2::`.
3. Credentials stored per TV as `<token hex>:<session id>`; later connects skip pairing.

## Tasks
1. **Crypto + protocol** (`samsung_encrypted_crypto.dart`, `samsung_encrypted_protocol.dart`): own AES-128 (any round count; FIPS-197 vector checked), SHA-1 from `package:crypto`, big-int exchange; golden vectors from the reference for every function.
2. **Pairing client** (`samsung_encrypted_auth.dart`) over an injectable `SamsungHttp`, tested against a scripted TV using golden vectors.
3. **Driver** (`samsung_encrypted_driver.dart`): PIN pairing states (`AwaitingPin`), stored credentials, socket.io channel with heartbeat reply, reconnect, all the lessons (handshake failures on close/dispose, stale sockets, drop-queued-presses, storage failures tolerated, typing unsupported).
4. **Wiring:** `TvBrand.samsungEncrypted`, Add-by-IP chips relabelled by year, factory, hints, forgetting a TV deletes its stored credentials.
5. Checklist, CI build, fresh review, fix pass, serve.

## Review Focus
1. Wrong PIN / expired PIN page: `PairingDenied` and a way to retry; no credentials stored.
2. Pairing aborted midway (dispose, socket close): connect fails, no hang, PIN page left running on the TV is closed when possible.
3. Stale credentials (TV reset): keys silently do nothing — is there a way for the user to recover (forget the TV and re-pair)?
4. Crypto edge cases: odd-length big-integer hex, leading zeros, wrong-length hello data.
5. socket.io framing: heartbeat, unexpected frames, malformed frames.
