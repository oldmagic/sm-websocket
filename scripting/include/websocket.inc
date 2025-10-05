#if defined _websocket_included
  #endinput
#endif
#define _websocket_included

/**
 * WebSocket Ready State enumeration (RFC 6455)
 * Represents the current state of a WebSocket connection
 */
enum WebsocketReadyState {
	State_Connecting = 0,  // Connection is being established
	State_Open = 1,        // Connection is open and ready for communication
	State_Closing = 2,     // Connection is closing (closing handshake started)
	State_Closed = 3       // Connection is closed or couldn't be opened
}

/**
 * WebSocket handle type
 * Used to reference WebSocket connections (both master and child)
 */
enum WebsocketHandle {
	INVALID_WEBSOCKET_HANDLE = 0
}

/**
 * WebSocket send data type
 * Specifies the type of data being sent over the WebSocket
 */
enum WebsocketSendType {
	SendType_Text = 0,    // UTF-8 encoded text data
	SendType_Binary = 1   // Raw binary data
}

/**
 * Called when an unrecoverable error occurs on the master socket
 *
 * @param websocket     The websocket handle pointing to the calling websocket
 * @param errorType     The error type (see socket.inc for error types)
 * @param errorNum      The errno value (see errno.h for details)
 * @noreturn
 */
typedef WebsocketErrorCB = function void(
	WebsocketHandle websocket, 
	int errorType, 
	int errorNum
);

/**
 * Called when a master websocket is closed
 *
 * @param websocket     The websocket handle pointing to the calling websocket
 * @noreturn
 */
typedef WebsocketCloseCB = function void(WebsocketHandle websocket);

/**
 * Triggered when a client connects to the websocket server
 *
 * @param websocket     The websocket handle pointing to the listen socket
 * @param newWebsocket  The websocket handle to the newly created child socket
 * @param remoteIP      The remote IP address of the client
 * @param remotePort    The remote port of the client
 * @param protocols     Buffer containing client's supported subprotocols (comma-separated)
 *                      Modify this to select one protocol to use
 * @param getPath       The HTTP GET path sent by the client during handshake
 * @return              Plugin_Continue to accept connection, Plugin_Handled to reject
 */
typeset WebsocketIncomingCB {
	function Action(
		WebsocketHandle websocket, 
		WebsocketHandle newWebsocket, 
		const char[] remoteIP, 
		int remotePort, 
		char protocols[256]
	);
	
	function Action(
		WebsocketHandle websocket, 
		WebsocketHandle newWebsocket, 
		const char[] remoteIP, 
		int remotePort, 
		char protocols[256], 
		const char[] getPath
	);
}

/**
 * Triggered when a websocket receives data
 *
 * @note This callback is binary-safe when using dataSize for operations
 * @note Packets may be split into multiple chunks (multiple callback calls)
 * @note Unless configured otherwise with SocketSetOption, receiveData will
 *       not exceed 4096 characters including null terminator
 *
 * @param websocket     The websocket handle pointing to the calling socket
 * @param iType         The type of data received (Text or Binary)
 * @param receiveData   The received data (null-terminated at receiveData[dataSize])
 * @param dataSize      The length of received data (excluding null terminator)
 * @noreturn
 */
typedef WebsocketReceiveCB = function void(
	WebsocketHandle websocket, 
	WebsocketSendType iType, 
	const char[] receiveData, 
	int dataSize
);

/**
 * Called when a socket has been properly disconnected by the remote side
 *
 * @param websocket     The websocket handle pointing to the calling socket
 * @noreturn
 */
typedef WebsocketDisconnectCB = function void(WebsocketHandle websocket);

/**
 * Called when the ready state of a child socket changes
 *
 * @note Only fires for State_Open and State_Closing transitions
 *
 * @param websocket     The websocket handle pointing to the calling socket
 * @param readystate    The new ready state of the child socket
 * @noreturn
 */
typedef WebsocketReadyStateChangedCB = function void(
	WebsocketHandle websocket, 
	WebsocketReadyState readystate
);

/**
 * Called when a client WebSocket connection is successfully established
 *
 * @param websocket     The websocket handle for the client connection
 * @noreturn
 */
typedef WebsocketConnectCB = function void(WebsocketHandle websocket);

/**
 * Creates a websocket server that listens on the specified IP and port
 *
 * @note Multiple plugins can share the same IP:port combination
 * @note Always call Websocket_Close() in OnPluginEnd() to clean up
 *
 * @param sHostName     The IP address to bind to (e.g., "0.0.0.0" for all interfaces)
 * @param iPort         The port to listen on
 * @param inc           Callback for incoming client connections
 * @param we            Callback for socket errors
 * @param clo           Callback when the socket is closed
 * @return              A WebsocketHandle on success, INVALID_WEBSOCKET_HANDLE on failure
 * @error               Throws error if socket creation/binding fails
 */
native WebsocketHandle Websocket_Open(
	const char[] sHostName, 
	int iPort, 
	WebsocketIncomingCB inc, 
	WebsocketErrorCB we, 
	WebsocketCloseCB clo
);

/**
 * Connects to a remote WebSocket server as a client
 *
 * @note Use ws:// for plain connections, wss:// for TLS (requires socket extension with TLS)
 * @note Always call Websocket_Close() when done to clean up
 * @note The path parameter is used in the HTTP Upgrade request (e.g., "/socket.io")
 *
 * @param url           The WebSocket URL (e.g., "ws://example.com:8080" or "wss://example.com:443")
 * @param path          The HTTP path for the connection (e.g., "/" or "/socket.io")
 * @param onConnect     Callback when connection is established
 * @param onReceive     Callback for received data
 * @param onDisconnect  Callback when disconnected
 * @param onError       Callback for errors
 * @return              A WebsocketHandle on success, INVALID_WEBSOCKET_HANDLE on failure
 * @error               Throws error if URL parsing fails or socket creation fails
 */
native WebsocketHandle Websocket_Connect(
	const char[] url,
	const char[] path,
	WebsocketConnectCB onConnect,
	WebsocketReceiveCB onReceive,
	WebsocketDisconnectCB onDisconnect,
	WebsocketErrorCB onError
);

/**
 * Hooks events for a child socket (client connection)
 *
 * @note Must be called in the WebsocketIncomingCB callback to handle the connection
 * @note If no plugin hooks a child socket, it will be automatically closed
 *
 * @param childwebsocket    The child websocket to hook
 * @param recv              Callback for received data
 * @param disc              Callback for disconnection
 * @param we                Callback for errors
 * @return                  True on success, false otherwise
 * @error                   Throws error if childwebsocket is invalid
 */
native bool Websocket_HookChild(
	WebsocketHandle childwebsocket, 
	WebsocketReceiveCB recv, 
	WebsocketDisconnectCB disc, 
	WebsocketErrorCB we
);

/**
 * Hooks ready state change events for a child socket
 *
 * @note Optional - only needed if you want to track state transitions
 *
 * @param childwebsocket    The child websocket to hook
 * @param readystate        Callback for ready state changes
 * @return                  True on success, false otherwise
 * @error                   Throws error if childwebsocket is invalid
 */
native bool Websocket_HookReadyStateChange(
	WebsocketHandle childwebsocket, 
	WebsocketReadyStateChangedCB readystate
);

/**
 * Sends text or binary data through the websocket
 *
 * @note For binary data containing null bytes, always specify dataSize
 * @note The socket must be in State_Open to send data
 * @note For client connections, frames are automatically masked per RFC 6455
 *
 * @param childwebsocket    The child or client websocket to send data through
 * @param type              The data type (SendType_Text or SendType_Binary)
 * @param sPayload          The data to send
 * @param dataSize          Length of data to send (-1 to auto-detect using strlen)
 *                          Use actual length for binary data with embedded nulls
 * @return                  True if data was sent, false otherwise
 * @error                   Throws error if childwebsocket is invalid
 */
native bool Websocket_Send(
	WebsocketHandle childwebsocket, 
	WebsocketSendType type, 
	const char[] sPayload, 
	int dataSize = -1
);

/**
 * Gets the current ready state of a child websocket
 *
 * @param childwebsocket    The child websocket to query
 * @return                  The current WebsocketReadyState
 * @error                   Throws error if childwebsocket is invalid
 */
native WebsocketReadyState Websocket_GetReadyState(WebsocketHandle childwebsocket);

/**
 * Unhooks all events from a child socket
 *
 * @note If no plugins are listening to the socket after unhooking,
 *       the socket will be automatically closed with close code 1000
 *
 * @param childwebsocket    The child websocket to unhook
 * @noreturn
 * @error                   Throws error if childwebsocket is invalid
 */
native void Websocket_UnhookChild(WebsocketHandle childwebsocket);

/**
 * Closes a listening master socket or client connection
 *
 * @note For master sockets: remains open if other plugins are still using it
 * @note For client connections: closes the connection with code 1000 (normal closure)
 * @note Always call this in OnPluginEnd() to properly clean up resources
 * @note All associated child sockets will be closed with code 1001
 *
 * @param websocket         The master or client websocket to close
 * @noreturn
 * @error                   Throws error if websocket is invalid
 */
native void Websocket_Close(WebsocketHandle websocket);

/**
 * Shared plugin interface
 */
public SharedPlugin __pl_websocket = {
	name = "websocket",
	file = "websocket.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

/**
 * Mark natives as optional if plugin is not required
 */
#if !defined REQUIRE_PLUGIN
public void __pl_websocket_SetNTVOptional() {
	MarkNativeAsOptional("Websocket_Open");
	MarkNativeAsOptional("Websocket_Connect");
	MarkNativeAsOptional("Websocket_HookReadyStateChange");
	MarkNativeAsOptional("Websocket_HookChild");
	MarkNativeAsOptional("Websocket_Send");
	MarkNativeAsOptional("Websocket_GetReadyState");
	MarkNativeAsOptional("Websocket_UnhookChild");
	MarkNativeAsOptional("Websocket_Close");
}
#endif