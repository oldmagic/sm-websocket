# sm-websocket

**RFC 6455 WebSocket Protocol Implementation for SourceMod**

A server-side WebSocket protocol implementation that enables real-time bidirectional communication between game servers and web browsers, Socket.IO servers, or any WebSocket client.

[![SourceMod](https://img.shields.io/badge/SourceMod-1.11+-orange.svg)](https://www.sourcemod.net/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

---

## 📋 Table of Contents

- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [API Reference](#-api-reference)
- [Usage Examples](#-usage-examples)
- [Architecture](#-architecture)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## ✨ Features

- **Full RFC 6455 Compliance** - Complete WebSocket protocol implementation (Version 13)
- **Server-Side WebSocket** - Act as a WebSocket server accepting incoming connections
- **Multi-Plugin Support** - Multiple plugins can share the same WebSocket port
- **Fragment Support** - Handles fragmented messages automatically
- **Control Frames** - Ping/Pong, Close handshake with proper reason codes
- **Binary & Text** - Support for both text and binary WebSocket frames
- **Ready State Tracking** - Connection lifecycle management (Connecting, Open, Closing, Closed)
- **Modern Syntax** - Compiled with SourceMod 1.11+ using modern SourcePawn

---

## 📦 Requirements

### Server Requirements
- **SourceMod 1.11 or newer**
- **Socket Extension v3.0+** ([sm-ext-socket](https://github.com/oldmagic/sm-ext-socket))
  - Provides raw TCP/UDP socket functionality
  - Must be compiled with or without TLS support

### Development Requirements
- **SourcePawn Compiler 1.11+** (spcomp/spcomp64)
- Include files:
  - `sourcemod.inc` (standard)
  - `socket.inc` (from socket extension)
  - `regex.inc` (standard)
  - `base64.inc` (included in this repository)
  - `sha1.inc` (included in this repository)

---

## 🚀 Installation

### Option 1: Pre-compiled Plugin (Recommended)

1. **Download the compiled plugin:**
   ```bash
   # The plugin is already compiled in this repository
   cp compiled/websocket.smx /path/to/gameserver/addons/sourcemod/plugins/
   ```

2. **Install the socket extension:**
   ```bash
   # Download from https://github.com/oldmagic/sm-ext-socket
   cp socket.ext.so /path/to/gameserver/addons/sourcemod/extensions/
   # or socket.ext.dll for Windows
   ```

3. **Restart your server or load the plugin:**
   ```
   sm plugins load websocket
   ```

### Option 2: Compile from Source

1. **Clone this repository:**
   ```bash
   git clone https://github.com/oldmagic/sm-websocket.git
   cd sm-websocket
   ```

2. **Compile the plugin:**
   ```bash
   ./spcomp64 -i scripting/include scripting/websocket.sp -o compiled/websocket.smx
   ```

3. **Copy files to your server:**
   ```bash
   cp compiled/websocket.smx /path/to/gameserver/addons/sourcemod/plugins/
   cp scripting/include/websocket.inc /path/to/gameserver/addons/sourcemod/scripting/include/
   ```

---

## 🎯 Quick Start

### Basic WebSocket Server Example

```sourcepawn
#include <sourcemod>
#include <websocket>

#pragma newdecls required
#pragma semicolon 1

WebsocketHandle g_hListenSocket = INVALID_WEBSOCKET_HANDLE;

public void OnPluginStart()
{
    // Create a WebSocket server on port 8080
    g_hListenSocket = Websocket_Open(
        "0.0.0.0",                    // Listen on all interfaces
        8080,                          // Port
        OnWebSocketIncoming,           // Incoming connection callback
        OnWebSocketError,              // Error callback
        OnWebSocketClose               // Close callback
    );
    
    if (g_hListenSocket == INVALID_WEBSOCKET_HANDLE)
    {
        SetFailState("Failed to create WebSocket server on port 8080");
    }
    
    PrintToServer("[WebSocket] Server listening on port 8080");
}

public void OnPluginEnd()
{
    if (g_hListenSocket != INVALID_WEBSOCKET_HANDLE)
    {
        Websocket_Close(g_hListenSocket);
    }
}

// Called when a client connects
public void OnWebSocketIncoming(WebsocketHandle serverSocket, WebsocketHandle childSocket,
                                const char[] remoteIP, int remotePort,
                                const char[] path, const char[] protocol)
{
    PrintToServer("[WebSocket] New connection from %s:%d (Path: %s)", remoteIP, remotePort, path);
    
    // Hook the child socket to receive messages
    Websocket_HookChild(childSocket, OnWebSocketReceive, OnWebSocketDisconnect, OnWebSocketChildError);
    
    // Optional: Hook ready state changes
    Websocket_HookReadyStateChange(childSocket, OnWebSocketReadyStateChanged);
    
    // Send a welcome message
    Websocket_Send(childSocket, SendType_Text, "Welcome to the server!");
}

// Called when data is received from a client
public void OnWebSocketReceive(WebsocketHandle childSocket, WebsocketSendType sendType,
                               const char[] data, int dataSize)
{
    PrintToServer("[WebSocket] Received %d bytes: %s", dataSize, data);
    
    // Echo the message back
    Websocket_Send(childSocket, sendType, data);
}

// Called when a client disconnects
public void OnWebSocketDisconnect(WebsocketHandle childSocket)
{
    PrintToServer("[WebSocket] Client disconnected");
    Websocket_UnhookChild(childSocket);
}

// Called when an error occurs on child socket
public void OnWebSocketChildError(WebsocketHandle childSocket, int errorType, int errorNum)
{
    PrintToServer("[WebSocket] Child socket error: type=%d, num=%d", errorType, errorNum);
}

// Called when ready state changes
public void OnWebSocketReadyStateChanged(WebsocketHandle childSocket, WebsocketReadyState state)
{
    PrintToServer("[WebSocket] Ready state changed to: %d", state);
}

// Called when an error occurs on server socket
public void OnWebSocketError(WebsocketHandle serverSocket, int errorType, int errorNum)
{
    PrintToServer("[WebSocket] Server error: type=%d, num=%d", errorType, errorNum);
}

// Called when server socket is closed
public void OnWebSocketClose(WebsocketHandle serverSocket)
{
    PrintToServer("[WebSocket] Server closed");
    g_hListenSocket = INVALID_WEBSOCKET_HANDLE;
}
```

---

## 📚 API Reference

### Core Functions

#### `Websocket_Open`
Creates a WebSocket server listening on a specific address and port.

```sourcepawn
WebsocketHandle Websocket_Open(
    const char[] hostname,           // IP address or hostname to bind (e.g., "0.0.0.0")
    int port,                        // Port to listen on
    WebSocket_OnIncomingConnection incoming,  // Callback for new connections
    WebSocket_OnError error,         // Callback for errors
    WebSocket_OnClosed close         // Callback when socket closes
);
```

**Returns:** `WebsocketHandle` or `INVALID_WEBSOCKET_HANDLE` on failure

---

#### `Websocket_HookChild`
Hooks callbacks to a connected client socket.

```sourcepawn
bool Websocket_HookChild(
    WebsocketHandle childSocket,     // Child socket handle
    WebSocket_OnMessage receive,     // Callback for received messages
    WebSocket_OnDisconnect disconnect, // Callback for disconnection
    WebSocket_OnError error          // Callback for errors
);
```

**Returns:** `true` on success

---

#### `Websocket_Send`
Sends data to a connected client.

```sourcepawn
bool Websocket_Send(
    WebsocketHandle childSocket,     // Child socket handle
    WebsocketSendType sendType,      // SendType_Text or SendType_Binary
    const char[] data,               // Data to send
    int dataLen = -1                 // Length (-1 for null-terminated strings)
);
```

**Returns:** `true` on success

---

#### `Websocket_GetReadyState`
Gets the current connection state.

```sourcepawn
WebsocketReadyState Websocket_GetReadyState(WebsocketHandle childSocket);
```

**Returns:** Current ready state (Connecting, Open, Closing, Closed)

---

#### `Websocket_UnhookChild`
Removes all hooks from a child socket and closes it if no other plugins are using it.

```sourcepawn
void Websocket_UnhookChild(WebsocketHandle childSocket);
```

---

#### `Websocket_Close`
Closes the server socket and all connected clients.

```sourcepawn
void Websocket_Close(WebsocketHandle serverSocket);
```

---

### Enums

#### `WebsocketReadyState`
```sourcepawn
enum WebsocketReadyState {
    State_Connecting = 0,  // Handshake in progress
    State_Open = 1,        // Connection established
    State_Closing = 2,     // Close handshake initiated
    State_Closed = 3       // Connection closed
}
```

#### `WebsocketSendType`
```sourcepawn
enum WebsocketSendType {
    SendType_Text = 0,     // UTF-8 text data
    SendType_Binary = 1    // Binary data
}
```

---

## 💡 Usage Examples

### Example 1: Chat Server

```sourcepawn
#include <sourcemod>
#include <websocket>

ArrayList g_aConnectedClients;
WebsocketHandle g_hServer;

public void OnPluginStart()
{
    g_aConnectedClients = new ArrayList();
    g_hServer = Websocket_Open("0.0.0.0", 8080, OnIncoming, OnError, OnClose);
}

public void OnIncoming(WebsocketHandle server, WebsocketHandle client,
                      const char[] ip, int port, const char[] path, const char[] protocol)
{
    g_aConnectedClients.Push(client);
    Websocket_HookChild(client, OnMessage, OnDisconnect, OnChildError);
    
    // Broadcast join message
    char buffer[256];
    FormatEx(buffer, sizeof(buffer), "User from %s:%d joined!", ip, port);
    BroadcastMessage(buffer);
}

public void OnMessage(WebsocketHandle client, WebsocketSendType type,
                     const char[] data, int dataSize)
{
    // Broadcast to all clients
    BroadcastMessage(data);
}

void BroadcastMessage(const char[] message)
{
    int count = g_aConnectedClients.Length;
    for (int i = 0; i < count; i++)
    {
        WebsocketHandle client = g_aConnectedClients.Get(i);
        if (Websocket_GetReadyState(client) == State_Open)
        {
            Websocket_Send(client, SendType_Text, message);
        }
    }
}

public void OnDisconnect(WebsocketHandle client)
{
    int index = g_aConnectedClients.FindValue(client);
    if (index != -1)
    {
        g_aConnectedClients.Erase(index);
    }
    Websocket_UnhookChild(client);
}
```

---

### Example 2: Integration with Socket.IO Server

If you need to connect **to** a Socket.IO server (as a client), you'll need to implement the Socket.IO protocol on top of WebSocket. However, this plugin is designed as a **server** that accepts connections.

For Socket.IO client functionality, consider using HTTP polling or WebSocket client libraries.

---

### Example 3: Real-time Game Stats

```sourcepawn
#include <sourcemod>
#include <websocket>

WebsocketHandle g_hStatsServer;
ArrayList g_aWebClients;

public void OnPluginStart()
{
    g_aWebClients = new ArrayList();
    g_hStatsServer = Websocket_Open("0.0.0.0", 9000, OnWebClient, OnError, OnClose);
    
    // Hook game events
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
}

public void OnWebClient(WebsocketHandle server, WebsocketHandle client,
                       const char[] ip, int port, const char[] path, const char[] protocol)
{
    g_aWebClients.Push(client);
    Websocket_HookChild(client, OnWebMessage, OnWebDisconnect, OnWebError);
    
    // Send initial game state
    SendGameState(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    
    char buffer[512];
    FormatEx(buffer, sizeof(buffer), 
        "{\"event\":\"player_death\",\"victim\":\"%N\",\"attacker\":\"%N\"}",
        victim, attacker);
    
    BroadcastToWebClients(buffer);
}

void BroadcastToWebClients(const char[] json)
{
    int count = g_aWebClients.Length;
    for (int i = 0; i < count; i++)
    {
        WebsocketHandle client = g_aWebClients.Get(i);
        if (Websocket_GetReadyState(client) == State_Open)
        {
            Websocket_Send(client, SendType_Text, json);
        }
    }
}
```

---

## 🏗️ Architecture

### Protocol Flow

```
1. Client initiates TCP connection
   ↓
2. Client sends HTTP upgrade request with WebSocket headers
   ↓
3. Plugin validates Sec-WebSocket-Key
   ↓
4. Plugin generates Sec-WebSocket-Accept response
   ↓
5. Plugin sends HTTP 101 Switching Protocols
   ↓
6. Connection upgraded to WebSocket protocol
   ↓
7. Bidirectional frame-based communication
   ↓
8. Close handshake (either side can initiate)
```

### Frame Structure

WebSocket frames follow RFC 6455:
- **FIN bit**: Final fragment indicator
- **Opcode**: Frame type (text, binary, close, ping, pong)
- **Mask bit**: Client frames must be masked
- **Payload length**: 7, 16, or 64 bits
- **Masking key**: 4 bytes (if masked)
- **Payload**: Actual data

---

## 🔧 Troubleshooting

### Common Issues

#### "Invalid handle" errors
**Solution:** Make sure you're not using a socket handle after it's been closed. Check ready state before sending.

#### Connection timeouts
**Solution:** Ensure firewall allows incoming connections on your chosen port. Verify the socket extension is loaded (`sm exts list`).

#### Handshake failures
**Solution:** Client must send proper WebSocket upgrade headers. Check client implementation follows RFC 6455.

#### Messages not received
**Solution:** Ensure you've called `Websocket_HookChild()` with proper callbacks before the handshake completes.

### Debug Mode

Enable debug logging by modifying `DEBUG` define in `websocket.sp`:

```sourcepawn
#define DEBUG 2  // 0=off, 1=errors, 2=info, 3=verbose
```

Recompile and check `logs/websocket_debug.log`.

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow SourceMod coding standards
- Use modern SourcePawn syntax (`#pragma newdecls required`)
- Add comments for complex logic
- Test with multiple concurrent connections
- Verify RFC 6455 compliance

---

## 📄 License

This project is licensed under the GPL-3.0 License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Credits

- **Original Author:** Peace-Maker (Jannik Hartung)
- **Modernization:** 2025 update for SourceMod 1.11+
- **Socket Extension:** [sm-ext-socket](https://github.com/oldmagic/sm-ext-socket) by AlliedModders

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/oldmagic/sm-websocket/issues)
- **Documentation:** [RFC 6455 - The WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- **SourceMod:** [AlliedModders Forums](https://forums.alliedmods.net/)

---

**Made with ❤️ for the SourceMod community**