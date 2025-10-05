# Integration Notes for Magnetized MatchFlow

## Current Status: sm-websocket vs magnetized_matchflow.sp

### The Challenge

- **sm-websocket plugin**: WebSocket **SERVER** (accepts incoming connections)
- **magnetized_matchflow.sp**: Needs WebSocket **CLIENT** (connects outgoing to Socket.IO)

These are fundamentally different roles in the WebSocket architecture.

### Current Implementation

`magnetized_matchflow.sp` currently uses the raw socket extension directly to create CLIENT connections:

```sourcepawn
#tryinclude <socket>

// Creates client socket
g_Socket = SocketCreate(SOCKET_TCP, OnSocketError);
SocketConnect(g_Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, host, port);
```

This works but:
- ❌ Uses raw TCP sockets (not WebSocket protocol)
- ❌ Requires Socket.IO server to accept raw TCP
- ❌ No WebSocket handshake, framing, or masking

### Integration Paths

#### Option 1: Add WebSocket Client Mode to sm-websocket (RECOMMENDED)

Extend `sm-websocket` to support **client mode**:

```sourcepawn
// Proposed API for client connections
WebsocketHandle ws = Websocket_Connect(
    "wss://chat.magnetized.org:8080",
    "/socket.io",
    OnWSReceive,
    OnWSDisconnect,
    OnWSError
);

Websocket_Send(ws, SendType_Text, jsonPayload);
```

**Benefits:**
- ✅ Full WebSocket protocol support (RFC 6455)
- ✅ Can connect to Socket.IO servers properly
- ✅ Handles handshake, framing, masking automatically
- ✅ TLS/SSL support (wss://)
- ✅ Reuses existing sm-websocket infrastructure

**Implementation TODO:**
1. Add `Websocket_Connect()` native for client connections
2. Implement WebSocket client handshake (Sec-WebSocket-Key generation)
3. Add client-side frame masking (required by RFC 6455)
4. Handle Upgrade response parsing
5. Support Socket.IO transport negotiation

#### Option 2: Use sm-websocket for Server-to-Server

If backend can also be a WebSocket client, reverse the architecture:

```
CS:GO Server (sm-websocket server) ← Backend (WebSocket client connects in)
```

**Benefits:**
- ✅ Works with current sm-websocket (server-only)
- ✅ CS:GO server stays accessible without outbound firewall rules

**Drawbacks:**
- ❌ Requires backend architecture changes
- ❌ CS:GO server must be publicly accessible
- ❌ Less common pattern

#### Option 3: Keep Current Raw Socket Implementation

Continue using raw socket extension for magnetized_matchflow.sp:

**Benefits:**
- ✅ Already implemented and working
- ✅ No code changes needed

**Drawbacks:**
- ❌ Not using WebSocket protocol
- ❌ Requires custom backend protocol
- ❌ No standard WebSocket/Socket.IO compatibility

### Recommended Next Steps

**Short Term (Current State):**
- Keep `magnetized_matchflow.sp` using raw socket extension
- Keep `sm-websocket` for other plugins that need WebSocket server
- Document the architectural difference

**Long Term (Future Enhancement):**
1. Extend `sm-websocket` with client mode support
2. Add `Websocket_Connect()` API
3. Migrate `magnetized_matchflow.sp` to use WebSocket client API
4. Enable Socket.IO compatibility

### Example: Future Migration

**Current (Raw Socket):**
```sourcepawn
g_Socket = SocketCreate(SOCKET_TCP, OnSocketError);
SocketConnect(g_Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "chat.magnetized.org", 8080);
SocketSend(g_Socket, jsonData);
```

**Future (WebSocket Client):**
```sourcepawn
g_WebSocket = Websocket_Connect(
    "wss://chat.magnetized.org:8080",
    "/socket.io",
    OnWebSocketReceive,
    OnWebSocketDisconnect,
    OnWebSocketError
);
Websocket_Send(g_WebSocket, SendType_Text, jsonData);
```

### Files Affected

- **sm-websocket/scripting/websocket.sp** - Add client mode
- **sm-websocket/scripting/include/websocket.inc** - Add `Websocket_Connect` native
- **magnetized/csco-plugin/magnetized_matchflow.sp** - Migrate to WebSocket client API (once available)

### WebSocket Client Requirements (RFC 6455)

1. **Client Handshake:**
   - Generate Sec-WebSocket-Key (16 bytes base64)
   - Send HTTP Upgrade request
   - Validate Sec-WebSocket-Accept response

2. **Client Frame Masking:**
   - ALL client→server frames MUST be masked
   - Generate 4-byte random masking key per frame
   - XOR payload with masking key

3. **Connection Lifecycle:**
   - CONNECTING → OPEN → CLOSING → CLOSED
   - Handle close handshake (send→wait→receive→close)

4. **Socket.IO Compatibility:**
   - Support /socket.io path prefix
   - Handle Engine.IO transport negotiation
   - Parse Socket.IO packet format (JSON with type prefixes)

---

## Conclusion

**Current State:** sm-websocket and magnetized_matchflow serve different purposes and cannot be directly integrated yet.

**Future State:** Extend sm-websocket with WebSocket client mode to enable full protocol support for magnetized_matchflow.

**Action Item:** Document this architectural decision and plan for future client mode implementation.
