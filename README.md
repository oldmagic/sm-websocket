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
- [CS:GO Server Integration](#-csgo-server-integration)
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

## � CS:GO Server Integration

This section provides a complete guide for integrating WebSocket functionality into your CS:GO dedicated server.

### Directory Structure

```
csgo/
├── addons/
│   └── sourcemod/
│       ├── extensions/
│       │   └── socket.ext.so          # Socket extension (Linux)
│       │   └── socket.ext.dll         # Socket extension (Windows)
│       ├── plugins/
│       │   ├── websocket.smx          # WebSocket plugin (compiled)
│       │   └── your_plugin.smx        # Your plugin using WebSocket
│       ├── scripting/
│       │   ├── include/
│       │   │   ├── websocket.inc      # WebSocket API include
│       │   │   ├── base64.inc         # Base64 encoding
│       │   │   └── sha1.inc           # SHA-1 hashing
│       │   └── your_plugin.sp         # Your plugin source
│       ├── configs/
│       │   └── websocket.cfg          # WebSocket configuration (optional)
│       └── logs/
│           └── websocket_debug.log    # Debug log (if DEBUG enabled)
└── cfg/
    └── server.cfg                     # Server configuration
```

### Installation Steps

#### 1. Install Socket Extension

Download the Socket extension from [sm-ext-socket](https://github.com/oldmagic/sm-ext-socket):

**Linux:**
```bash
cd csgo/addons/sourcemod/extensions/
wget https://github.com/oldmagic/sm-ext-socket/releases/latest/download/socket.ext.so
chmod +x socket.ext.so
```

**Windows:**
Download `socket.ext.dll` and place it in `csgo/addons/sourcemod/extensions/`

#### 2. Install WebSocket Plugin

```bash
# Copy compiled plugin
cp compiled/websocket.smx csgo/addons/sourcemod/plugins/

# Copy include files (for development)
cp scripting/include/*.inc csgo/addons/sourcemod/scripting/include/
```

#### 3. Configure Convars

Create `csgo/addons/sourcemod/configs/websocket.cfg`:

```sourcepawn
// ===================================================================
// WebSocket Configuration
// ===================================================================

// WebSocket plugin version (read-only)
// Default: "2.0"
sm_websocket_version "2.0"

// ===================================================================
// Network Configuration (Set these in your plugin code, not here)
// ===================================================================
// WebSocket server port: 8550 (example)
// WebSocket bind address: "0.0.0.0" or "127.0.0.1"
// Note: These are set programmatically when calling Websocket_Open()
```

#### 4. Server Configuration

Add to `csgo/cfg/server.cfg`:

```sourcepawn
// ===================================================================
// SourceMod & Extensions
// ===================================================================

// Load SourceMod
sm plugins load_unlock
sm plugins load websocket

// ===================================================================
// Firewall & Network
// ===================================================================

// Open ports in firewall (example):
// - Game server: 27015 (TCP/UDP)
// - WebSocket: 8550 (TCP)

// Note: Configure your firewall to allow incoming connections:
// Linux (ufw): sudo ufw allow 8550/tcp
// Linux (iptables): iptables -A INPUT -p tcp --dport 8550 -j ACCEPT
// Windows: Add inbound rule for TCP port 8550
```

### Example Plugin for CS:GO

Create `csgo/addons/sourcemod/scripting/csgo_websocket_stats.sp`:

```sourcepawn
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <websocket>
#include <cstrike>

#define PLUGIN_VERSION "1.0"

// WebSocket handle
WebsocketHandle g_hWebSocket = INVALID_WEBSOCKET_HANDLE;

// Configuration
#define WS_HOST "0.0.0.0"  // Listen on all interfaces
#define WS_PORT 8550        // WebSocket port

public Plugin myinfo = {
    name = "CS:GO WebSocket Stats",
    author = "Your Name",
    description = "Broadcasts CS:GO game stats via WebSocket",
    version = PLUGIN_VERSION,
    url = "https://yourwebsite.com"
};

public void OnPluginStart() {
    // Open WebSocket server
    g_hWebSocket = Websocket_Open(
        WS_HOST,
        WS_PORT,
        OnWebSocketIncoming,
        OnWebSocketError,
        OnWebSocketClose
    );
    
    if (g_hWebSocket == INVALID_WEBSOCKET_HANDLE) {
        SetFailState("Failed to create WebSocket on %s:%d", WS_HOST, WS_PORT);
    }
    
    PrintToServer("[WebSocket] Server listening on %s:%d", WS_HOST, WS_PORT);
    
    // Hook CS:GO events
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
}

public void OnPluginEnd() {
    if (g_hWebSocket != INVALID_WEBSOCKET_HANDLE) {
        Websocket_Close(g_hWebSocket);
    }
}

// ===================================================================
// WebSocket Callbacks
// ===================================================================

public Action OnWebSocketIncoming(
    WebsocketHandle websocket,
    WebsocketHandle child,
    const char[] remoteIP,
    int remotePort,
    char[] protocols,
    const char[] path
) {
    PrintToServer("[WebSocket] Incoming connection from %s:%d (path: %s)", 
        remoteIP, remotePort, path);
    
    // Hook the child connection
    Websocket_HookChild(child, OnWebSocketReceive, OnWebSocketDisconnect, OnWebSocketChildError);
    Websocket_HookReadyStateChange(child, OnWebSocketReadyStateChange);
    
    // Send welcome message
    char welcomeMsg[256];
    FormatEx(welcomeMsg, sizeof(welcomeMsg), 
        "{\"type\":\"welcome\",\"server\":\"CS:GO Stats\",\"map\":\"%s\"}",
        GetCurrentMap());
    
    return Plugin_Continue;
}

public void OnWebSocketReceive(
    WebsocketHandle websocket,
    WebsocketSendType iType,
    const char[] receiveData,
    int dataSize
) {
    PrintToServer("[WebSocket] Received: %s", receiveData);
    
    // Parse JSON commands (example)
    if (StrContains(receiveData, "\"cmd\":\"get_players\"") != -1) {
        SendPlayerList(websocket);
    }
    else if (StrContains(receiveData, "\"cmd\":\"get_scores\"") != -1) {
        SendScores(websocket);
    }
}

public void OnWebSocketDisconnect(WebsocketHandle websocket) {
    PrintToServer("[WebSocket] Client disconnected");
}

public void OnWebSocketChildError(WebsocketHandle websocket, int errorType, int errorNum) {
    LogError("[WebSocket] Child error: type=%d, num=%d", errorType, errorNum);
}

public void OnWebSocketError(WebsocketHandle websocket, int errorType, int errorNum, int data) {
    LogError("[WebSocket] Master error: type=%d, num=%d", errorType, errorNum);
}

public void OnWebSocketClose(WebsocketHandle websocket) {
    PrintToServer("[WebSocket] Master socket closed");
}

public void OnWebSocketReadyStateChange(WebsocketHandle websocket, WebsocketReadyState newState) {
    PrintToServer("[WebSocket] Ready state changed to: %d", newState);
}

// ===================================================================
// CS:GO Event Handlers
// ===================================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    bool headshot = event.GetBool("headshot");
    
    // Broadcast to all WebSocket clients
    BroadcastEvent("player_death", victim, attacker, weapon, headshot);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    BroadcastSimpleEvent("round_start");
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    int winner = event.GetInt("winner");
    BroadcastRoundEnd(winner);
}

// ===================================================================
// Helper Functions
// ===================================================================

void BroadcastEvent(const char[] eventType, int victim, int attacker, const char[] weapon, bool headshot) {
    char victimName[64], attackerName[64];
    
    if (IsValidClient(victim)) {
        GetClientName(victim, victimName, sizeof(victimName));
    } else {
        strcopy(victimName, sizeof(victimName), "Unknown");
    }
    
    if (IsValidClient(attacker)) {
        GetClientName(attacker, attackerName, sizeof(attackerName));
    } else {
        strcopy(attackerName, sizeof(attackerName), "World");
    }
    
    char json[512];
    FormatEx(json, sizeof(json),
        "{\"type\":\"%s\",\"victim\":\"%s\",\"attacker\":\"%s\",\"weapon\":\"%s\",\"headshot\":%s,\"timestamp\":%d}",
        eventType, victimName, attackerName, weapon, headshot ? "true" : "false", GetTime());
    
    BroadcastToAll(json);
}

void BroadcastSimpleEvent(const char[] eventType) {
    char json[256];
    FormatEx(json, sizeof(json), 
        "{\"type\":\"%s\",\"timestamp\":%d}", eventType, GetTime());
    BroadcastToAll(json);
}

void BroadcastRoundEnd(int winner) {
    char json[256];
    FormatEx(json, sizeof(json),
        "{\"type\":\"round_end\",\"winner\":%d,\"timestamp\":%d}", winner, GetTime());
    BroadcastToAll(json);
}

void SendPlayerList(WebsocketHandle websocket) {
    char json[2048], playerData[128];
    strcopy(json, sizeof(json), "{\"type\":\"players\",\"list\":[");
    
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            char name[64];
            GetClientName(i, name, sizeof(name));
            
            FormatEx(playerData, sizeof(playerData),
                "{\"id\":%d,\"name\":\"%s\",\"team\":%d,\"score\":%d,\"deaths\":%d}",
                i, name, GetClientTeam(i), GetClientFrags(i), GetClientDeaths(i));
            
            StrCat(json, sizeof(json), playerData);
            if (i < MaxClients) StrCat(json, sizeof(json), ",");
        }
    }
    
    StrCat(json, sizeof(json), "]}");
    Websocket_Send(websocket, SendType_Text, json);
}

void SendScores(WebsocketHandle websocket) {
    int ctScore = GetTeamScore(CS_TEAM_CT);
    int tScore = GetTeamScore(CS_TEAM_T);
    
    char json[256];
    FormatEx(json, sizeof(json),
        "{\"type\":\"scores\",\"ct\":%d,\"t\":%d,\"map\":\"%s\"}",
        ctScore, tScore, GetCurrentMap());
    
    Websocket_Send(websocket, SendType_Text, json);
}

void BroadcastToAll(const char[] message) {
    // Note: You'd need to track all connected WebSocket children
    // and iterate through them to send to all clients
    // This is simplified for example purposes
    PrintToServer("[Broadcast] %s", message);
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client));
}

char[] GetCurrentMap() {
    char map[64];
    GetCurrentMap(map, sizeof(map));
    return map;
}
```

### Compiling the Plugin

```bash
cd csgo/addons/sourcemod/scripting/
./spcomp64 -i include csgo_websocket_stats.sp -o ../plugins/csgo_websocket_stats.smx
```

### Testing the Connection

#### Using Browser Console

```javascript
// Connect to WebSocket server
const ws = new WebSocket('ws://your-server-ip:8550');

ws.onopen = () => {
    console.log('Connected to CS:GO server');
    
    // Request player list
    ws.send(JSON.stringify({ cmd: 'get_players' }));
};

ws.onmessage = (event) => {
    console.log('Received:', JSON.parse(event.data));
};

ws.onerror = (error) => {
    console.error('WebSocket error:', error);
};

ws.onclose = () => {
    console.log('Disconnected');
};
```

#### Using Python

```python
import asyncio
import websockets
import json

async def connect():
    uri = "ws://your-server-ip:8550"
    async with websockets.connect(uri) as websocket:
        print("Connected to CS:GO server")
        
        # Request scores
        await websocket.send(json.dumps({"cmd": "get_scores"}))
        
        # Listen for events
        while True:
            message = await websocket.recv()
            data = json.loads(message)
            print(f"Event: {data['type']}")

asyncio.run(connect())
```

### Common Convars Reference

These convars are available in your plugin code:

```sourcepawn
// Example convar usage in your plugin
ConVar g_cvWebSocketEnabled;
ConVar g_cvWebSocketPort;
ConVar g_cvWebSocketHost;
ConVar g_cvBroadcastKills;
ConVar g_cvBroadcastRounds;

public void OnPluginStart() {
    // Create custom convars
    g_cvWebSocketEnabled = CreateConVar("sm_ws_enabled", "1", 
        "Enable WebSocket server", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    
    g_cvWebSocketPort = CreateConVar("sm_ws_port", "8550", 
        "WebSocket server port", FCVAR_NOTIFY, true, 1024.0, true, 65535.0);
    
    g_cvWebSocketHost = CreateConVar("sm_ws_host", "0.0.0.0", 
        "WebSocket bind address (0.0.0.0 = all interfaces)");
    
    g_cvBroadcastKills = CreateConVar("sm_ws_broadcast_kills", "1", 
        "Broadcast player deaths via WebSocket", FCVAR_NOTIFY);
    
    g_cvBroadcastRounds = CreateConVar("sm_ws_broadcast_rounds", "1", 
        "Broadcast round events via WebSocket", FCVAR_NOTIFY);
    
    // Auto-generate config file
    AutoExecConfig(true, "websocket_stats");
}
```

This generates `csgo/cfg/sourcemod/websocket_stats.cfg`:

```
// This file was auto-generated by SourceMod (v1.11.0)
// ConVars for plugin "csgo_websocket_stats.smx"

// Enable WebSocket server
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
sm_ws_enabled "1"

// WebSocket server port
// Default: "8550"
// Minimum: "1024.000000"
// Maximum: "65535.000000"
sm_ws_port "8550"

// WebSocket bind address (0.0.0.0 = all interfaces)
// Default: "0.0.0.0"
sm_ws_host "0.0.0.0"

// Broadcast player deaths via WebSocket
// Default: "1"
sm_ws_broadcast_kills "1"

// Broadcast round events via WebSocket
// Default: "1"
sm_ws_broadcast_rounds "1"
```

### Security Considerations

1. **Firewall Configuration**: Only open WebSocket ports to trusted networks
2. **Authentication**: Implement token-based authentication in your plugin
3. **Rate Limiting**: Limit message frequency to prevent spam
4. **Input Validation**: Always validate incoming JSON data
5. **TLS/SSL**: Consider using a reverse proxy (nginx) for wss:// connections

### Performance Tips

- Use `SendType_Binary` for large data transfers
- Implement message batching for high-frequency events
- Monitor `websocket_debug.log` for connection issues
- Keep payload sizes under 32KB for optimal performance
- Use JSON minification (no whitespace) for smaller messages

---

## �🏗️ Architecture

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

## ⚠️ Current Limitations & Future Plans

### Server-Only Mode

**Important:** This plugin currently operates in **server mode only**. It creates a WebSocket server that accepts incoming connections from WebSocket clients (browsers, Node.js, Python, etc.).

#### What This Means

✅ **Supported Use Cases:**
- Web browser connects to game server for live stats
- External monitoring tools connect to game server
- Admin panels connect to game server for control
- Multiple clients connecting to same game server

❌ **Not Yet Supported:**
- Game server connecting **OUT** to external WebSocket servers
- Socket.IO client connections from game server
- Connecting to Discord, Slack, or other WebSocket APIs
- Client-to-client direct connections

### Integration with Magnetized MatchFlow

If you're using this with `magnetized_matchflow.sp`, note that:

- **magnetized_matchflow.sp** needs **WebSocket client** mode (connect out to Socket.IO server)
- **sm-websocket** provides **WebSocket server** mode (accept incoming connections)

These are fundamentally different architectural roles. See [INTEGRATION_NOTES.md](INTEGRATION_NOTES.md) for detailed explanation and migration path.

#### Workaround Options

1. **Continue using raw socket extension** - magnetized_matchflow.sp works with raw TCP sockets
2. **Reverse the architecture** - Have backend connect TO the game server instead
3. **Wait for client mode** - Future enhancement to support outgoing WebSocket connections

### Planned Enhancements

Future versions may include:

- 🔄 **WebSocket Client Mode** - Connect to external WebSocket servers
- 🔌 **Socket.IO Protocol Layer** - Full Socket.IO client/server support
- 📦 **Connection Pooling** - Manage multiple WebSocket connections efficiently
- 🔐 **Authentication Extensions** - Built-in token-based auth support
- 📊 **Performance Monitoring** - Connection stats and metrics

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