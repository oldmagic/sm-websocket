#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <socket>
#include <websocket>
#include <base64>
#include <sha1>

#define PLUGIN_VERSION "2.0"
#define DEBUG 0

#if DEBUG > 0
char g_sLog[PLATFORM_MAX_PATH];
#endif

/**
 * WebSocket Protocol Implementation (RFC 6455)
 * https://tools.ietf.org/html/rfc6455
 */

// Master socket plugin callbacks structure
enum struct MasterPluginCallbacks {
	Handle pluginHandle;
	Function errorCallback;
	Function incomingCallback;
	Function closeCallback;
}

// Child socket plugin callbacks structure
enum struct ChildPluginCallbacks {
	Handle pluginHandle;
	Function receiveCallback;
	Function disconnectCallback;
	Function errorCallback;
	Function readystateCallback;
}

#define FRAGMENT_MAX_LENGTH 32768
#define URL_MAX_LENGTH 2000

// Handshake header parsing regex
Regex g_hRegExKey;
Regex g_hRegExPath;
Regex g_hRegExProtocol;

// Master socket data structures
ArrayList g_hMasterSockets;
ArrayList g_hMasterSocketHostPort;
ArrayList g_hMasterSocketIndexes;
ArrayList g_hMasterSocketPlugins;
ArrayList g_hMasterErrorForwards;
ArrayList g_hMasterCloseForwards;
ArrayList g_hMasterIncomingForwards;

// Child socket data structures
ArrayList g_hChildsMasterSockets;
ArrayList g_hChildSockets;
ArrayList g_hChildSocketPlugins;
ArrayList g_hChildSocketIndexes;
ArrayList g_hChildSocketHost;
ArrayList g_hChildSocketPort;
ArrayList g_hChildSocketReadyState;
ArrayList g_hChildSocketFragmentedPayload;
ArrayList g_hChildErrorForwards;
ArrayList g_hChildReceiveForwards;
ArrayList g_hChildDisconnectForwards;
ArrayList g_hChildReadyStateChangeForwards;

// Handle counter for pseudo-handles
int g_iLastSocketIndex = 0;

enum WebsocketFrameType {
	FrameType_Continuation = 0,
	FrameType_Text = 1,
	FrameType_Binary = 2,
	FrameType_Close = 8,
	FrameType_Ping = 9,
	FrameType_Pong = 10
}

enum struct WebsocketFrame {
	bool FIN;
	bool RSV1;
	bool RSV2;
	bool RSV3;
	WebsocketFrameType OPCODE;
	bool MASK;
	int PAYLOAD_LEN;
	char MASKINGKEY[5];
	int CLOSE_REASON;
}

public Plugin myinfo = {
	name = "Websocket",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Websocket protocol implementation (RFC 6455)",
	version = PLUGIN_VERSION,
	url = "http://www.wcfan.de/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("websocket");
	CreateNative("Websocket_Open", Native_Websocket_Open);
	CreateNative("Websocket_HookChild", Native_Websocket_HookChild);
	CreateNative("Websocket_HookReadyStateChange", Native_Websocket_HookReadyStateChange);
	CreateNative("Websocket_GetReadyState", Native_Websocket_GetReadyState);
	CreateNative("Websocket_Send", Native_Websocket_Send);
	CreateNative("Websocket_UnhookChild", Native_Websocket_UnhookChild);
	CreateNative("Websocket_Close", Native_Websocket_Close);
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("sm_websocket_version", PLUGIN_VERSION, 
		"WebSocket Extension Version", 
		FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	
	// Initialize regex patterns
	RegexError iRegExError;
	char sError[64];
	
	g_hRegExKey = new Regex("Sec-WebSocket-Key: (.*)\r\n", 0, sError, sizeof(sError), iRegExError);
	if (g_hRegExKey == null) {
		SetFailState("Failed to compile Sec-WebSocket-Key regex: %s (%d)", sError, iRegExError);
	}
	
	g_hRegExPath = new Regex("GET (.*)( HTTP/1.\\d)\r\n", 0, sError, sizeof(sError), iRegExError);
	if (g_hRegExPath == null) {
		SetFailState("Failed to compile GET-Path regex: %s (%d)", sError, iRegExError);
	}
	
	g_hRegExProtocol = new Regex("Sec-WebSocket-Protocol: (.*)\r\n", 0, sError, sizeof(sError), iRegExError);
	if (g_hRegExProtocol == null) {
		SetFailState("Failed to compile Sec-WebSocket-Protocol regex: %s (%d)", sError, iRegExError);
	}
	
	// Initialize master socket arrays
	g_hMasterSockets = new ArrayList();
	g_hMasterSocketHostPort = new ArrayList(ByteCountToCells(128));
	g_hMasterSocketIndexes = new ArrayList();
	g_hMasterSocketPlugins = new ArrayList();
	g_hMasterErrorForwards = new ArrayList();
	g_hMasterCloseForwards = new ArrayList();
	g_hMasterIncomingForwards = new ArrayList();
	
	// Initialize child socket arrays
	g_hChildsMasterSockets = new ArrayList();
	g_hChildSockets = new ArrayList();
	g_hChildSocketIndexes = new ArrayList();
	g_hChildSocketPlugins = new ArrayList();
	g_hChildSocketHost = new ArrayList(ByteCountToCells(64));
	g_hChildSocketPort = new ArrayList();
	g_hChildSocketReadyState = new ArrayList();
	g_hChildSocketFragmentedPayload = new ArrayList();
	g_hChildErrorForwards = new ArrayList();
	g_hChildReceiveForwards = new ArrayList();
	g_hChildDisconnectForwards = new ArrayList();
	g_hChildReadyStateChangeForwards = new ArrayList();
	
#if DEBUG > 0
	BuildPath(Path_SM, g_sLog, sizeof(g_sLog), "logs/websocket_debug.log");
#endif
}

public void OnPluginEnd() {
	// Clean up all connections
	while (g_hMasterSockets.Length > 0) {
		CloseMasterSocket(0);
	}
	
	// Clean up regex handles
	delete g_hRegExKey;
	delete g_hRegExPath;
	delete g_hRegExProtocol;
	
	// Clean up arrays
	delete g_hMasterSockets;
	delete g_hMasterSocketHostPort;
	delete g_hMasterSocketIndexes;
	delete g_hMasterSocketPlugins;
	delete g_hMasterErrorForwards;
	delete g_hMasterCloseForwards;
	delete g_hMasterIncomingForwards;
	delete g_hChildsMasterSockets;
	delete g_hChildSockets;
	delete g_hChildSocketIndexes;
	delete g_hChildSocketPlugins;
	delete g_hChildSocketHost;
	delete g_hChildSocketPort;
	delete g_hChildSocketReadyState;
	delete g_hChildSocketFragmentedPayload;
	delete g_hChildErrorForwards;
	delete g_hChildReceiveForwards;
	delete g_hChildDisconnectForwards;
	delete g_hChildReadyStateChangeForwards;
}

public int Native_Websocket_Open(Handle plugin, int numParams) {
	// Check if plugin already has a socket open (limit: one per plugin)
	int iSize = g_hMasterSocketPlugins.Length;
	for (int i = 0; i < iSize; i++) {
		ArrayList hMasterSocketPlugins = g_hMasterSocketPlugins.Get(i);
		int iPluginCount = hMasterSocketPlugins.Length;
		
		for (int p = 0; p < iPluginCount; p++) {
			MasterPluginCallbacks aPluginInfo;
			hMasterSocketPlugins.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
			
			if (aPluginInfo.pluginHandle == plugin) {
				ThrowNativeError(SP_ERROR_NATIVE, "Only one websocket per plugin allowed.");
				return view_as<int>(INVALID_WEBSOCKET_HANDLE);
			}
		}
	}
	
	int iHostNameLength;
	GetNativeStringLength(1, iHostNameLength);
	if (iHostNameLength <= 0) {
		return view_as<int>(INVALID_WEBSOCKET_HANDLE);
	}
	
	char[] sHostName = new char[iHostNameLength + 1];
	GetNativeString(1, sHostName, iHostNameLength + 1);
	
	int iPort = GetNativeCell(2);
	int iIndex = -1;
	
	// Check if socket already exists on this host:port
	char sHostPort[128];
	FormatEx(sHostPort, sizeof(sHostPort), "%s:%d", sHostName, iPort);
	
	iSize = g_hMasterSocketHostPort.Length;
	for (int i = 0; i < iSize; i++) {
		char sHostPortStored[128];
		g_hMasterSocketHostPort.GetString(i, sHostPortStored, sizeof(sHostPortStored));
		
		if (StrEqual(sHostPort, sHostPortStored, false)) {
			iIndex = i;
			break;
		}
	}
	
	PrivateForward hErrorForward, hCloseForward, hIncomingForward;
	int iPseudoHandle;
	
	// Create new socket if it doesn't exist
	if (iIndex == -1) {
		Handle hMasterSocket = SocketCreate(SOCKET_TCP, OnSocketError);
		if (hMasterSocket == null) {
			ThrowNativeError(SP_ERROR_NATIVE, "Failed to create socket");
			return view_as<int>(INVALID_WEBSOCKET_HANDLE);
		}
		
		if (!SocketSetOption(hMasterSocket, SocketReuseAddr, 1)) {
			delete hMasterSocket;
			ThrowNativeError(SP_ERROR_NATIVE, "Failed to set SO_REUSEADDR option");
			return view_as<int>(INVALID_WEBSOCKET_HANDLE);
		}
		
		if (!SocketBind(hMasterSocket, sHostName, iPort)) {
			delete hMasterSocket;
			ThrowNativeError(SP_ERROR_NATIVE, "Failed to bind socket to %s:%d", sHostName, iPort);
			return view_as<int>(INVALID_WEBSOCKET_HANDLE);
		}
		
		if (!SocketListen(hMasterSocket, OnSocketIncoming)) {
			delete hMasterSocket;
			ThrowNativeError(SP_ERROR_NATIVE, "Failed to listen on %s:%d", sHostName, iPort);
			return view_as<int>(INVALID_WEBSOCKET_HANDLE);
		}
		
		iIndex = g_hMasterSockets.Push(hMasterSocket);
		iPseudoHandle = ++g_iLastSocketIndex;
		g_hMasterSocketIndexes.Push(iPseudoHandle);
		
		// Create private forwards
		hIncomingForward = new PrivateForward(ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_String, Param_String);
		g_hMasterIncomingForwards.Push(hIncomingForward);
		
		hErrorForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		g_hMasterErrorForwards.Push(hErrorForward);
		
		hCloseForward = new PrivateForward(ET_Ignore, Param_Cell);
		g_hMasterCloseForwards.Push(hCloseForward);
		
		SocketSetArg(hMasterSocket, iPseudoHandle);
		g_hMasterSocketHostPort.PushString(sHostPort);
		
		Debug(1, "Created socket on %s:%d #%d", sHostName, iPort, iIndex);
	} else {
		// Reuse existing socket
		iPseudoHandle = g_hMasterSocketIndexes.Get(iIndex);
		hIncomingForward = g_hMasterIncomingForwards.Get(iIndex);
		hErrorForward = g_hMasterErrorForwards.Get(iIndex);
		hCloseForward = g_hMasterCloseForwards.Get(iIndex);
		
		Debug(1, "Reusing socket on %s:%d #%d", sHostName, iPort, iIndex);
	}
	
	// Add callbacks to forwards
	Function fIncomingCallback = GetNativeFunction(3);
	if (!hIncomingForward.AddFunction(plugin, fIncomingCallback)) {
		LogError("Failed to add incoming callback");
	}
	
	Function fErrorCallback = GetNativeFunction(4);
	if (!hErrorForward.AddFunction(plugin, fErrorCallback)) {
		LogError("Failed to add error callback");
	}
	
	Function fCloseCallback = GetNativeFunction(5);
	if (!hCloseForward.AddFunction(plugin, fCloseCallback)) {
		LogError("Failed to add close callback");
	}
	
	// Store plugin info
	ArrayList hMasterSocketPlugins;
	if (iIndex >= iSize) {
		hMasterSocketPlugins = new ArrayList(sizeof(MasterPluginCallbacks));
		g_hMasterSocketPlugins.Push(hMasterSocketPlugins);
	} else {
		hMasterSocketPlugins = g_hMasterSocketPlugins.Get(iIndex);
	}
	
	MasterPluginCallbacks aPluginInfo;
	aPluginInfo.pluginHandle = plugin;
	aPluginInfo.errorCallback = fErrorCallback;
	aPluginInfo.incomingCallback = fIncomingCallback;
	aPluginInfo.closeCallback = fCloseCallback;
	hMasterSocketPlugins.PushArray(aPluginInfo, sizeof(aPluginInfo));
	
	return iPseudoHandle;
}

public int Native_Websocket_Send(Handle plugin, int numParams) {
	WebsocketHandle iPseudoChildHandle = GetNativeCell(1);
	int iChildIndex = g_hChildSocketIndexes.FindValue(view_as<int>(iPseudoChildHandle));
	
	if (iPseudoChildHandle == INVALID_WEBSOCKET_HANDLE || iChildIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid child websocket handle");
		return false;
	}
	
	WebsocketFrame vFrame;
	WebsocketSendType sendType = GetNativeCell(2);
	vFrame.OPCODE = (sendType == SendType_Text) ? FrameType_Text : FrameType_Binary;
	vFrame.FIN = true;
	vFrame.CLOSE_REASON = -1;
	
	vFrame.PAYLOAD_LEN = GetNativeCell(4);
	if (vFrame.PAYLOAD_LEN == -1) {
		GetNativeStringLength(3, vFrame.PAYLOAD_LEN);
	}
	
	char[] sPayLoad = new char[vFrame.PAYLOAD_LEN + 1];
	GetNativeString(3, sPayLoad, vFrame.PAYLOAD_LEN + 1);
	
	return SendWebsocketFrame(iChildIndex, sPayLoad, vFrame);
}

public int Native_Websocket_HookChild(Handle plugin, int numParams) {
	WebsocketHandle iPseudoChildHandle = GetNativeCell(1);
	int iChildIndex = g_hChildSocketIndexes.FindValue(view_as<int>(iPseudoChildHandle));
	
	if (iPseudoChildHandle == INVALID_WEBSOCKET_HANDLE || iChildIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid child websocket handle");
		return false;
	}
	
	PrivateForward hReceiveForward = g_hChildReceiveForwards.Get(iChildIndex);
	PrivateForward hErrorForward = g_hChildErrorForwards.Get(iChildIndex);
	PrivateForward hDisconnectForward = g_hChildDisconnectForwards.Get(iChildIndex);
	
	ArrayList hChildSocketPlugin = g_hChildSocketPlugins.Get(iChildIndex);
	int iPluginCount = hChildSocketPlugin.Length;
	int iPluginInfoIndex = -1;
	
	// Check if plugin already hooked this socket
	for (int p = 0; p < iPluginCount; p++) {
		ChildPluginCallbacks aPluginInfo;
		hChildSocketPlugin.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
		
		if (plugin == aPluginInfo.pluginHandle) {
			iPluginInfoIndex = p;
			
			// Remove existing callbacks
			if (aPluginInfo.receiveCallback != INVALID_FUNCTION) {
				hReceiveForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.receiveCallback);
				hDisconnectForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.disconnectCallback);
				hErrorForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.errorCallback);
			}
			break;
		}
	}
	
	ChildPluginCallbacks aPluginInfo;
	if (iPluginInfoIndex != -1) {
		hChildSocketPlugin.GetArray(iPluginInfoIndex, aPluginInfo, sizeof(aPluginInfo));
	} else {
		aPluginInfo.pluginHandle = plugin;
		aPluginInfo.readystateCallback = INVALID_FUNCTION;
	}
	
	aPluginInfo.receiveCallback = GetNativeFunction(2);
	aPluginInfo.disconnectCallback = GetNativeFunction(3);
	aPluginInfo.errorCallback = GetNativeFunction(4);
	
	if (iPluginInfoIndex == -1) {
		hChildSocketPlugin.PushArray(aPluginInfo, sizeof(aPluginInfo));
	} else {
		hChildSocketPlugin.SetArray(iPluginInfoIndex, aPluginInfo, sizeof(aPluginInfo));
	}
	
	// Add callbacks to forwards
	hReceiveForward.AddFunction(aPluginInfo.pluginHandle, aPluginInfo.receiveCallback);
	hDisconnectForward.AddFunction(aPluginInfo.pluginHandle, aPluginInfo.disconnectCallback);
	hErrorForward.AddFunction(aPluginInfo.pluginHandle, aPluginInfo.errorCallback);
	
	return true;
}

public int Native_Websocket_HookReadyStateChange(Handle plugin, int numParams) {
	WebsocketHandle iPseudoChildHandle = GetNativeCell(1);
	int iChildIndex = g_hChildSocketIndexes.FindValue(view_as<int>(iPseudoChildHandle));
	
	if (iPseudoChildHandle == INVALID_WEBSOCKET_HANDLE || iChildIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid child websocket handle");
		return false;
	}
	
	PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iChildIndex);
	ArrayList hChildSocketPlugin = g_hChildSocketPlugins.Get(iChildIndex);
	int iPluginCount = hChildSocketPlugin.Length;
	int iPluginInfoIndex = -1;
	
	// Check if plugin already registered
	for (int p = 0; p < iPluginCount; p++) {
		ChildPluginCallbacks aPluginInfo;
		hChildSocketPlugin.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
		
		if (plugin == aPluginInfo.pluginHandle) {
			iPluginInfoIndex = p;
			
			// Remove existing callback
			if (aPluginInfo.readystateCallback != INVALID_FUNCTION) {
				hReadyStateChangeForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.readystateCallback);
			}
			break;
		}
	}
	
	ChildPluginCallbacks aPluginInfo;
	if (iPluginInfoIndex != -1) {
		hChildSocketPlugin.GetArray(iPluginInfoIndex, aPluginInfo, sizeof(aPluginInfo));
	} else {
		aPluginInfo.pluginHandle = plugin;
		aPluginInfo.receiveCallback = INVALID_FUNCTION;
		aPluginInfo.errorCallback = INVALID_FUNCTION;
		aPluginInfo.disconnectCallback = INVALID_FUNCTION;
	}
	
	aPluginInfo.readystateCallback = GetNativeFunction(2);
	
	if (iPluginInfoIndex == -1) {
		hChildSocketPlugin.PushArray(aPluginInfo, sizeof(aPluginInfo));
	} else {
		hChildSocketPlugin.SetArray(iPluginInfoIndex, aPluginInfo, sizeof(aPluginInfo));
	}
	
	hReadyStateChangeForward.AddFunction(aPluginInfo.pluginHandle, aPluginInfo.readystateCallback);
	
	return true;
}

public int Native_Websocket_GetReadyState(Handle plugin, int numParams) {
	WebsocketHandle iPseudoChildHandle = GetNativeCell(1);
	int iChildIndex = g_hChildSocketIndexes.FindValue(view_as<int>(iPseudoChildHandle));
	
	if (iPseudoChildHandle == INVALID_WEBSOCKET_HANDLE || iChildIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid child websocket handle");
		return 0;
	}
	
	return g_hChildSocketReadyState.Get(iChildIndex);
}

public int Native_Websocket_UnhookChild(Handle plugin, int numParams) {
	WebsocketHandle iPseudoChildHandle = GetNativeCell(1);
	int iChildIndex = g_hChildSocketIndexes.FindValue(view_as<int>(iPseudoChildHandle));
	
	if (iPseudoChildHandle == INVALID_WEBSOCKET_HANDLE || iChildIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid child websocket handle");
		return 0;
	}
	
	PrivateForward hReceiveForward = g_hChildReceiveForwards.Get(iChildIndex);
	PrivateForward hDisconnectForward = g_hChildDisconnectForwards.Get(iChildIndex);
	PrivateForward hErrorForward = g_hChildErrorForwards.Get(iChildIndex);
	PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iChildIndex);
	
	ArrayList hChildSocketPlugin = g_hChildSocketPlugins.Get(iChildIndex);
	int iPluginCount = hChildSocketPlugin.Length;
	
	for (int p = 0; p < iPluginCount; p++) {
		ChildPluginCallbacks aPluginInfo;
		hChildSocketPlugin.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
		
		if (aPluginInfo.pluginHandle == plugin) {
			// Remove callbacks from forwards
			if (aPluginInfo.receiveCallback != INVALID_FUNCTION) {
				hReceiveForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.receiveCallback);
				hDisconnectForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.disconnectCallback);
				hErrorForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.errorCallback);
			}
			
			if (aPluginInfo.readystateCallback != INVALID_FUNCTION) {
				hReadyStateChangeForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.readystateCallback);
			}
			
			hChildSocketPlugin.Erase(p);
			break;
		}
	}
	
	// Close connection if no plugins are using it
	if (hChildSocketPlugin.Length == 0) {
		CloseConnection(iChildIndex, 1000, "");
	}
	
	return 0;
}

public int Native_Websocket_Close(Handle plugin, int numParams) {
	WebsocketHandle iPseudoHandle = GetNativeCell(1);
	int iIndex = g_hMasterSocketIndexes.FindValue(view_as<int>(iPseudoHandle));
	
	if (iPseudoHandle == INVALID_WEBSOCKET_HANDLE || iIndex == -1) {
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid websocket handle");
		return 0;
	}
	
	CloseMasterSocket(iIndex);
	return 0;
}

public void OnSocketError(Handle socket, int errorType, int errorNum, any arg) {
	int iIndex = g_hMasterSocketIndexes.FindValue(arg);
	
	if (iIndex != -1) {
		CloseMasterSocket(iIndex, true, errorType, errorNum);
	} else {
		delete socket;
	}
}

void CloseMasterSocket(int iIndex, bool bError = false, int errorType = -1, int errorNum = -1) {
	if (iIndex < 0 || iIndex >= g_hMasterSockets.Length) {
		return;
	}
	
	int iPseudoHandle = g_hMasterSocketIndexes.Get(iIndex);
	PrivateForward hErrorForward = g_hMasterErrorForwards.Get(iIndex);
	PrivateForward hIncomingForward = g_hMasterIncomingForwards.Get(iIndex);
	PrivateForward hCloseForward = g_hMasterCloseForwards.Get(iIndex);
	
	// Close all child sockets (iterate backwards to avoid index issues)
	for (int i = g_hChildsMasterSockets.Length - 1; i >= 0; i--) {
		if (g_hChildsMasterSockets.Get(i) == iIndex) {
			CloseConnection(i, 1001, "");
		}
	}
	
	// Notify plugins
	if (hIncomingForward.FunctionCount > 0) {
		if (bError) {
			Call_StartForward(hErrorForward);
			Call_PushCell(iPseudoHandle);
			Call_PushCell(errorType);
			Call_PushCell(errorNum);
			Call_PushCell(0);
			Call_Finish();
		} else {
			Call_StartForward(hCloseForward);
			Call_PushCell(iPseudoHandle);
			Call_Finish();
		}
		
		// Remove all callbacks
		ArrayList hPlugins = g_hMasterSocketPlugins.Get(iIndex);
		int iPluginCount = hPlugins.Length;
		
		for (int p = 0; p < iPluginCount; p++) {
			MasterPluginCallbacks aPluginInfo;
			hPlugins.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
			
			if (!IsPluginStillLoaded(aPluginInfo.pluginHandle)) {
				continue;
			}
			
			hErrorForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.errorCallback);
			hIncomingForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.incomingCallback);
			hCloseForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.closeCallback);
		}
		
		delete hPlugins;
	}
	
	// Clean up
	delete hErrorForward;
	delete hIncomingForward;
	delete hCloseForward;
	
	Handle hMasterSocket = g_hMasterSockets.Get(iIndex);
	delete hMasterSocket;
	
	g_hMasterSocketPlugins.Erase(iIndex);
	g_hMasterErrorForwards.Erase(iIndex);
	g_hMasterIncomingForwards.Erase(iIndex);
	g_hMasterCloseForwards.Erase(iIndex);
	g_hMasterSocketHostPort.Erase(iIndex);
	g_hMasterSockets.Erase(iIndex);
	g_hMasterSocketIndexes.Erase(iIndex);
}

public void OnSocketIncoming(Handle socket, Handle newSocket, const char[] remoteIP, int remotePort, any arg) {
	int iIndex = g_hMasterSocketIndexes.FindValue(arg);
	
	if (iIndex == -1) {
		delete newSocket;
		return;
	}
	
	// Setup child socket callbacks
	SocketSetReceiveCallback(newSocket, OnChildSocketReceive);
	SocketSetDisconnectCallback(newSocket, OnChildSocketDisconnect);
	SocketSetErrorCallback(newSocket, OnChildSocketError);
	
	int iPseudoChildHandle = ++g_iLastSocketIndex;
	PrivateForward hIncomingForward = g_hMasterIncomingForwards.Get(iIndex);
	
	// Check if any plugins are still listening
	if (hIncomingForward.FunctionCount == 0) {
		delete newSocket;
		CloseMasterSocket(iIndex);
		return;
	}
	
	SocketSetArg(newSocket, iPseudoChildHandle);
	
	// Store child socket data
	g_hChildSockets.Push(newSocket);
	g_hChildsMasterSockets.Push(iIndex);
	g_hChildSocketIndexes.Push(iPseudoChildHandle);
	g_hChildSocketHost.PushString(remoteIP);
	g_hChildSocketPort.Push(remotePort);
	g_hChildSocketPlugins.Push(new ArrayList(sizeof(ChildPluginCallbacks)));
	g_hChildSocketReadyState.Push(State_Connecting);
	
	// Initialize fragmented payload buffer
	ArrayList hFragmentedPayload = new ArrayList(ByteCountToCells(FRAGMENT_MAX_LENGTH));
	g_hChildSocketFragmentedPayload.Push(hFragmentedPayload);
	hFragmentedPayload.Push(0); // Payload length
	hFragmentedPayload.Push(0); // Payload type
	
	// Create private forwards for this child
	g_hChildReceiveForwards.Push(new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Any));
	g_hChildErrorForwards.Push(new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Any));
	g_hChildDisconnectForwards.Push(new PrivateForward(ET_Ignore, Param_Cell, Param_Any));
	g_hChildReadyStateChangeForwards.Push(new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Any));
}

public void OnChildSocketError(Handle socket, int errorType, int errorNum, any arg) {
	int iIndex = g_hChildSocketIndexes.FindValue(arg);
	
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	PrivateForward hErrorForward = g_hChildErrorForwards.Get(iIndex);
	
	Call_StartForward(hErrorForward);
	Call_PushCell(g_hChildSocketIndexes.Get(iIndex));
	Call_PushCell(errorType);
	Call_PushCell(errorNum);
	Call_Finish();
	
	CloseChildSocket(iIndex, false);
}

public void OnChildSocketDisconnect(Handle socket, any arg) {
	Debug(1, "Child socket disconnected");
	
	int iIndex = g_hChildSocketIndexes.FindValue(arg);
	
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	CloseChildSocket(iIndex);
}

public void OnChildSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg) {
	Debug(2, "Child socket receives data: %s", receiveData);
	
	int iIndex = g_hChildSocketIndexes.FindValue(arg);
	
	if (iIndex == -1) {
		delete socket;
		return;
	}
	
	WebsocketReadyState iReadyState = g_hChildSocketReadyState.Get(iIndex);
	
	if (iReadyState == State_Connecting) {
		HandleWebSocketHandshake(iIndex, receiveData, socket);
	} else if (iReadyState == State_Open) {
		HandleWebSocketFrame(iIndex, receiveData, dataSize, arg);
	}
}

void HandleWebSocketHandshake(int iIndex, const char[] receiveData, Handle socket) {
	RegexError iRegexError;
	
	// Extract security key
	int iSubStrings = g_hRegExKey.Match(receiveData, iRegexError);
	if (iSubStrings <= 0) {
		LogError("Failed to find Sec-WebSocket-Key in handshake");
		CloseChildSocket(iIndex);
		return;
	}
	
	char sKey[256];
	if (!g_hRegExKey.GetSubString(1, sKey, sizeof(sKey))) {
		LogError("Failed to extract security key");
		CloseChildSocket(iIndex);
		return;
	}
	
	Debug(2, "Key: %s", sKey);
	
	// Generate accept key
	char sAcceptKey[512];
	Format(sAcceptKey, sizeof(sAcceptKey), "%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11", sKey);
	
	// SHA1 hash the accept key
	int iHashedKey[20];
	SHA1(sAcceptKey, iHashedKey, sizeof(iHashedKey));
	
	// Base64 encode the hash
	char sResponseKey[64];
	EncodeBase64(sResponseKey, sizeof(sResponseKey), iHashedKey, 20);
	
	Debug(2, "ResponseKey: %s", sResponseKey);
	
	// Extract protocol
	char sProtocol[256];
	iSubStrings = g_hRegExProtocol.Match(receiveData, iRegexError);
	if (iSubStrings > 0) {
		g_hRegExProtocol.GetSubString(1, sProtocol, sizeof(sProtocol));
	}
	
	// Extract path
	char sPath[URL_MAX_LENGTH];
	iSubStrings = g_hRegExPath.Match(receiveData, iRegexError);
	if (iSubStrings > 0) {
		g_hRegExPath.GetSubString(1, sPath, sizeof(sPath));
	}
	
	// Notify plugins of incoming connection
	int iMasterIndex = g_hChildsMasterSockets.Get(iIndex);
	PrivateForward hIncomingForward = g_hMasterIncomingForwards.Get(iMasterIndex);
	
	Call_StartForward(hIncomingForward);
	Call_PushCell(g_hMasterSocketIndexes.Get(iMasterIndex));
	Call_PushCell(g_hChildSocketIndexes.Get(iIndex));
	
	char remoteIP[65];
	g_hChildSocketHost.GetString(iIndex, remoteIP, sizeof(remoteIP));
	Call_PushString(remoteIP);
	Call_PushCell(g_hChildSocketPort.Get(iIndex));
	
	char sProtocolReturn[256];
	strcopy(sProtocolReturn, sizeof(sProtocolReturn), sProtocol);
	Call_PushStringEx(sProtocolReturn, sizeof(sProtocolReturn), SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
	Call_PushString(sPath);
	
	Action iResult;
	Call_Finish(iResult);
	
	// Connection refused
	if (iResult >= Plugin_Handled) {
		Debug(1, "IncomingForward blocked connection");
		CloseChildSocket(iIndex);
		return;
	}
	
	// Check if any plugin hooked the child
	ArrayList hChildSocketPlugins = g_hChildSocketPlugins.Get(iIndex);
	if (hChildSocketPlugins.Length == 0) {
		Debug(1, "No plugin hooked child socket");
		CloseChildSocket(iIndex);
		return;
	}
	
	// Validate protocol
	if (strlen(sProtocol) > 0 && StrContains(sProtocol, sProtocolReturn) == -1) {
		Debug(1, "Invalid protocol chosen: %s (available: %s)", sProtocolReturn, sProtocol);
		sProtocolReturn[0] = '\0';
	} else if (strlen(sProtocol) > 0) {
		Format(sProtocolReturn, sizeof(sProtocolReturn), "\r\nSec-Websocket-Protocol: %s", sProtocol);
	}
	
	// Send handshake response
	char sHTTPRequest[512];
	FormatEx(sHTTPRequest, sizeof(sHTTPRequest), "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s%s\r\n\r\n", sResponseKey, sProtocolReturn);
	
	SocketSend(socket, sHTTPRequest);
	
	Debug(2, "Handshake response: %s", sHTTPRequest);
	
	// Update state to open
	g_hChildSocketReadyState.Set(iIndex, State_Open);
	
	// Notify ready state change
	PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iIndex);
	Call_StartForward(hReadyStateChangeForward);
	Call_PushCell(g_hChildSocketIndexes.Get(iIndex));
	Call_PushCell(State_Open);
	Call_Finish();
}

void HandleWebSocketFrame(int iIndex, const char[] receiveData, int dataSize, any arg) {
	WebsocketFrame vFrame;
	char[] sPayLoad = new char[dataSize];
	
	ParseFrame(vFrame, receiveData, dataSize, sPayLoad);
	
	if (!PreprocessFrame(iIndex, vFrame, sPayLoad)) {
		// Call receive forward
		PrivateForward hReceiveForward = g_hChildReceiveForwards.Get(iIndex);
		Call_StartForward(hReceiveForward);
		Call_PushCell(arg);
		
		// Handle fragmented messages
		if (vFrame.OPCODE == FrameType_Continuation) {
			ArrayList hFragmentedPayload = g_hChildSocketFragmentedPayload.Get(iIndex);
			int iPayloadLength = hFragmentedPayload.Get(0);
			
			char[] sConcatPayload = new char[iPayloadLength + 1];
			char sPayloadPart[FRAGMENT_MAX_LENGTH];
			int iSize = hFragmentedPayload.Length;
			
			// Concatenate all fragments
			for (int i = 2; i < iSize; i++) {
				hFragmentedPayload.GetString(i, sPayloadPart, sizeof(sPayloadPart));
				StrCat(sConcatPayload, iPayloadLength + 1, sPayloadPart);
			}
			
			WebsocketSendType iType = (hFragmentedPayload.Get(1) == view_as<int>(FrameType_Text)) ? SendType_Text : SendType_Binary;
			Call_PushCell(iType);
			Call_PushString(sConcatPayload);
			Call_PushCell(iPayloadLength);
			
			// Clear fragment buffer
			hFragmentedPayload.Clear();
			hFragmentedPayload.Push(0);
			hFragmentedPayload.Push(0);
		} else {
			// Unfragmented message
			WebsocketSendType iType = (vFrame.OPCODE == FrameType_Text) ? SendType_Text : SendType_Binary;
			Call_PushCell(iType);
			Call_PushString(sPayLoad);
			Call_PushCell(vFrame.PAYLOAD_LEN);
		}
		
		Call_Finish();
	}
}

void CloseChildSocket(int iChildIndex, bool bFireForward = true) {
	if (iChildIndex < 0 || iChildIndex >= g_hChildSockets.Length) {
		return;
	}
	
	Debug(1, "Closing child socket #%d", iChildIndex);
	
	if (bFireForward) {
		PrivateForward hDisconnectForward = g_hChildDisconnectForwards.Get(iChildIndex);
		Call_StartForward(hDisconnectForward);
		Call_PushCell(g_hChildSocketIndexes.Get(iChildIndex));
		Call_Finish();
	}
	
	// Remove callbacks from forwards
	PrivateForward hReceiveForward = g_hChildReceiveForwards.Get(iChildIndex);
	PrivateForward hDisconnectForward = g_hChildDisconnectForwards.Get(iChildIndex);
	PrivateForward hErrorForward = g_hChildErrorForwards.Get(iChildIndex);
	PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iChildIndex);
	
	ArrayList hChildSocketPlugin = g_hChildSocketPlugins.Get(iChildIndex);
	int iPluginCount = hChildSocketPlugin.Length;
	
	for (int p = 0; p < iPluginCount; p++) {
		ChildPluginCallbacks aPluginInfo;
		hChildSocketPlugin.GetArray(p, aPluginInfo, sizeof(aPluginInfo));
		
		if (!IsPluginStillLoaded(aPluginInfo.pluginHandle)) {
			continue;
		}
		
		if (aPluginInfo.receiveCallback != INVALID_FUNCTION) {
			hReceiveForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.receiveCallback);
			hDisconnectForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.disconnectCallback);
			hErrorForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.errorCallback);
		}
		
		if (aPluginInfo.readystateCallback != INVALID_FUNCTION) {
			hReadyStateChangeForward.RemoveFunction(aPluginInfo.pluginHandle, aPluginInfo.readystateCallback);
		}
	}
	
	// Clean up handles
	delete hChildSocketPlugin;
	delete hReceiveForward;
	delete hDisconnectForward;
	delete hErrorForward;
	delete hReadyStateChangeForward;
	
	// Delete fragmented payload buffer
	ArrayList hFragmentedPayload = g_hChildSocketFragmentedPayload.Get(iChildIndex);
	delete hFragmentedPayload;
	
	Handle hChildSocket = g_hChildSockets.Get(iChildIndex);
	delete hChildSocket;
	
	// Remove from arrays
	g_hChildSockets.Erase(iChildIndex);
	g_hChildsMasterSockets.Erase(iChildIndex);
	g_hChildSocketHost.Erase(iChildIndex);
	g_hChildSocketPort.Erase(iChildIndex);
	g_hChildSocketReadyState.Erase(iChildIndex);
	g_hChildSocketPlugins.Erase(iChildIndex);
	g_hChildSocketIndexes.Erase(iChildIndex);
	g_hChildSocketFragmentedPayload.Erase(iChildIndex);
	g_hChildReceiveForwards.Erase(iChildIndex);
	g_hChildErrorForwards.Erase(iChildIndex);
	g_hChildDisconnectForwards.Erase(iChildIndex);
	g_hChildReadyStateChangeForwards.Erase(iChildIndex);
}

void ParseFrame(WebsocketFrame vFrame, const char[] receiveDataLong, int dataSize, char[] sPayLoad) {
	int[] receiveData = new int[dataSize];
	for (int i = 0; i < dataSize; i++) {
		receiveData[i] = receiveDataLong[i] & 0xff;
		Debug(3, "%d (%c): %08b", i, (receiveData[i] < 32 ? ' ' : receiveData[i]), receiveData[i]);
	}
	
	char sByte[9];
	FormatEx(sByte, sizeof(sByte), "%08b", receiveData[0]);
	Debug(3, "First byte: %s", sByte);
	
	vFrame.FIN = (sByte[0] == '1');
	vFrame.RSV1 = (sByte[1] == '1');
	vFrame.RSV2 = (sByte[2] == '1');
	vFrame.RSV3 = (sByte[3] == '1');
	vFrame.OPCODE = view_as<WebsocketFrameType>(BinToDec(sByte[4]));
	
	FormatEx(sByte, sizeof(sByte), "%08b", receiveData[1]);
	Debug(3, "Second byte: %s", sByte);
	
	vFrame.MASK = (sByte[0] == '1');
	vFrame.PAYLOAD_LEN = BinToDec(sByte[1]);
	
	int iOffset = 2;
	vFrame.MASKINGKEY[0] = '\0';
	
	// Handle extended payload length
	if (vFrame.PAYLOAD_LEN > 126) {
		char sLongLength[49];
		for (int i = 2; i < 10; i++) {
			Format(sLongLength, sizeof(sLongLength), "%s%08b", sLongLength, receiveData[i]);
		}
		vFrame.PAYLOAD_LEN = BinToDec(sLongLength);
		iOffset += 8;
	} else if (vFrame.PAYLOAD_LEN > 125) {
		char sLongLength[17];
		for (int i = 2; i < 4; i++) {
			Format(sLongLength, sizeof(sLongLength), "%s%08b", sLongLength, receiveData[i]);
		}
		vFrame.PAYLOAD_LEN = BinToDec(sLongLength);
		iOffset += 2;
	}
	
	// Extract masking key
	if (vFrame.MASK) {
		for (int i = iOffset, j = 0; j < 4; i++, j++) {
			vFrame.MASKINGKEY[j] = receiveData[i];
		}
		vFrame.MASKINGKEY[4] = '\0';
		iOffset += 4;
	}
	
	// Extract and unmask payload
	int[] iPayLoad = new int[vFrame.PAYLOAD_LEN];
	for (int i = iOffset, j = 0; j < vFrame.PAYLOAD_LEN; i++, j++) {
		iPayLoad[j] = receiveData[i];
	}
	
	Debug(2, "dataSize: %d, PAYLOAD_LEN: %d, OPCODE: %d", dataSize, vFrame.PAYLOAD_LEN, vFrame.OPCODE);
	
	// Unmask payload
	if (vFrame.MASK) {
		for (int i = 0; i < vFrame.PAYLOAD_LEN; i++) {
			sPayLoad[i] = iPayLoad[i] ^ vFrame.MASKINGKEY[i % 4];
		}
		sPayLoad[vFrame.PAYLOAD_LEN] = '\0';
	} else {
		for (int i = 0; i < vFrame.PAYLOAD_LEN; i++) {
			sPayLoad[i] = iPayLoad[i];
		}
		sPayLoad[vFrame.PAYLOAD_LEN] = '\0';
	}
	
	// Handle close frame
	if (vFrame.OPCODE == FrameType_Close && vFrame.PAYLOAD_LEN >= 2) {
		char sCloseReason[17];
		FormatEx(sCloseReason, sizeof(sCloseReason), "%08b%08b", sPayLoad[0] & 0xff, sPayLoad[1] & 0xff);
		vFrame.CLOSE_REASON = BinToDec(sCloseReason);
		
		// Shift payload to remove close reason
		for (int i = 0; i < vFrame.PAYLOAD_LEN - 2; i++) {
			sPayLoad[i] = sPayLoad[i + 2];
		}
		sPayLoad[vFrame.PAYLOAD_LEN - 2] = '\0';
		vFrame.PAYLOAD_LEN -= 2;
		
		Debug(2, "CLOSE_REASON: %d", vFrame.CLOSE_REASON);
	} else {
		vFrame.CLOSE_REASON = -1;
	}
	
	Debug(2, "PAYLOAD: %s", sPayLoad);
}

bool PreprocessFrame(int iIndex, WebsocketFrame vFrame, char[] sPayLoad) {
	// Handle fragmented frames
	if (!vFrame.FIN) {
		// Control frames cannot be fragmented
		if (vFrame.OPCODE >= FrameType_Close) {
			LogError("Received fragmented control frame (opcode: %d)", vFrame.OPCODE);
			CloseConnection(iIndex, 1002, "Fragmented control frame not allowed");
			return true;
		}
		
		ArrayList hFragmentedPayload = g_hChildSocketFragmentedPayload.Get(iIndex);
		int iPayloadLength = hFragmentedPayload.Get(0);
		
		// First frame of fragmented message
		if (iPayloadLength == 0) {
			if (vFrame.OPCODE == FrameType_Continuation) {
				LogError("First fragmented frame must not have opcode 0");
				CloseConnection(iIndex, 1002, "Invalid fragmented frame sequence");
				return true;
			}
			hFragmentedPayload.Set(1, view_as<int>(vFrame.OPCODE));
		} else {
			if (vFrame.OPCODE != FrameType_Continuation) {
				LogError("Continuation frame must have opcode 0 (got: %d)", vFrame.OPCODE);
				CloseConnection(iIndex, 1002, "Invalid continuation frame opcode");
				return true;
			}
		}
		
		// Store fragment
		iPayloadLength += vFrame.PAYLOAD_LEN;
		hFragmentedPayload.Set(0, iPayloadLength);
		
		if (vFrame.PAYLOAD_LEN > FRAGMENT_MAX_LENGTH) {
			for (int i = 0; i < vFrame.PAYLOAD_LEN; i += FRAGMENT_MAX_LENGTH) {
				hFragmentedPayload.PushString(sPayLoad[i]);
			}
		} else {
			hFragmentedPayload.PushString(sPayLoad);
		}
		
		return true;
	}
	
	// Handle different frame types
	switch (vFrame.OPCODE) {
		case FrameType_Continuation: {
			ArrayList hFragmentedPayload = g_hChildSocketFragmentedPayload.Get(iIndex);
			int iPayloadLength = hFragmentedPayload.Get(0);
			
			if (iPayloadLength == 0) {
				LogError("Received final fragment without initial frames");
				CloseConnection(iIndex, 1002, "Invalid fragmentation");
				return true;
			}
			
			// Add final fragment
			iPayloadLength += vFrame.PAYLOAD_LEN;
			hFragmentedPayload.Set(0, iPayloadLength);
			
			if (vFrame.PAYLOAD_LEN > FRAGMENT_MAX_LENGTH) {
				for (int i = 0; i < vFrame.PAYLOAD_LEN; i += FRAGMENT_MAX_LENGTH) {
					hFragmentedPayload.PushString(sPayLoad[i]);
				}
			} else {
				hFragmentedPayload.PushString(sPayLoad);
			}
			
			return false; // Allow forwarding to plugin
		}
		
		case FrameType_Text, FrameType_Binary: {
			return false; // Allow forwarding to plugin
		}
		
		case FrameType_Close: {
			// If already closing, finalize disconnect
			if (g_hChildSocketReadyState.Get(iIndex) == State_Closing) {
				CloseChildSocket(iIndex);
				return true;
			}
			
			// Echo close frame
			SendWebsocketFrame(iIndex, sPayLoad, vFrame);
			g_hChildSocketReadyState.Set(iIndex, State_Closing);
			
			// Notify state change
			PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iIndex);
			Call_StartForward(hReadyStateChangeForward);
			Call_PushCell(g_hChildSocketIndexes.Get(iIndex));
			Call_PushCell(State_Closing);
			Call_Finish();
			
			CloseChildSocket(iIndex);
			return true;
		}
		
		case FrameType_Ping: {
			vFrame.OPCODE = FrameType_Pong;
			SendWebsocketFrame(iIndex, sPayLoad, vFrame);
			return true;
		}
		
		case FrameType_Pong: {
			return true;
		}
	}
	
	// Unknown opcode
	LogError("Received frame with unknown opcode: %d", vFrame.OPCODE);
	CloseConnection(iIndex, 1002, "Invalid opcode");
	return true;
}

bool SendWebsocketFrame(int iIndex, char[] sPayLoad, WebsocketFrame vFrame) {
	WebsocketReadyState iReadyState = g_hChildSocketReadyState.Get(iIndex);
	if (iReadyState != State_Open) {
		return false;
	}
	
	int length = vFrame.PAYLOAD_LEN;
	Debug(1, "Sending payload: %s (length: %d)", sPayLoad, length);
	
	// Clear RSV bits
	vFrame.RSV1 = false;
	vFrame.RSV2 = false;
	vFrame.RSV3 = false;
	
	char[] sFrame = new char[length + 14];
	if (!PackFrame(sPayLoad, sFrame, vFrame)) {
		return false;
	}
	
	// Calculate total frame size
	if (length > 65535) {
		length += 10;
	} else if (length > 125) {
		length += 4;
	} else {
		length += 2;
	}
	
	if (vFrame.CLOSE_REASON != -1) {
		length += 2;
	}
	
	Debug(1, "Sending frame (size: %d)", length);
	Handle hSocket = g_hChildSockets.Get(iIndex);
	SocketSend(hSocket, sFrame, length);
	
	return true;
}

bool PackFrame(char[] sPayLoad, char[] sFrame, WebsocketFrame vFrame) {
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
		default: {
			LogError("Attempting to send frame with invalid opcode: %d", vFrame.OPCODE);
			return false;
		}
	}
	
	int iOffset;
	
	// Set payload length
	if (length > 65535) {
		sFrame[1] = 127;
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
		
		if (sFrame[2] > 127) {
			LogError("Payload too large");
			return false;
		}
		iOffset = 10;
	} else if (length > 125) {
		sFrame[1] = 126;
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
		sFrame[1] = length;
		iOffset = 2;
	}
	
	// Ensure MASK bit is not set (server doesn't mask)
	sFrame[1] &= ~(1 << 7);
	vFrame.MASK = false;
	
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
	
	// Add payload
	strcopy(sFrame[iOffset], length + 1, sPayLoad);
	
	return true;
}

void CloseConnection(int iIndex, int iCloseReason, char[] sPayLoad) {
	WebsocketFrame vFrame;
	vFrame.OPCODE = FrameType_Close;
	vFrame.CLOSE_REASON = iCloseReason;
	vFrame.PAYLOAD_LEN = strlen(sPayLoad);
	vFrame.FIN = true;
	
	SendWebsocketFrame(iIndex, sPayLoad, vFrame);
	g_hChildSocketReadyState.Set(iIndex, State_Closing);
	
	// Notify state change
	PrivateForward hReadyStateChangeForward = g_hChildReadyStateChangeForwards.Get(iIndex);
	Call_StartForward(hReadyStateChangeForward);
	Call_PushCell(g_hChildSocketIndexes.Get(iIndex));
	Call_PushCell(State_Closing);
	Call_Finish();
}

// Utility Functions

void Debug(int iDebugLevel, const char[] fmt, any ...) {
#if DEBUG > 0
	if (iDebugLevel > DEBUG) {
		return;
	}
	
	char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), fmt, 3);
	LogToFile(g_sLog, sBuffer);
#else
	#pragma unused iDebugLevel, fmt
#endif
}

int BinToDec(const char[] sBinary) {
	int ret = 0;
	int len = strlen(sBinary);
	
	for (int i = 0; i < len; i++) {
		ret = ret << 1;
		if (sBinary[i] == '1') {
			ret |= 1;
		}
	}
	
	return ret;
}

bool IsPluginStillLoaded(Handle plugin) {
	Handle hIt = GetPluginIterator();
	bool bPluginLoaded = false;
	
	while (MorePlugins(hIt)) {
		Handle hPlugin = ReadPlugin(hIt);
		if (hPlugin == plugin && GetPluginStatus(hPlugin) == Plugin_Running) {
			bPluginLoaded = true;
			break;
		}
	}
	
	delete hIt;
	return bPluginLoaded;
}