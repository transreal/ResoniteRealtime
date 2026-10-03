# ResoniteRealtime_ws API Reference

## 概要
Pure-Wolfram WebSocket layer (RFC 6455), server + client, in context `ResoniteRealtime``. Underlies ResoniteRealtime (https://github.com/transreal/ResoniteRealtime).
- Both Resonite links are WebSocket: server side (in-world WebsocketClient connects in) and client side (connects to ResoniteLink). One frame codec serves both.
- Zero dependencies: only SocketOpen / SocketListen / SocketConnect. No Python worker, no J/Link.
- Server side only unmasks incoming frames. Client side masks outgoing frames (RFC 6455 requires it).
- Receive is via SocketListen async handlers. No FrontEnd communication. Never Pause inside handlers.
- Writes use SocketWriteMessage[..., "Blocking" -> True] in 64 KB chunks. Plain BinaryWrite inside callbacks/tasks only enqueues and silently drops on overflow (~1-2 MB), truncating bodies.
- Load: Block[{$CharacterEncoding="UTF-8"}, Get["ResoniteRealtime_ws.wl"]]
- IDs: servers "wssN", server-side connections "wsN", client connections "wcN".
- Loading performs one SocketOpen/Close warm-up (iEnsureSocketsReady) because a first-ever SocketConnect can crash the kernel; RRWSConnect re-checks.
- Close convention: sockets are never closed inside SocketListen callbacks (kernel crash); they are queued in a graveyard and reclaimed by RRWSSweep from top-level public APIs (RRWSServe, RRWSConnect, RRWSStatus, RRWSClose, RRWSStopServe call it automatically).

## Handler Association
handler[assoc] receives:
- "Event" -> "Open"|"Message"|"Close"|"Error"
- "Connection" -> connId
- "Role" -> "server"|"client"
- "Data" -> String (opcode 1) or ByteArray (opcode 2) (Message only)
- "Opcode" -> 1|2 (Message only)
- "Reason" -> "Peer"|"Local"|"HTTP"|"ServerStopped" (Close only)
- "Time" -> AbsoluteTime
Handler exceptions are swallowed; the last is recorded in $RRWSLastError. Fragmented messages are reassembled; ping is answered with pong automatically.
HTTPHandler assoc (see RRWSServe): <|"Method" -> first 8 chars of request, "Request" -> header text, "Headers" -> lowercased-key Association, "Path" -> String, "Connection" -> connId|>.

## Server

### RRWSServe[port, handler, opts]
Start a WebSocket server on port. Non-Upgrade plain HTTP GETs go to HTTPHandler (if set), then the connection is closed.
→ serverId (String), or Failure["PortUnavailable", ...]
Options: "BindAddress" -> "127.0.0.1" ("0.0.0.0" to expose; Automatic = 127.0.0.1), "HTTPHandler" -> None (f[assoc] returning a ByteArray (full raw HTTP response) written to the socket; same host:port reuses Resonite host-access permission)
例: RRWSServe[8765, Print, "HTTPHandler" -> (ByteArray[...]&)]

### RRWSStopServe[serverId] → serverId | $Failed
Close the server and all its connections (Close reason "ServerStopped"). $Failed if unknown id.

### RRWSStopServe[]
Stop all servers.

## Client

### RRWSConnect[url, handler, opts]
Connect as client to ws://host:port/path (http:// accepted; default port 80, path "/"). Handshake is synchronous; later receive is async. "Open" is delivered to the handler before return.
→ connId (String), or Failure["ConnectFailed"|"HandshakeTimeout"|"HandshakeRejected"|"BadAcceptKey", ...]
Options: "Timeout" -> 10 (handshake seconds)

## Send / Control

### RRWSSend[connId, text] → Integer | $Failed
Send a text frame (opcode 1). text: String (UTF-8) or ByteArray (sent as text frame). Returns payload byte length; $Failed if unknown connection or handshake not done.

### RRWSPing[connId] → Integer | $Failed
Send ping frame (keepalive).

### RRWSClose[connId] → connId | $Failed
Send close frame, close socket (Close reason "Local"), pause 0.15 s, sweep.

### RRWSBatch[expr]
HoldFirst. While expr evaluates, frames from RRWSSend/RRWSPing are buffered per connection and written together at the end (always flushed, even on abort). Nested calls: outer flushes. Avoids ~12 ms per-send write wait.

### RRWSFlush[] → Null
Flush buffered RRWSBatch frames immediately (call before a send that waits for a reply).

## Status

### RRWSStatus[] → Association
<|"Servers" -> <|id -> <|"Port","Started"|>|>, "Connections" -> <|id -> <|"Role","URL","Server","Handshake","Sent","Received","IdleSeconds"|>|>|>. Sweeps first.

### RRWSConnections[] → {String...}
List live connection IDs.

### RRWSSweep[]  → Integer
Reclaim graveyard sockets; returns count. No-op (0) inside SocketListen callbacks. Normally unnecessary.

### $RRWSLastError
型: Association, 初期値: unset
Record of last swallowed handler exception: <|"Time" -> AbsoluteTime, "Argument" -> handler argument|>.