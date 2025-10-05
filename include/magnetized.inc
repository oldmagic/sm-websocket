/**
 * Magnetized Common Library
 * Shared utilities, constants, and helper functions for Magnetized plugins
 * 
 * Organization: Magnetized
 * Version: 2.2.0 - Updated with modern SourceMod patterns
 */

#if defined _magnetized_included
 #endinput
#endif
#define _magnetized_included

// ========================== CONSTANTS ==========================

#define MAGNETIZED_VERSION "2.2.0"
#define MAGNETIZED_PREFIX "[Magnetized]"

// Team constants
#define TEAM_NONE 0
#define TEAM_SPEC 1
#define TEAM_T 2
#define TEAM_CT 3

// Limits
#define MAX_PLAYERS 64
#define MAGNETIZED_MAX_NAME_LENGTH 64
#define MAX_STEAMID_LENGTH 64
#define MAX_MESSAGE_LENGTH 256
#define MAX_WEAPON_LENGTH 64

// Chat colors (using CS:GO/CS2 color codes)
#define COLOR_DEFAULT "\x01"
#define COLOR_TEAMCOLOR "\x03"
#define COLOR_GREEN "\x04"
#define COLOR_LIGHTGREEN "\x05"
#define COLOR_RED "\x06"
#define COLOR_BLUE "\x0B"
#define COLOR_PURPLE "\x0C"
#define COLOR_ORANGE "\x10"

#define MAG_TEAM_COLOR(team) ((team) == TEAM_T ? COLOR_ORANGE : ((team) == TEAM_CT ? COLOR_BLUE : ((team) == TEAM_SPEC ? COLOR_LIGHTGREEN : COLOR_DEFAULT)))

// Weapon slots
#define SLOT_PRIMARY 0
#define SLOT_SECONDARY 1
#define SLOT_KNIFE 2
#define SLOT_GRENADES 3
#define SLOT_C4 4

// ========================== ENUMS ==========================

enum TimeoutType
{
    Timeout_None = 0,
    Timeout_Tactical,
    Timeout_Technical,
    Timeout_Disconnect
}

enum MatchState
{
    MatchState_None = 0,
    MatchState_Warmup,
    MatchState_Knife,
    MatchState_Live,
    MatchState_Paused,
    MatchState_Completed
}

enum WeaponType
{
    WeaponType_Unknown = 0,
    WeaponType_Pistol,
    WeaponType_SMG,
    WeaponType_Rifle,
    WeaponType_Sniper,
    WeaponType_Shotgun,
    WeaponType_MachineGun,
    WeaponType_Grenade,
    WeaponType_Knife,
    WeaponType_C4
}

// ========================== METHODMAPS ==========================

methodmap MagnetizedPlayer
{
    public MagnetizedPlayer(int client)
    {
        return view_as<MagnetizedPlayer>(client);
    }
    
    property int Client
    {
        public get() { return view_as<int>(this); }
    }
    
    public bool IsValid()
    {
        int client = this.Client;
        return (client > 0 && client <= MaxClients && IsClientInGame(client));
    }
    
    public bool IsConnected()
    {
        int client = this.Client;
        return (client > 0 && client <= MaxClients && IsClientConnected(client));
    }
    
    public bool IsBot()
    {
        return this.IsValid() && IsFakeClient(this.Client);
    }
    
    public bool IsHuman()
    {
        return this.IsValid() && !IsFakeClient(this.Client);
    }
    
    public bool IsAlive()
    {
        return this.IsValid() && IsPlayerAlive(this.Client);
    }
    
    public int GetTeam()
    {
        return this.IsValid() ? GetClientTeam(this.Client) : TEAM_NONE;
    }
    
    public bool IsOnTeam(int team)
    {
        return this.GetTeam() == team;
    }
    
    public bool IsPlayingTeam()
    {
        int team = this.GetTeam();
        return (team == TEAM_T || team == TEAM_CT);
    }
    
    public int GetHealth()
    {
        return this.IsValid() ? GetClientHealth(this.Client) : 0;
    }
    
    public int GetArmor()
    {
        return this.IsValid() ? GetClientArmor(this.Client) : 0;
    }
    
    public int GetFrags()
    {
        return this.IsValid() ? GetClientFrags(this.Client) : 0;
    }
    
    public int GetDeaths()
    {
        return this.IsValid() ? GetClientDeaths(this.Client) : 0;
    }
    
    public bool GetName(char[] buffer, int maxlen)
    {
        if (!this.IsValid())
            return false;
        return GetClientName(this.Client, buffer, maxlen);
    }
    
    public bool GetAuthId(char[] buffer, int maxlen, AuthIdType authType = AuthId_SteamID64)
    {
        if (!this.IsValid())
            return false;
        return GetClientAuthId(this.Client, authType, buffer, maxlen, true);
    }
    
    public bool HasWeapon(const char[] weaponName)
    {
        if (!this.IsValid())
            return false;
        
        char className[64];
        if (weaponName[0] == 'w' && weaponName[1] == 'e' && weaponName[2] == 'a')
            strcopy(className, sizeof(className), weaponName);
        else
            Format(className, sizeof(className), "weapon_%s", weaponName);
        
        int weapon = GetPlayerWeaponSlot(this.Client, SLOT_PRIMARY);
        if (weapon != -1)
        {
            char weaponClass[64];
            GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
            if (StrEqual(className, weaponClass, false))
                return true;
        }
        
        weapon = GetPlayerWeaponSlot(this.Client, SLOT_SECONDARY);
        if (weapon != -1)
        {
            char weaponClass[64];
            GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
            if (StrEqual(className, weaponClass, false))
                return true;
        }
        
        return false;
    }
    
    public void PrintToChat(const char[] format, any ...)
    {
        if (!this.IsValid())
            return;
        
        char buffer[MAX_MESSAGE_LENGTH];
        VFormat(buffer, sizeof(buffer), format, 3);
        PrintToChat(this.Client, "%s", buffer);
    }
    
    public void PrintToConsole(const char[] format, any ...)
    {
        if (!this.IsValid())
            return;
        
        char buffer[MAX_MESSAGE_LENGTH];
        VFormat(buffer, sizeof(buffer), format, 3);
        PrintToConsole(this.Client, "%s", buffer);
    }
}

// ========================== TEAM UTILITIES ==========================

/**
 * Gets the opposite team
 * @param team      Team to get opposite of
 * @return          Opposite team (T<->CT) or 0 if invalid
 */
stock int Mag_GetOppositeTeam(int team)
{
    switch (team)
    {
        case TEAM_T: return TEAM_CT;
        case TEAM_CT: return TEAM_T;
        default: return TEAM_NONE;
    }
}

/**
 * Gets a team name string
 * @param team      Team index
 * @param buffer    Buffer to store name
 * @param maxlen    Maximum buffer length
 */
stock void Mag_GetTeamName(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_T:
        {
            strcopy(buffer, maxlen, "Terrorist");
            return;
        }
        case TEAM_CT:
        {
            strcopy(buffer, maxlen, "Counter-Terrorist");
            return;
        }
        case TEAM_SPEC:
        {
            strcopy(buffer, maxlen, "Spectator");
            return;
        }
    }

    strcopy(buffer, maxlen, "None");
}

/**
 * Gets a short team name string
 * @param team      Team index
 * @param buffer    Buffer to store name
 * @param maxlen    Maximum buffer length
 */
stock void Mag_GetTeamNameShort(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_T:
        {
            strcopy(buffer, maxlen, "T");
            return;
        }
        case TEAM_CT:
        {
            strcopy(buffer, maxlen, "CT");
            return;
        }
        case TEAM_SPEC:
        {
            strcopy(buffer, maxlen, "SPEC");
            return;
        }
    }

    strcopy(buffer, maxlen, "NONE");
}

/**
 * Gets team color for chat
 * @param team      Team index
 * @param buffer    Buffer that receives the color code
 * @param maxlen    Maximum buffer length
 */
stock void Mag_GetTeamColor(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_T:
        {
            strcopy(buffer, maxlen, COLOR_ORANGE);
            return;
        }
        case TEAM_CT:
        {
            strcopy(buffer, maxlen, COLOR_BLUE);
            return;
        }
        case TEAM_SPEC:
        {
            strcopy(buffer, maxlen, COLOR_LIGHTGREEN);
            return;
        }
    }

    strcopy(buffer, maxlen, COLOR_DEFAULT);
}

// ========================== MATH UTILITIES ==========================

/**
 * Returns the maximum of two integers
 */
stock int Mag_Max(int a, int b)
{
    return (a > b) ? a : b;
}

/**
 * Returns the minimum of two integers
 */
stock int Mag_Min(int a, int b)
{
    return (a < b) ? a : b;
}

/**
 * Clamps a value between min and max
 */
stock int Mag_Clamp(int value, int min, int max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

/**
 * Clamps a float value between min and max
 */
stock float Mag_ClampFloat(float value, float min, float max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

/**
 * Linear interpolation between two values
 */
stock float Mag_Lerp(float a, float b, float t)
{
    return a + (b - a) * Mag_ClampFloat(t, 0.0, 1.0);
}

/**
 * Returns absolute value
 */
stock int Mag_Abs(int value)
{
    return (value < 0) ? -value : value;
}

/**
 * Returns absolute value (float)
 */
stock float Mag_AbsFloat(float value)
{
    return (value < 0.0) ? -value : value;
}

/**
 * Rounds a float to specified decimal places
 */
stock float Mag_Round(float value, int decimals = 0)
{
    float multiplier = Pow(10.0, float(decimals));
    return RoundToNearest(value * multiplier) / multiplier;
}

// ========================== STRING UTILITIES ==========================

/**
 * Sanitizes a string for use in filenames
 * @param str       String to sanitize (modified in place)
 * @param maxlen    Maximum length
 */
stock void Mag_SanitizeFilename(char[] str, int maxlen)
{
    int len = strlen(str);
    if (len >= maxlen)
        len = maxlen - 1;
    
    for (int i = 0; i < len; i++)
    {
        char c = str[i];
        bool valid = 
            (c >= 'a' && c <= 'z') || 
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || 
            c == '_' || c == '-' || c == '.';
        
        if (!valid)
            str[i] = '_';
    }
}

/**
 * Escapes quotes in a string for JSON
 * @param input     Input string
 * @param output    Output buffer
 * @param maxlen    Maximum output length
 */
stock void Mag_EscapeQuotes(const char[] input, char[] output, int maxlen)
{
    strcopy(output, maxlen, input);
    ReplaceString(output, maxlen, "\\", "\\\\", false);
    ReplaceString(output, maxlen, "\"", "\\\"", false);
    ReplaceString(output, maxlen, "\n", "\\n", false);
    ReplaceString(output, maxlen, "\r", "\\r", false);
    ReplaceString(output, maxlen, "\t", "\\t", false);
}

/**
 * Formats a timestamp
 * @param buffer    Output buffer
 * @param maxlen    Maximum buffer length
 * @param timestamp Unix timestamp (0 = current time)
 */
stock void Mag_FormatTimestamp(char[] buffer, int maxlen, int timestamp = 0)
{
    if (timestamp <= 0)
        timestamp = GetTime();
    
    FormatTime(buffer, maxlen, "%Y-%m-%d %H:%M:%S", timestamp);
}

/**
 * Formats a duration in seconds to readable string (e.g., "2h 30m 15s")
 * @param buffer    Output buffer
 * @param maxlen    Maximum buffer length
 * @param seconds   Duration in seconds
 */
stock void Mag_FormatDuration(char[] buffer, int maxlen, int seconds)
{
    int hours = seconds / 3600;
    int mins = (seconds % 3600) / 60;
    int secs = seconds % 60;
    
    if (hours > 0)
        Format(buffer, maxlen, "%dh %dm %ds", hours, mins, secs);
    else if (mins > 0)
        Format(buffer, maxlen, "%dm %ds", mins, secs);
    else
        Format(buffer, maxlen, "%ds", secs);
}

/**
 * Strips color codes from a string
 * @param input     Input string
 * @param output    Output buffer
 * @param maxlen    Maximum output length
 */
stock void Mag_StripColors(const char[] input, char[] output, int maxlen)
{
    int j = 0;
    int len = strlen(input);
    
    for (int i = 0; i < len && j < maxlen - 1; i++)
    {
        if (input[i] == '\x01' || input[i] == '\x02' || input[i] == '\x03' ||
            input[i] == '\x04' || input[i] == '\x05' || input[i] == '\x06' ||
            input[i] == '\x07' || input[i] == '\x08' || input[i] == '\x09' ||
            input[i] == '\x0A' || input[i] == '\x0B' || input[i] == '\x0C' ||
            input[i] == '\x0D' || input[i] == '\x0E' || input[i] == '\x0F' ||
            input[i] == '\x10')
        {
            continue;
        }
        
        output[j++] = input[i];
    }
    
    output[j] = '\0';
}

/**
 * Checks if string contains only alphanumeric characters
 */
stock bool Mag_IsAlphaNumeric(const char[] str)
{
    int len = strlen(str);
    for (int i = 0; i < len; i++)
    {
        char c = str[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
            return false;
    }
    return true;
}

// ========================== PLAYER UTILITIES ==========================

/**
 * Counts players by team
 * @param totalOut      Output: total human players
 * @param tOut          Output: T players
 * @param ctOut         Output: CT players
 */
stock void Mag_CountPlayers(int &totalOut = 0, int &tOut = 0, int &ctOut = 0)
{
    totalOut = 0;
    tOut = 0;
    ctOut = 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
        
        totalOut++;
        int team = GetClientTeam(i);
        
        if (team == TEAM_T)
            tOut++;
        else if (team == TEAM_CT)
            ctOut++;
    }
}

/**
 * Gets alive players on a team
 * @param team      Team to count
 * @return          Number of alive players
 */
stock int Mag_GetAliveCount(int team)
{
    int count = 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
        
        if (GetClientTeam(i) == team && IsPlayerAlive(i))
            count++;
    }
    
    return count;
}

/**
 * Gets total players on a team (including dead)
 * @param team      Team to count
 * @return          Number of players
 */
stock int Mag_GetTeamCount(int team)
{
    int count = 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
        
        if (GetClientTeam(i) == team)
            count++;
    }
    
    return count;
}

/**
 * Checks if a player is in a clutch situation
 * @param client    Client index
 * @return          True if player is last alive on their team with enemies remaining
 */
stock bool Mag_IsClutchSituation(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return false;
    
    if (!IsPlayerAlive(client))
        return false;
    
    int clientTeam = GetClientTeam(client);
    if (clientTeam != TEAM_T && clientTeam != TEAM_CT)
        return false;
    
    int aliveTeammates = 0;
    int aliveEnemies = 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
            continue;
        
        int team = GetClientTeam(i);
        if (team == clientTeam)
        {
            if (i != client)
                aliveTeammates++;
        }
        else if (team == Mag_GetOppositeTeam(clientTeam))
        {
            aliveEnemies++;
        }
    }
    
    return (aliveTeammates == 0 && aliveEnemies > 0);
}

/**
 * Gets client by Steam ID
 * @param steamid   Steam ID string (any format)
 * @return          Client index or 0 if not found
 */
stock int Mag_GetClientBySteamId(const char[] steamid)
{
    if (!steamid[0])
        return 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
        
        char clientSteamId[MAX_STEAMID_LENGTH];
        if (GetClientAuthId(i, AuthId_SteamID64, clientSteamId, sizeof(clientSteamId), true))
        {
            if (StrEqual(steamid, clientSteamId, false))
                return i;
        }
        
        // Try Steam2 format
        if (GetClientAuthId(i, AuthId_Steam2, clientSteamId, sizeof(clientSteamId), true))
        {
            if (StrEqual(steamid, clientSteamId, false))
                return i;
        }
        
        // Try Steam3 format
        if (GetClientAuthId(i, AuthId_Steam3, clientSteamId, sizeof(clientSteamId), true))
        {
            if (StrEqual(steamid, clientSteamId, false))
                return i;
        }
    }
    
    return 0;
}

/**
 * Validates client index with additional checks
 * @param client        Client index
 * @param checkAlive    Also check if alive
 * @param checkTeam     Also check if on playing team
 * @return              True if valid
 */
stock bool Mag_IsValidClient(int client, bool checkAlive = false, bool checkTeam = false)
{
    if (client <= 0 || client > MaxClients)
        return false;
    
    if (!IsClientInGame(client))
        return false;
    
    if (IsFakeClient(client))
        return false;
    
    if (checkAlive && !IsPlayerAlive(client))
        return false;
    
    if (checkTeam)
    {
        int team = GetClientTeam(client);
        if (team != TEAM_T && team != TEAM_CT)
            return false;
    }
    
    return true;
}

// ========================== WEAPON UTILITIES ==========================

/**
 * Checks if a weapon is a sniper rifle
 * @param weapon    Weapon classname or name
 * @return          True if weapon is a sniper rifle
 */
stock bool Mag_IsSniperWeapon(const char[] weapon)
{
    return (
        StrContains(weapon, "awp", false) != -1 ||
        StrContains(weapon, "ssg08", false) != -1 ||
        StrContains(weapon, "scar20", false) != -1 ||
        StrContains(weapon, "g3sg1", false) != -1
    );
}

/**
 * Checks if a weapon is a pistol
 * @param weapon    Weapon classname or name
 * @return          True if weapon is a pistol
 */
stock bool Mag_IsPistolWeapon(const char[] weapon)
{
    return (
        StrContains(weapon, "glock", false) != -1 ||
        StrContains(weapon, "hkp2000", false) != -1 ||
        StrContains(weapon, "usp", false) != -1 ||
        StrContains(weapon, "p250", false) != -1 ||
        StrContains(weapon, "elite", false) != -1 ||
        StrContains(weapon, "fiveseven", false) != -1 ||
        StrContains(weapon, "tec9", false) != -1 ||
        StrContains(weapon, "cz75", false) != -1 ||
        StrContains(weapon, "deagle", false) != -1 ||
        StrContains(weapon, "revolver", false) != -1
    );
}

/**
 * Checks if a weapon is a rifle
 * @param weapon    Weapon classname or name
 * @return          True if weapon is a rifle
 */
stock bool Mag_IsRifleWeapon(const char[] weapon)
{
    return (
        StrContains(weapon, "ak47", false) != -1 ||
        StrContains(weapon, "m4a1", false) != -1 ||
        StrContains(weapon, "m4a4", false) != -1 ||
        StrContains(weapon, "famas", false) != -1 ||
        StrContains(weapon, "galilar", false) != -1 ||
        StrContains(weapon, "aug", false) != -1 ||
        StrContains(weapon, "sg556", false) != -1
    );
}

/**
 * Gets weapon type from classname
 * @param weapon    Weapon classname
 * @return          WeaponType enum value
 */
stock WeaponType Mag_GetWeaponType(const char[] weapon)
{
    if (Mag_IsSniperWeapon(weapon))
        return WeaponType_Sniper;
    if (Mag_IsRifleWeapon(weapon))
        return WeaponType_Rifle;
    if (Mag_IsPistolWeapon(weapon))
        return WeaponType_Pistol;
    
    if (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1)
        return WeaponType_Knife;
    if (StrContains(weapon, "c4", false) != -1)
        return WeaponType_C4;
    if (StrContains(weapon, "flashbang", false) != -1 || StrContains(weapon, "hegrenade", false) != -1 ||
        StrContains(weapon, "smokegrenade", false) != -1 || StrContains(weapon, "molotov", false) != -1 ||
        StrContains(weapon, "incgrenade", false) != -1 || StrContains(weapon, "decoy", false) != -1)
        return WeaponType_Grenade;
    if (StrContains(weapon, "nova", false) != -1 || StrContains(weapon, "xm1014", false) != -1 ||
        StrContains(weapon, "mag7", false) != -1 || StrContains(weapon, "sawedoff", false) != -1)
        return WeaponType_Shotgun;
    if (StrContains(weapon, "mac10", false) != -1 || StrContains(weapon, "mp9", false) != -1 ||
        StrContains(weapon, "mp7", false) != -1 || StrContains(weapon, "ump45", false) != -1 ||
        StrContains(weapon, "p90", false) != -1 || StrContains(weapon, "bizon", false) != -1 ||
        StrContains(weapon, "mp5", false) != -1)
        return WeaponType_SMG;
    if (StrContains(weapon, "m249", false) != -1 || StrContains(weapon, "negev", false) != -1)
        return WeaponType_MachineGun;
    
    return WeaponType_Unknown;
}

/**
 * Checks if a player is currently scoped
 * @param client    Client index
 * @return          True if player is scoped with a sniper
 */
stock bool Mag_IsPlayerScoped(int client)
{
    if (client <= 0 || !IsClientInGame(client))
        return false;
    
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)
        return false;
    
    char weaponName[MAX_WEAPON_LENGTH];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName));
    
    if (Mag_IsSniperWeapon(weaponName))
    {
        int fov = GetEntProp(client, Prop_Send, "m_iFOV");
        int defaultFov = GetEntProp(client, Prop_Send, "m_iDefaultFOV");
        return (fov < defaultFov);
    }
    
    return false;
}

/**
 * Gets player's active weapon classname
 * @param client    Client index
 * @param buffer    Output buffer
 * @param maxlen    Maximum buffer length
 * @return          True if weapon found
 */
stock bool Mag_GetActiveWeapon(int client, char[] buffer, int maxlen)
{
    if (client <= 0 || !IsClientInGame(client))
        return false;
    
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)
        return false;
    
    return GetEntityClassname(weapon, buffer, maxlen);
}

// ========================== GAME STATE UTILITIES ==========================

/**
 * Freezes or unfreezes a player
 * @param client    Client index
 * @param freeze    True to freeze, false to unfreeze
 * @return          Previous lag compensation value
 */
stock float Mag_FreezePlayer(int client, bool freeze)
{
    if (client <= 0 || !IsClientInGame(client))
        return 1.0;
    
    float oldValue = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
    
    if (freeze)
    {
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.0);
        float vel[3] = {0.0, 0.0, 0.0};
        TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
    }
    else
    {
        float value = (oldValue <= 0.0) ? 1.0 : oldValue;
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", value);
    }
    
    return oldValue;
}

/**
 * Broadcasts a message to all players with prefix
 * @param prefix    Message prefix
 * @param format    Format string
 * @param ...       Format arguments
 */
stock void Mag_Announce(const char[] prefix, const char[] format, any ...)
{
    char message[MAX_MESSAGE_LENGTH];
    VFormat(message, sizeof(message), format, 3);
    
    PrintToChatAll("%s %s", prefix, message);
    PrintToServer("%s %s", prefix, message);
}

/**
 * Broadcasts a colored message to all players
 * @param format    Format string (can contain color codes)
 * @param ...       Format arguments
 */
stock void Mag_AnnounceColored(const char[] format, any ...)
{
    char message[MAX_MESSAGE_LENGTH];
    VFormat(message, sizeof(message), format, 2);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            PrintToChat(i, "%s", message);
    }
    
    // Strip colors for server console
    char stripped[MAX_MESSAGE_LENGTH];
    Mag_StripColors(message, stripped, sizeof(stripped));
    PrintToServer("%s", stripped);
}

/**
 * Builds the win threshold for current match state
 * @param maxRounds         Max rounds in regulation
 * @param inOvertime        Whether currently in overtime
 * @param overtimeMaxRounds Max rounds per overtime period
 * @return                  Rounds needed to win current period
 */
stock int Mag_GetWinThreshold(int maxRounds, bool inOvertime = false, int overtimeMaxRounds = 6)
{
    if (inOvertime)
    {
        if (overtimeMaxRounds < 2)
            overtimeMaxRounds = 6;
        return (overtimeMaxRounds / 2) + 1;
    }
    
    if (maxRounds < 2)
        maxRounds = 24;
    
    return (maxRounds / 2) + 1;
}

/**
 * Calculates K/D ratio
 * @param kills     Kill count
 * @param deaths    Death count
 * @return          K/D ratio
 */
stock float Mag_CalculateKD(int kills, int deaths)
{
    if (deaths <= 0)
        return float(kills);
    
    return float(kills) / float(deaths);
}

/**
 * Calculates headshot percentage
 * @param headshots Total headshots
 * @param kills     Total kills
 * @return          Headshot percentage (0.0-100.0)
 */
stock float Mag_CalculateHSPercent(int headshots, int kills)
{
    if (kills <= 0)
        return 0.0;
    
    return (float(headshots) / float(kills)) * 100.0;
}

/**
 * Calculates average damage per round
 * @param totalDamage   Total damage dealt
 * @param rounds        Number of rounds played
 * @return              ADR value
 */
stock float Mag_CalculateADR(int totalDamage, int rounds)
{
    if (rounds <= 0)
        return 0.0;
    
    return float(totalDamage) / float(rounds);
}

/**
 * Calculates Kill-Assist-Survive-Trade (KAST) percentage
 * @param rounds        Total rounds played
 * @param kastRounds    Rounds with K/A/S/T
 * @return              KAST percentage (0.0-100.0)
 */
stock float Mag_CalculateKAST(int rounds, int kastRounds)
{
    if (rounds <= 0)
        return 0.0;
    
    return (float(kastRounds) / float(rounds)) * 100.0;
}

/**
 * Calculates Rating 2.0 (simplified HLTV formula)
 * @param kills         Total kills
 * @param deaths        Total deaths
 * @param assists       Total assists
 * @param adr           Average damage per round
 * @param kast          KAST percentage
 * @return              Rating 2.0 value
 */
stock float Mag_CalculateRating2(int kills, int deaths, int assists, float adr, float kast)
{
    float kd = Mag_CalculateKD(kills, deaths);
    
    // Simplified formula (actual HLTV formula is more complex)
    float rating = (0.0073 * kast) + 
                   (0.3591 * (kills + assists)) / Mag_Max(deaths, 1) +
                   (-0.5329) +
                   (0.00647 * adr) +
                   (0.1 * kd);
    
    return Mag_ClampFloat(rating, 0.0, 3.0);
}

// ========================== FILE UTILITIES ==========================

/**
 * Checks if a file exists and is readable
 * @param path      File path
 * @return          True if file exists and is readable
 */
stock bool Mag_IsFileReadable(const char[] path)
{
    if (!FileExists(path))
        return false;
    
    File f = OpenFile(path, "rb");
    if (f == null)
        return false;
    
    delete f;
    return true;
}

/**
 * Gets file size in bytes
 * @param path      File path
 * @return          File size or -1 on error
 */
stock int Mag_GetFileSize(const char[] path)
{
    if (!FileExists(path))
        return -1;
    
    File f = OpenFile(path, "rb");
    if (f == null)
        return -1;
    
    f.Seek(0, SEEK_END);
    int size = f.Position;
    delete f;
    
    return size;
}

/**
 * Formats file size to human-readable string
 * @param bytes     File size in bytes
 * @param buffer    Output buffer
 * @param maxlen    Maximum buffer length
 */
stock void Mag_FormatFileSize(int bytes, char[] buffer, int maxlen)
{
    if (bytes < 1024)
        Format(buffer, maxlen, "%d B", bytes);
    else if (bytes < 1048576)
        Format(buffer, maxlen, "%.2f KB", float(bytes) / 1024.0);
    else if (bytes < 1073741824)
        Format(buffer, maxlen, "%.2f MB", float(bytes) / 1048576.0);
    else
        Format(buffer, maxlen, "%.2f GB", float(bytes) / 1073741824.0);
}

// ========================== ARRAY UTILITIES ==========================

/**
 * Checks if an array contains a value
 * @param array     Array to search
 * @param size      Array size
 * @param value     Value to find
 * @return          True if found
 */
stock bool Mag_ArrayContains(const int[] array, int size, int value)
{
    for (int i = 0; i < size; i++)
    {
        if (array[i] == value)
            return true;
    }
    return false;
}

/**
 * Shuffles an array using Fisher-Yates algorithm
 * @param array     Array to shuffle
 * @param size      Array size
 */
stock void Mag_ShuffleArray(int[] array, int size)
{
    for (int i = size - 1; i > 0; i--)
    {
        int j = GetRandomInt(0, i);
        int temp = array[i];
        array[i] = array[j];
        array[j] = temp;
    }
}

// ========================== VERSION INFO ==========================

/**
 * Gets the Magnetized library version
 * @param buffer    Output buffer
 * @param maxlen    Maximum buffer length
 */
stock void Mag_GetVersion(char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, MAGNETIZED_VERSION);
}

/**
 * Prints version information to server console
 */
stock void Mag_PrintVersionInfo()
{
    PrintToServer("===========================================");
    PrintToServer("  Magnetized Common Library v%s", MAGNETIZED_VERSION);
    PrintToServer("  Shared utilities for CS:CO plugins");
    PrintToServer("  Modern SourceMod 1.12+ compatible");
    PrintToServer("===========================================");
}

// ========================== DEPRECATED (Backward Compatibility) ==========================

/**
 * @deprecated Use Mag_IsValidClient instead
 */
#pragma deprecated Use Mag_IsValidClient() instead
stock bool IsValidClient(int client, bool checkAlive = false, bool checkTeam = false)
{
    return Mag_IsValidClient(client, checkAlive, checkTeam);
}

public Extension __ext_magnetized = 
{
    name = "Magnetized Common Library",
    file = "magnetized.inc",
    autoload = 0,
    required = 0,
};
