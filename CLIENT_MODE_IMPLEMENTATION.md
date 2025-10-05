# WebSocket Client Mode Implementation Plan

## Status: In Progress

### Completed ✅
1. Updated `websocket.inc` with client API:
   - Added `Websocket_Connect()` native declaration
   - Added `WebsocketConnectCB` callback typedef
   - Updated documentation for client/server dual mode

2. Added client data structures to `websocket.sp`:
   - `g_hClientSockets` - Client socket handles
   - `g_hClientSocketIndexes` - Pseudo-handles
   - `g_hClientSocketPlugins` - Plugin associations
   - `g_hClientSocket*` - Host, port, path, state tracking
   - `g_hClient*Forwards` - Callback forwards

3. Registered `Websocket_Connect` native in `AskPluginLoad2()`

4. Initialize client arrays in `OnPluginStart()`

5. Clean up client sockets in `OnPluginEnd()`

### In Progress 🔄
6. Implement `Native_Websocket_Connect()` - **NEEDS COMPLETION**
   - URL parsing (ws:// vs wss://)
   - Socket creation and connection
   - Callback registration

7. Implement client handshake generation - **NEEDS COMPLETION**
   - Generate random Sec-WebSocket-Key (16 bytes, base64)
   - Build HTTP Upgrade request
   - Send handshake to server

8. Implement client handshake validation - **NEEDS COMPLETION**
   - Parse HTTP 101 response
   - Validate Sec-WebSocket-Accept header
   - Trigger connect callback on success

9. Implement client frame masking - **CRITICAL RFC 6455 REQUIREMENT**
   - Generate random 4-byte masking key per frame
   - Mask all payload bytes: `masked[i] = payload[i] XOR mask[i % 4]`
   - Set MASK bit in frame header
   - This is MANDATORY for client→server frames

10. Update `Websocket_Send()` to detect client vs server sockets
    - Check if socket is client connection
    - Apply masking for client frames
    - Keep unmasked for server frames

### Not Started ⏳
11. Client socket callbacks:
    - `OnClientSocketConnected()`
    - `OnClientSocketReceive()`
    - `OnClientSocketDisconnect()`
    - `OnClientSocketError()`

12. Client frame handling:
    - Reuse existing `ParseFrame()` (works for both)
    - Create `HandleClientWebSocketFrame()`
    - Client receives UNMASKED frames from server

13. Helper functions:
    - `ParseWebSocketURL()` - Extract scheme, host, port
    - `GenerateWebSocketKey()` - Random 16 bytes + base64
    - `ValidateHandshakeResponse()` - Check HTTP 101 + headers
    - `SendClientWebsocketFrame()` - WITH masking

14. Update `Websocket_Close()` to handle client sockets

---

## Implementation File Structure

The full client implementation has been drafted in `websocket_client_impl.sp` with these key functions:

### Core Native
```sourcepawn
public int Native_Websocket_Connect(Handle plugin, int numParams)
```
- Parses URL and path
- Creates socket (TCP or TLS)
- Stores client data and callbacks
- Initiates connection

### Handshake Functions
```sourcepawn
void SendClientHandshake(int iIndex, Handle socket)
void GenerateWebSocketKey(char[] output, int maxlen)
void HandleClientHandshakeResponse(int iIndex, const char[] receiveData, int dataSize)
```

### Frame Functions
```sourcepawn
bool SendClientWebsocketFrame(int iIndex, char[] sPayLoad, WebsocketFrame vFrame)
bool PackClientFrame(char[] sPayLoad, char[] sFrame, WebsocketFrame vFrame)
void GenerateMaskingKey(char[] key)
```

### Socket Callbacks
```sourcepawn
public void OnClientSocketConnected(Handle socket, any arg)
public void OnClientSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
public void OnClientSocketDisconnect(Handle socket, any arg)
public void OnClientSocketError(Handle socket, int errorType, int errorNum, any arg)
```

### URL Parsing
```sourcepawn
bool ParseWebSocketURL(const char[] url, char[] scheme, int schemeLen, char[] host, int hostLen, int &port)
```

---

## RFC 6455 Client Requirements

### §5.3 Client-to-Server Masking (MANDATORY)
> A client MUST mask all frames that it sends to the server.

**Implementation:**
```sourcepawn
// Generate random masking key
void GenerateMaskingKey(char[] key) {
    int random = GetURandomInt();
    key[0] = random & 0xFF;
    key[1] = (random >> 8) & 0xFF;
    key[2] = (random >> 16) & 0xFF;
    key[3] = (random >> 24) & 0xFF;
}

// Apply masking to payload
for (int i = 0; i < payload_len; i++) {
    masked[i] = payload[i] ^ masking_key[i % 4];
}

// Set MASK bit in second byte
frame[1] |= 0x80; // Set bit 7
```

### §4.2 Client Handshake
**Request:**
```http
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```

**Response:**
```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

**Key Generation:**
1. Generate 16 random bytes
2. Base64 encode → Sec-WebSocket-Key
3. Server computes: `base64(SHA1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))`
4. Client validates Sec-WebSocket-Accept matches

---

## Integration Steps

### Step 1: Add URL Parser
```sourcepawn
// Insert after line 1350 (before utility functions)
bool ParseWebSocketURL(const char[] url, char[] scheme, int schemeLen, char[] host, int hostLen, int &port) {
    // ... implementation from websocket_client_impl.sp ...
}
```

### Step 2: Add Client Native
```sourcepawn
// Insert after Native_Websocket_Open()
public int Native_Websocket_Connect(Handle plugin, int numParams) {
    // ... implementation from websocket_client_impl.sp ...
}
```

### Step 3: Add Client Callbacks
```sourcepawn
// Insert after OnSocketIncoming()
public void OnClientSocketConnected(Handle socket, any arg) {
    // ... implementation ...
}
```

### Step 4: Add Handshake Functions
```sourcepawn
// Insert before utility functions
void SendClientHandshake(int iIndex, Handle socket) {
    // ... implementation ...
}
```

### Step 5: Add Frame Masking
```sourcepawn
// Update PackFrame() or create PackClientFrame()
bool PackClientFrame(char[] sPayLoad, char[] sFrame, WebsocketFrame vFrame) {
    // ... WITH masking ...
}
```

### Step 6: Update Websocket_Send()
```sourcepawn
// Detect if socket is client connection
if (IsClientSocket(websocketHandle)) {
    return SendClientWebsocketFrame(iIndex, sPayLoad, vFrame);
} else {
    return SendWebsocketFrame(iIndex, sPayLoad, vFrame);
}
```

---

## Testing Plan

### Test 1: Echo Server
```sourcepawn
#include <websocket>

public void OnPluginStart() {
    WebsocketHandle ws = Websocket_Connect(
        "ws://echo.websocket.org",
        "/",
        OnConnect,
        OnReceive,
        OnDisconnect,
        OnError
    );
}

public void OnConnect(WebsocketHandle ws) {
    PrintToServer("Connected!");
    Websocket_Send(ws, SendType_Text, "Hello, WebSocket!");
}

public void OnReceive(WebsocketHandle ws, WebsocketSendType type, const char[] data, int dataSize) {
    PrintToServer("Received: %s", data);
}
```

### Test 2: TLS Connection
```sourcepawn
WebsocketHandle ws = Websocket_Connect(
    "wss://echo.websocket.org",  // TLS
    "/",
    OnConnect,
    OnReceive,
    OnDisconnect,
    OnError
);
```

### Test 3: Socket.IO Compatibility
```sourcepawn
WebsocketHandle ws = Websocket_Connect(
    "ws://localhost:8080",
    "/socket.io",  // Socket.IO path
    OnConnect,
    OnReceive,
    OnDisconnect,
    OnError
);
```

---

## File Sizes & Estimates

- **websocket.sp** current: 1,410 lines
- **Client implementation**: ~800 lines
- **Expected total**: ~2,200 lines
- **Compilation**: Should compile without errors if integrated carefully

---

## Next Actions

1. **Integrate URL parser** into websocket.sp
2. **Add Native_Websocket_Connect()** with full implementation
3. **Add client socket callbacks** (4 functions)
4. **Implement client handshake** (send + validate)
5. **Add frame masking** (CRITICAL - must be correct)
6. **Update Websocket_Send()** to handle both modes
7. **Test with echo server**
8. **Update README** with client examples
9. **Update INTEGRATION_NOTES** with migration guide

---

## Estimated Completion Time

- **Core implementation**: 4-6 hours
- **Testing & debugging**: 2-3 hours
- **Documentation updates**: 1-2 hours
- **Total**: ~8-11 hours of focused development

---

## Immediate Next Step

Integrate the client implementation from `websocket_client_impl.sp` into the main `websocket.sp` file, section by section, testing compilation after each major addition.

**Start with:** URL parser + Native_Websocket_Connect skeleton
**Then add:** Client callbacks + handshake
**Finally add:** Frame masking + send functions

---

**Status**: Ready for implementation. All design decisions made, code drafted, RFC requirements documented.
