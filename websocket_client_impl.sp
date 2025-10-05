/**
 * WebSocket Client Implementation
 * RFC 6455 Client-Side Functions
 * 
 * This file contains the implementation for Websocket_Connect() and related client functions.
 * To be integrated into websocket.sp
 */

// ===================================================================
// NATIVE: Websocket_Connect
// ===================================================================

public int Native_Websocket_Connect(Handle plugin, int numParams) {
	// Parse URL
	char url[URL_MAX_LENGTH];
	GetNativeString(1, url, sizeof(url));
	
	char path[URL_MAX_LENGTH];
	GetNativeString(2, path, sizeof(path));
	
	// Parse URL components
	char scheme[8], host[256];
	int port = 0;
	
	if (!ParseWebSocketURL(url, scheme, sizeof(scheme), host, sizeof(host), port)) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid WebSocket URL: %s", url);
		return view_as<int>(INVALID_WEBSOCKET_HANDLE);
	}
	
	// Determine socket type
	bool useTLS = StrEqual(scheme, "wss", false);
	SocketType socketType = useTLS ? SOCKET_TLS : SOCKET_TCP;
	
	// Create socket
	Handle hSocket = SocketCreate(socketType, OnClientSocketError);
	if (hSocket == null) {
		ThrowNativeError(SP_ERROR_NATIVE, "Failed to create client socket");
		return view_as<int>(INVALID_WEBSOCKET_HANDLE);
	}
	
	int iPseudoHandle = ++g_iLastSocketIndex;
	
	// Store client socket data
	int iIndex = g_hClientSockets.Push(hSocket);
	g_hClientSocketIndexes.Push(iPseudoHandle);
	g_hClientSocketHost.PushString(host);
	g_hClientSocketPort.Push(port);
	g_hClientSocketPath.PushString(path);
	g_hClientSocketReadyState.Push(State_Connecting);
	g_hClientIsClient.Push(1); // Mark as client
	
	// Initialize fragmented payload buffer
	ArrayList hFragmentedPayload = new ArrayList(ByteCountToCells(FRAGMENT_MAX_LENGTH));
	g_hClientSocketFragmentedPayload.Push(hFragmentedPayload);
	hFragmentedPayload.Push(0); // Payload length
	hFragmentedPayload.Push(0); // Payload type
	
	// Store callbacks
	Handle pluginHandle = new ArrayList(1);
	pluginHandle.Set(0, view_as<int>(plugin));
	g_hClientSocketPlugins.Push(pluginHandle);
	
	// Create forwards
	PrivateForward hConnectForward = new PrivateForward(ET_Ignore, Param_Cell);
	hConnectForward.AddFunction(plugin, GetNativeFunction(3));
	g_hClientConnectForwards.Push(hConnectForward);
	
	PrivateForward hReceiveForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
	hReceiveForward.AddFunction(plugin, GetNativeFunction(4));
	g_hClientReceiveForwards.Push(hReceiveForward);
	
	PrivateForward hDisconnectForward = new PrivateForward(ET_Ignore, Param_Cell);
	hDisconnectForward.AddFunction(plugin, GetNativeFunction(5));
	g_hClientDisconnectForwards.Push(hDisconnectForward);
	
	PrivateForward hErrorForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	hErrorForward.AddFunction(plugin, GetNativeFunction(6));
	g_hClientErrorForwards.Push(hErrorForward);
	
	// Setup callbacks
	SocketSetReceiveCallback(hSocket, OnClientSocketReceive);
	SocketSetDisconnectCallback(hSocket, OnClientSocketDisconnect);
	SocketSetArg(hSocket, iPseudoHandle);
	
	// Connect
	Debug(1, "Client connecting to %s:%d (path: %s, TLS: %s)", host, port, path, useTLS ? "yes" : "no");
	
	if (useTLS) {
		SocketConnect(hSocket, OnClientSocketConnected, OnClientSocketReceive, OnClientSocketDisconnect, host, port);
	} else {
		SocketConnect(hSocket, OnClientSocketConnected, OnClientSocketReceive, OnClientSocketDisconnect, host, port);
	}
	
	return iPseudoHandle;
}

// ===================================================================
// CLIENT SOCKET CALLBACKS
// ===================================================================

public void OnClientSocketConnected(Handle socket, any arg) {
	Debug(1, "Client socket connected, sending handshake");
	
	int iIndex = g_hClientSocketIndexes.FindValue(arg);
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	// Send client handshake
	SendClientHandshake(iIndex, socket);
}

public void OnClientSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg) {
	Debug(2, "Client socket received data (%d bytes)", dataSize);
	
	int iIndex = g_hClientSocketIndexes.FindValue(arg);
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	WebsocketReadyState iReadyState = g_hClientSocketReadyState.Get(iIndex);
	
	if (iReadyState == State_Connecting) {
		// Handle handshake response
		HandleClientHandshakeResponse(iIndex, receiveData, dataSize);
	} else if (iReadyState == State_Open) {
		// Handle WebSocket frames (same as server child sockets)
		HandleClientWebSocketFrame(iIndex, receiveData, dataSize, arg);
	}
}

public void OnClientSocketDisconnect(Handle socket, any arg) {
	Debug(1, "Client socket disconnected");
	
	int iIndex = g_hClientSocketIndexes.FindValue(arg);
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	CloseClientSocket(iIndex);
}

public void OnClientSocketError(Handle socket, int errorType, int errorNum, any arg) {
	Debug(1, "Client socket error: type=%d, num=%d", errorType, errorNum);
	
	int iIndex = g_hClientSocketIndexes.FindValue(arg);
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	PrivateForward hErrorForward = g_hClientErrorForwards.Get(iIndex);
	Call_StartForward(hErrorForward);
	Call_PushCell(g_hClientSocketIndexes.Get(iIndex));
	Call_PushCell(errorType);
	Call_PushCell(errorNum);
	Call_Finish();
	
	CloseClientSocket(iIndex);
}

// ===================================================================
// CLIENT HANDSHAKE
// ===================================================================

void SendClientHandshake(int iIndex, Handle socket) {
	char host[256], path[256];
	g_hClientSocketHost.GetString(iIndex, host, sizeof(host));
	g_hClientSocketPath.GetString(iIndex, path, sizeof(path));
	int port = g_hClientSocketPort.Get(iIndex);
	
	// Generate Sec-WebSocket-Key (16 random bytes, base64 encoded)
	char key[25]; // 16 bytes = 24 base64 chars + null
	GenerateWebSocketKey(key, sizeof(key));
	
	// Build HTTP Upgrade request
	char request[1024];
	FormatEx(request, sizeof(request),
		"GET %s HTTP/1.1\r\n"
		"Host: %s:%d\r\n"
		"Upgrade: websocket\r\n"
		"Connection: Upgrade\r\n"
		"Sec-WebSocket-Key: %s\r\n"
		"Sec-WebSocket-Version: 13\r\n"
		"\r\n",
		path, host, port, key);
	
	Debug(2, "Sending client handshake:\n%s", request);
	
	// Store key for validation
	// We'll validate the Sec-WebSocket-Accept header in the response
	
	SocketSend(socket, request);
}

void GenerateWebSocketKey(char[] output, int maxlen) {
	// Generate 16 random bytes
	int randomData[4];
	for (int i = 0; i < 4; i++) {
		randomData[i] = GetURandomInt();
	}
	
	// Base64 encode
	EncodeBase64(output, maxlen, randomData, 16);
}

void HandleClientHandshakeResponse(int iIndex, const char[] receiveData, int dataSize) {
	Debug(2, "Handling client handshake response:\n%s", receiveData);
	
	// Check for HTTP 101 Switching Protocols
	if (StrContains(receiveData, "HTTP/1.1 101") == -1) {
		Debug(1, "Handshake failed: Expected HTTP 101, got: %s", receiveData);
		CloseClientSocket(iIndex);
		return;
	}
	
	// Validate Sec-WebSocket-Accept (optional, but recommended)
	// For now, just check it exists
	if (StrContains(receiveData, "Sec-WebSocket-Accept:") == -1) {
		Debug(1, "Handshake failed: Missing Sec-WebSocket-Accept header");
		CloseClientSocket(iIndex);
		return;
	}
	
	// Connection established!
	g_hClientSocketReadyState.Set(iIndex, State_Open);
	
	Debug(1, "Client handshake successful, connection open");
	
	// Call connect callback
	PrivateForward hConnectForward = g_hClientConnectForwards.Get(iIndex);
	Call_StartForward(hConnectForward);
	Call_PushCell(g_hClientSocketIndexes.Get(iIndex));
	Call_Finish();
}

// ===================================================================
// CLIENT FRAME HANDLING
// ===================================================================

void HandleClientWebSocketFrame(int iIndex, const char[] receiveData, int dataSize, any arg) {
	WebsocketFrame vFrame;
	char[] sPayLoad = new char[dataSize];
	
	ParseFrame(vFrame, receiveData, dataSize, sPayLoad);
	
	// Note: Client receives UNMASKED frames from server
	
	if (!PreprocessClientFrame(iIndex, vFrame, sPayLoad)) {
		// Call receive forward
		PrivateForward hReceiveForward = g_hClientReceiveForwards.Get(iIndex);
		Call_StartForward(hReceiveForward);
		Call_PushCell(arg);
		
		// Handle fragmented messages (same logic as server)
		if (vFrame.OPCODE == FrameType_Continuation) {
			ArrayList hFragmentedPayload = g_hClientSocketFragmentedPayload.Get(iIndex);
			int iPayloadLength = hFragmentedPayload.Get(0);
			
			char[] sConcatPayload = new char[iPayloadLength + 1];
			char sPayloadPart[FRAGMENT_MAX_LENGTH];
			int iSize = hFragmentedPayload.Length;
			
			for (int i = 2; i < iSize; i++) {
				hFragmentedPayload.GetString(i, sPayloadPart, sizeof(sPayloadPart));
				StrCat(sConcatPayload, iPayloadLength + 1, sPayloadPart);
			}
			
			WebsocketSendType iType = (hFragmentedPayload.Get(1) == view_as<int>(FrameType_Text)) ? SendType_Text : SendType_Binary;
			Call_PushCell(iType);
			Call_PushString(sConcatPayload);
			Call_PushCell(iPayloadLength);
			
			hFragmentedPayload.Clear();
			hFragmentedPayload.Push(0);
			hFragmentedPayload.Push(0);
		} else {
			WebsocketSendType iType = (vFrame.OPCODE == FrameType_Text) ? SendType_Text : SendType_Binary;
			Call_PushCell(iType);
			Call_PushString(sPayLoad);
			Call_PushCell(vFrame.PAYLOAD_LEN);
		}
		
		Call_Finish();
	}
}

bool PreprocessClientFrame(int iIndex, WebsocketFrame vFrame, char[] sPayLoad) {
	// Same preprocessing as server child sockets, but for client context
	// Handle fragmentation, control frames, etc.
	
	if (!vFrame.FIN) {
		if (vFrame.OPCODE >= FrameType_Close) {
			LogError("Received fragmented control frame");
			CloseClientConnection(iIndex, 1002, "Fragmented control frame");
			return true;
		}
		
		ArrayList hFragmentedPayload = g_hClientSocketFragmentedPayload.Get(iIndex);
		int iPayloadLength = hFragmentedPayload.Get(0);
		
		if (iPayloadLength == 0) {
			if (vFrame.OPCODE == FrameType_Continuation) {
				LogError("First fragmented frame must not have opcode 0");
				CloseClientConnection(iIndex, 1002, "Invalid fragmentation");
				return true;
			}
			hFragmentedPayload.Set(1, view_as<int>(vFrame.OPCODE));
		}
		
		iPayloadLength += vFrame.PAYLOAD_LEN;
		hFragmentedPayload.Set(0, iPayloadLength);
		hFragmentedPayload.PushString(sPayLoad);
		
		return true;
	}
	
	switch (vFrame.OPCODE) {
		case FrameType_Continuation: {
			ArrayList hFragmentedPayload = g_hClientSocketFragmentedPayload.Get(iIndex);
			int iPayloadLength = hFragmentedPayload.Get(0);
			
			if (iPayloadLength == 0) {
				LogError("Received final fragment without initial frames");
				CloseClientConnection(iIndex, 1002, "Invalid fragmentation");
				return true;
			}
			
			iPayloadLength += vFrame.PAYLOAD_LEN;
			hFragmentedPayload.Set(0, iPayloadLength);
			hFragmentedPayload.PushString(sPayLoad);
			
			return false;
		}
		
		case FrameType_Text, FrameType_Binary: {
			return false;
		}
		
		case FrameType_Close: {
			if (g_hClientSocketReadyState.Get(iIndex) == State_Closing) {
				CloseClientSocket(iIndex);
				return true;
			}
			
			// Echo close frame
			SendClientWebsocketFrame(iIndex, sPayLoad, vFrame);
			g_hClientSocketReadyState.Set(iIndex, State_Closing);
			CloseClientSocket(iIndex);
			return true;
		}
		
		case FrameType_Ping: {
			vFrame.OPCODE = FrameType_Pong;
			SendClientWebsocketFrame(iIndex, sPayLoad, vFrame);
			return true;
		}
		
		case FrameType_Pong: {
			return true;
		}
	}
	
	LogError("Unknown opcode: %d", vFrame.OPCODE);
	CloseClientConnection(iIndex, 1002, "Invalid opcode");
	return true;
}

// ===================================================================
// CLIENT FRAME SENDING (WITH MASKING)
// ===================================================================

bool SendClientWebsocketFrame(int iIndex, char[] sPayLoad, WebsocketFrame vFrame) {
	WebsocketReadyState iReadyState = g_hClientSocketReadyState.Get(iIndex);
	if (iReadyState != State_Open) {
		return false;
	}
	
	int length = vFrame.PAYLOAD_LEN;
	Debug(1, "Sending client frame: payload length=%d, opcode=%d", length, vFrame.OPCODE);
	
	// Clear RSV bits
	vFrame.RSV1 = false;
	vFrame.RSV2 = false;
	vFrame.RSV3 = false;
	
	// CLIENT FRAMES MUST BE MASKED (RFC 6455 §5.3)
	vFrame.MASK = true;
	
	// Generate random masking key
	GenerateMaskingKey(vFrame.MASKINGKEY);
	
	char[] sFrame = new char[length + 18]; // Extra space for header + masking key
	if (!PackClientFrame(sPayLoad, sFrame, vFrame)) {
		return false;
	}
	
	// Calculate total frame size
	int frameSize = length + 6; // payload + 2 byte header + 4 byte mask
	if (length > 65535) {
		frameSize += 8;
	} else if (length > 125) {
		frameSize += 2;
	}
	
	if (vFrame.CLOSE_REASON != -1) {
		frameSize += 2;
	}
	
	Debug(1, "Sending masked client frame (size: %d)", frameSize);
	Handle hSocket = g_hClientSockets.Get(iIndex);
	SocketSend(hSocket, sFrame, frameSize);
	
	return true;
}

void GenerateMaskingKey(char[] key) {
	// Generate 4 random bytes for masking key
	int random = GetURandomInt();
	key[0] = random & 0xFF;
	key[1] = (random >> 8) & 0xFF;
	key[2] = (random >> 16) & 0xFF;
	key[3] = (random >> 24) & 0xFF;
	key[4] = '\0';
}

bool PackClientFrame(char[] sPayLoad, char[] sFrame, WebsocketFrame vFrame) {
	int length = vFrame.PAYLOAD_LEN;
	
	// Set first byte (FIN + opcode)
	switch (vFrame.OPCODE) {
		case FrameType_Text: {
			sFrame[0] = 129; // 10000001
		}
		case FrameType_Close: {
			sFrame[0] = 136; // 10001000
			length += 2;
		}
		case FrameType_Ping: {
			sFrame[0] = 137; // 10001001
		}
		case FrameType_Pong: {
			sFrame[0] = 138; // 10001010
		}
		case FrameType_Binary: {
			sFrame[0] = 130; // 10000010
		}
		default: {
			LogError("Invalid opcode for client frame: %d", vFrame.OPCODE);
			return false;
		}
	}
	
	int iOffset;
	
	// Set payload length (with MASK bit set)
	if (length > 65535) {
		sFrame[1] = 255; // 127 + 128 (mask bit)
		char sLengthBin[65], sByte[9];
		FormatEx(sLengthBin, 65, "%064b", length);
		
		for (int i = 0, j = 2; i < 64; i++) {
			if (i && !(i % 8)) {
				sFrame[j] = BinToDec(sByte);
				sByte[0] = '\0';
				j++;
			}
			Format(sByte, 9, "%s%c", sByte, sLengthBin[i]);
		}
		
		iOffset = 10;
	} else if (length > 125) {
		sFrame[1] = 254; // 126 + 128 (mask bit)
		if (length < 256) {
			sFrame[2] = 0;
			sFrame[3] = length;
		} else {
			char sLengthBin[17], sByte[9];
			FormatEx(sLengthBin, 17, "%016b", length);
			
			for (int i = 0, j = 2; i < 16; i++) {
				if (i && !(i % 8)) {
					sFrame[j] = BinToDec(sByte);
					sByte[0] = '\0';
					j++;
				}
				Format(sByte, 9, "%s%c", sByte, sLengthBin[i]);
			}
		}
		iOffset = 4;
	} else {
		sFrame[1] = length | 128; // Set mask bit
		iOffset = 2;
	}
	
	// Add masking key
	for (int i = 0; i < 4; i++) {
		sFrame[iOffset + i] = vFrame.MASKINGKEY[i];
	}
	iOffset += 4;
	
	// Add close reason if present
	if (vFrame.OPCODE == FrameType_Close && vFrame.CLOSE_REASON != -1) {
		char sCloseReasonBin[17], sByte[9];
		FormatEx(sCloseReasonBin, 17, "%016b", vFrame.CLOSE_REASON);
		
		for (int i = 0, j = iOffset; i < 16; i++) {
			if (i && !(i % 8)) {
				sFrame[j] = BinToDec(sByte);
				sByte[0] = '\0';
				j++;
			}
			Format(sByte, 9, "%s%c", sByte, sCloseReasonBin[i]);
		}
		iOffset += 2;
	}
	
	// Add payload (MASKED)
	for (int i = 0; i < vFrame.PAYLOAD_LEN; i++) {
		sFrame[iOffset + i] = sPayLoad[i] ^ vFrame.MASKINGKEY[i % 4];
	}
	
	return true;
}

// ===================================================================
// CLIENT CONNECTION MANAGEMENT
// ===================================================================

void CloseClientConnection(int iIndex, int iCloseReason, char[] sPayLoad) {
	WebsocketFrame vFrame;
	vFrame.OPCODE = FrameType_Close;
	vFrame.CLOSE_REASON = iCloseReason;
	vFrame.PAYLOAD_LEN = strlen(sPayLoad);
	vFrame.FIN = true;
	
	SendClientWebsocketFrame(iIndex, sPayLoad, vFrame);
	g_hClientSocketReadyState.Set(iIndex, State_Closing);
}

void CloseClientSocket(int iIndex) {
	if (iIndex < 0 || iIndex >= g_hClientSockets.Length) {
		return;
	}
	
	Debug(1, "Closing client socket #%d", iIndex);
	
	// Fire disconnect callback
	PrivateForward hDisconnectForward = g_hClientDisconnectForwards.Get(iIndex);
	Call_StartForward(hDisconnectForward);
	Call_PushCell(g_hClientSocketIndexes.Get(iIndex));
	Call_Finish();
	
	// Clean up
	delete hDisconnectForward;
	delete g_hClientConnectForwards.Get(iIndex);
	delete g_hClientReceiveForwards.Get(iIndex);
	delete g_hClientErrorForwards.Get(iIndex);
	delete g_hClientSocketPlugins.Get(iIndex);
	delete g_hClientSocketFragmentedPayload.Get(iIndex);
	
	Handle hSocket = g_hClientSockets.Get(iIndex);
	delete hSocket;
	
	// Remove from arrays
	g_hClientSockets.Erase(iIndex);
	g_hClientSocketIndexes.Erase(iIndex);
	g_hClientSocketPlugins.Erase(iIndex);
	g_hClientSocketHost.Erase(iIndex);
	g_hClientSocketPort.Erase(iIndex);
	g_hClientSocketPath.Erase(iIndex);
	g_hClientSocketReadyState.Erase(iIndex);
	g_hClientSocketFragmentedPayload.Erase(iIndex);
	g_hClientConnectForwards.Erase(iIndex);
	g_hClientReceiveForwards.Erase(iIndex);
	g_hClientDisconnectForwards.Erase(iIndex);
	g_hClientErrorForwards.Erase(iIndex);
	g_hClientIsClient.Erase(iIndex);
}

// ===================================================================
// URL PARSING HELPER
// ===================================================================

bool ParseWebSocketURL(const char[] url, char[] scheme, int schemeLen, char[] host, int hostLen, int &port) {
	// Parse ws://host:port or wss://host:port
	
	// Find scheme
	int colonPos = StrContains(url, "://");
	if (colonPos == -1) {
		return false;
	}
	
	strcopy(scheme, schemeLen, url);
	scheme[colonPos] = '\0';
	
	// Default ports
	if (StrEqual(scheme, "wss", false)) {
		port = 443;
	} else if (StrEqual(scheme, "ws", false)) {
		port = 80;
	} else {
		return false;
	}
	
	// Extract host:port
	int hostStart = colonPos + 3;
	char hostPort[512];
	strcopy(hostPort, sizeof(hostPort), url[hostStart]);
	
	// Remove path if present
	int slashPos = StrContains(hostPort, "/");
	if (slashPos != -1) {
		hostPort[slashPos] = '\0';
	}
	
	// Check for port
	int portPos = StrContains(hostPort, ":");
	if (portPos != -1) {
		strcopy(host, hostLen, hostPort);
		host[portPos] = '\0';
		port = StringToInt(hostPort[portPos + 1]);
	} else {
		strcopy(host, hostLen, hostPort);
	}
	
	return true;
}
