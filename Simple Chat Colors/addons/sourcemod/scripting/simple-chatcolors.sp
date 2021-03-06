/************************************************************************
*************************************************************************
Simple Chat Colors
Description:
		Changes the colors of players chat based on config file
*************************************************************************
*************************************************************************
This file is part of Simple Plugins project.

This plugin is free software: you can redistribute 
it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or
later version. 

This plugin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this plugin.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************
*************************************************************************
File Information
$Id$
$Author$
$Revision$
$Date$
$LastChangedBy$
$LastChangedDate$
$URL$
$Copyright: (c) Simple Plugins 2008-2009$
*************************************************************************
*************************************************************************
*/

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <loghelper>
#include <simple-plugins>
#undef REQUIRE_PLUGIN
#include <autoupdate>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.3.0"

#define CHAT_SYMBOL_ADMIN 			'@'
#define CHAT_SYMBOL_CLAN 			'#'
#define CHAT_TRIGGER_PUBLIC 	'!'
#define CHAT_TRIGGER_PRIVATE 	'/'
#define CHAR_PERCENT						"%"
#define CHAR_NULL 							"\0"
#define CHAR_FILTER							"*"

enum e_Settings
{
Handle:hGroupName,
Handle:hGroupFlag,
Handle:hNameColor,
Handle:hTextColor,
Handle:hTagText,
Handle:hTagColor,
Handle:hOverrides
};

enum e_AutoResponses
{
Handle:hPhrase,
Handle:hResponse,
Handle:hMatch
};

enum e_ChatType
{
	ChatType_All,
	ChatType_Team,
	ChatType_Clan,
	ChatType_SpectatorAll,
	ChatType_SpectatorTeam
};

enum e_DeadChat
{
	DeadChat_Restricted,
	DeadChat_Normal,
	DeadChat_UnRestricted
};

new Handle:g_Cvar_hDebug = INVALID_HANDLE;
new Handle:g_Cvar_hTriggerBackup = INVALID_HANDLE;
new Handle:g_Cvar_hClanChatEnabled = INVALID_HANDLE;
new Handle:g_Cvar_hClanFlag = INVALID_HANDLE;
new Handle:g_Cvar_hDeadChat = INVALID_HANDLE;
new Handle:g_Cvar_hChatFilterEnabled = INVALID_HANDLE;
new Handle:g_Cvar_hChatColorTagsEnabled = INVALID_HANDLE;
new Handle:g_Cvar_hAutoResponseEnabled = INVALID_HANDLE;
new Handle:g_aBadWords = INVALID_HANDLE;
new Handle:g_aSettings[e_Settings];
new Handle:g_aResponses[e_AutoResponses];

new bool:g_bDebug = false;
new bool:g_bTriggerBackup = false;
new bool:g_bOverrideSection = false;
new bool:g_bClanChatEnabled = false;
new bool:g_bChatFilterEnabled = false;
new bool:g_bAutoResponseEnabled = false;
new bool:g_bChatColorTagsEnabled = false;
new bool:g_aPlayerClanMember[MAXPLAYERS + 1] = { false, ... };
new bool:g_aPlayerGagged[MAXPLAYERS + 1] = { false, ... };

new String:g_sClanFlags[16];

new g_iArraySize;
new e_DeadChat:g_eDeadChatMode;
new g_aPlayerIndex[MAXPLAYERS + 1] = { -1, ... };


public Plugin:myinfo =
{
	name = "Simple Chat Colors",
	author = "Simple Plugins",
	description = "Changes the colors of players chat based on config file.",
	version = PLUGIN_VERSION,
	url = "http://www.simple-plugins.com"
};


/**
Below is call to include a modified version of the base antiflood.sp plugin.  
All credit goes to SourceMod dev team
*/
#include "simple-plugins/antiflood.sp"


/**
Sourcemod callbacks
*/
public OnPluginStart()
{
	
	/**
	Get game type and load the team numbers
	*/
	g_CurrentMod = GetCurrentMod();
	LoadCurrentTeams();
	LogAction(0, -1, "[SCC] Detected [%s].", g_sGameName[g_CurrentMod]);
	
	/**
	Need to create all of our console variables.
	*/
	CreateConVar("sm_chatcolors_version", PLUGIN_VERSION, "Simple Chat Colors", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_hDeadChat = CreateConVar("scc_deadchat", "1", "0 = Dead can't see or type chat \n 1 = Dead can see all chat and type to other dead players \n 2 = Dead can see and type chat to all");
	g_Cvar_hDebug = CreateConVar("scc_debug", "0", "Enable/Disable debugging information");
	g_Cvar_hTriggerBackup = CreateConVar("scc_triggerbackup", "0", "Enable/Disable the trigger backup");
	g_Cvar_hClanChatEnabled = CreateConVar("scc_clanchat_enabled", "1", "Enable/Disable clan chat");
	g_Cvar_hClanFlag = CreateConVar("scc_clanflag", "a", "Specify the admin flag given to clan members");
	g_Cvar_hChatFilterEnabled = CreateConVar("scc_chatfilter_enabled", "1", "Enable/Disable chat filtering");
	g_Cvar_hAutoResponseEnabled = CreateConVar("scc_autoresponse_enabled", "1", "Enable/Disable auto responses");
	g_Cvar_hChatColorTagsEnabled = CreateConVar("scc_chatcolortags_enabled", "1", "Enable/Disable color tags in chat messages");
	
	/**
	Hook console variables
	*/
	HookConVarChange(g_Cvar_hDebug, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hTriggerBackup, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hClanChatEnabled, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hDeadChat, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hChatFilterEnabled, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hAutoResponseEnabled, ConVarSettingsChanged);
	HookConVarChange(g_Cvar_hChatColorTagsEnabled, ConVarSettingsChanged);
	
	/**
	Need to register the commands we are going to use
	*/
	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_SayTeam);
	AddCommandListener(Command_SMgag, "sm_gag");
	AddCommandListener(Command_SMungag, "sm_ungag");
	AddCommandListener(Command_SMsilence, "sm_silence");
	AddCommandListener(Command_SMunsilence, "sm_unsilence");
	RegAdminCmd("sm_reloadscc", Command_Reload, ADMFLAG_GENERIC,  "Reloads settings from the config files");
	RegAdminCmd("sm_printcolors", Command_PrintColors, ADMFLAG_GENERIC,  "Prints out the color names in their color");
	
	/**
	Create the arrays
	*/
	for (new e_Settings:i; i < e_Settings:sizeof(g_aSettings); i++)
	{
		g_aSettings[i] = CreateArray(256, 1);
	}
	
	for (new e_AutoResponses:i; i < e_AutoResponses:sizeof(g_aResponses); i++)
	{
		g_aResponses[i] = CreateArray(512, 1);
	}
	
	g_aBadWords = CreateArray(128, 1);
	
	/**
	Load translation file
	*/
	LoadTranslations ("common.phrases");
	LoadTranslations ("scc.phrases");
	
	/**
	Load the admins and colors from the config
	*/
	ReloadConfigFiles();
	
	/**
	Init the antiflood plugin
	*/
	InitAntiFlood();
	
	/**
	Load the config file
	*/
	AutoExecConfig();
}

public OnAllPluginsLoaded()
{
	
	/*
	Deal with some known plugin conflicts
	*/
	new Handle:hAntiFlood = FindConVar("sm_flood_time");
	if (hAntiFlood != INVALID_HANDLE)
	{
		new String:sNewFile[PLATFORM_MAX_PATH + 1], String:sOldFile[PLATFORM_MAX_PATH + 1];
		BuildPath(Path_SM, sNewFile, sizeof(sNewFile), "plugins/disabled/antiflood.smx");
		BuildPath(Path_SM, sOldFile, sizeof(sOldFile), "plugins/antiflood.smx");
	
		/**
		Check if plugins/antiflood.smx exists, and if not, ignore
		*/
		if(!FileExists(sOldFile))
		{
			return;
		}
	
		/** 
		Check if plugins/disabled/antiflood.smx already exists, and if so, delete it
		*/
		if(FileExists(sNewFile))
		{
			DeleteFile(sNewFile);
		}
	
		/**
		Unload plugins/antiflood.smx and move it to plugins/disabled/antiflood.smx
		*/
		LogAction(0, -1, "Detected the plugin Antiflood");
		LogAction(0, -1, "Antiflood plugin conflicts with Simple Chat Colors");
		LogAction(0, -1, "Unloading plugin and disabling Antiflood plugin");
		ServerCommand("sm plugins unload antiflood");
		RenameFile(sNewFile, sOldFile);
	}
	
	/*
	Register the autoupdater if they have it
	*/
	if(LibraryExists("pluginautoupdate")) 
	{ 
		AutoUpdate_AddPlugin("sm-simple-plugins.googlecode.com", "/svn/branches/simplechatcolors.xml", PLUGIN_VERSION); 
	}
}

public OnPluginEnd()
{
	/*
	De-register the autoupdater if they have it
	*/
	if(LibraryExists("pluginautoupdate")) 
	{ 
		AutoUpdate_RemovePlugin(); 
	}
}

public OnConfigsExecuted()
{
	GetConVarString(g_Cvar_hClanFlag, g_sClanFlags, sizeof(g_sClanFlags));
	g_bDebug = GetConVarBool(g_Cvar_hDebug);
	g_bTriggerBackup = GetConVarBool(g_Cvar_hTriggerBackup);
	g_bClanChatEnabled = GetConVarBool(g_Cvar_hClanChatEnabled);
	g_eDeadChatMode = e_DeadChat:GetConVarInt(g_Cvar_hDeadChat);
	g_bChatFilterEnabled = GetConVarBool(g_Cvar_hChatFilterEnabled);
	g_bAutoResponseEnabled = GetConVarBool(g_Cvar_hAutoResponseEnabled);
	g_bChatColorTagsEnabled = GetConVarBool(g_Cvar_hChatColorTagsEnabled);
	ReloadConfigFiles();
}

public OnClientPostAdminCheck(client)
{
	
	/**
	Check the client to see if they have a color
	*/
	CheckPlayer(client);
}

public OnClientDisconnect(client)
{
	g_aPlayerIndex[client] = -1;
	g_aPlayerClanMember[client] = false;
	g_aPlayerGagged[client] = false;
}

public OnMapStart()
{
	GetTeams();
}

/**
Adjust the settings if a convar was changed
*/
public ConVarSettingsChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (convar == g_Cvar_hDebug)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bDebug = true;
		}
		else
		{
			g_bDebug = false;
		}
	}
	else if (convar == g_Cvar_hTriggerBackup)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bTriggerBackup = true;
		}
		else
		{
			g_bTriggerBackup = false;
		}
	}
	else if (convar == g_Cvar_hClanChatEnabled)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bClanChatEnabled = true;
		}
		else
		{
			g_bClanChatEnabled = false;
		}
	}
	else if (convar == g_Cvar_hDeadChat)
	{
		g_eDeadChatMode = e_DeadChat:StringToInt(newValue);
	}
	else if (convar == g_Cvar_hChatFilterEnabled)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bChatFilterEnabled = true;
		}
		else
		{
			g_bChatFilterEnabled = false;
		}
	}
	else if (convar == g_Cvar_hAutoResponseEnabled)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bAutoResponseEnabled = true;
		}
		else
		{
			g_bAutoResponseEnabled = false;
		}
	}
	else if (convar == g_Cvar_hChatColorTagsEnabled)
	{
		if (StringToInt(newValue) == 1)
		{
			g_bChatColorTagsEnabled = true;
		}
		else
		{
			g_bChatColorTagsEnabled = false;
		}
	}
}

/**
Commands
*/

public Action:Command_Say(client, args)
{
	
	/**
	Make sure its not the server or a chat trigger or if the player is gagged
	*/
	if (client == 0 || IsChatTrigger() || g_aPlayerGagged[client])
	{
		return Plugin_Continue;
	}
	
	/**
	Get the message
	*/
	decl	String:sMessage[256];
	GetCmdArgString(sMessage, sizeof(sMessage));
	
	/**
	Process the message
	*/
	return ProcessMessage(client, false, sMessage, sizeof(sMessage));
}

public Action:Command_SayTeam(client, args)
{
	
	/**
	Make sure its not the server or a chat trigger or if the player is gagged
	*/
	if (client == 0 || IsChatTrigger() || g_aPlayerGagged[client])
	{
		return Plugin_Continue;
	}
	
	/**
	Check the flood tokens
	**/
	if (g_FloodTokens[client] >= 3)
	{
		return Plugin_Handled;
	}
	
	/**
	Get the message
	*/
	decl	String:sMessage[256];
	GetCmdArgString(sMessage, sizeof(sMessage));
	
	/**
	Process the message
	*/
	return ProcessMessage(client, true, sMessage, sizeof(sMessage));
}

public Action:Command_Reload(client, args)
{
	ReloadConfigFiles();	
	return Plugin_Handled;
}

public Action:Command_PrintColors(client, args)
{
	CPrintToChat(client, "{default}default");
	CPrintToChat(client, "{green}green");
	CPrintToChat(client, "{lightgreen}lightgreen");
	CPrintToChat(client, "{red}red");
	CPrintToChat(client, "{blue}blue");
	CPrintToChatEx(client, client, "{teamcolor}teamcolor");
	CPrintToChat(client, "{olive}olive");
	return Plugin_Handled;
}


/**
Below are functions from the basechat.sp plugin.  
All credit goes to SourceMod dev team
*/
public Action:Command_SMgag(client, const String:command[], argc)
{
	if (argc < 1)
	{
		return Plugin_Continue;
	}
	
	decl String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client, 
			target_list, 
			MAXPLAYERS, 
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		return Plugin_Continue;
	}

	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];
		
		g_aPlayerGagged[target] = true;
	}
	
	return Plugin_Continue;
}

public Action:Command_SMungag(client, const String:command[], argc)
{
	if (argc < 1)
	{
		return Plugin_Continue;
	}
	
	decl String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client, 
			target_list, 
			MAXPLAYERS, 
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		return Plugin_Continue;
	}

	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];
		
		g_aPlayerGagged[target] = false;
	}
	
	return Plugin_Continue;
}

public Action:Command_SMsilence(client, const String:command[], argc)
{
	if (argc < 1)
	{
		return Plugin_Continue;
	}
	
	decl String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client, 
			target_list, 
			MAXPLAYERS, 
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		return Plugin_Continue;
	}

	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];

		g_aPlayerGagged[target] = true;
	}
	
	return Plugin_Continue;
}

public Action:Command_SMunsilence(client, const String:command[], argc)
{
	if (argc < 1)
	{
		return Plugin_Continue;
	}
	
	decl String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client, 
			target_list, 
			MAXPLAYERS, 
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		return Plugin_Continue;
	}

	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];
		
		g_aPlayerGagged[target] = false;
	}
	
	return Plugin_Continue;
}


/**
Stock Functions
*/
stock CheckPlayer(client)
{
	new String:sFlags[15];
	new String:sClientSteamID[64];
	new bool:bDebug_FoundBySteamID = false;
	new iIndex = -1;
	
	/**
	Look for a steamid first
	*/
	GetClientAuthString(client, sClientSteamID, sizeof(sClientSteamID));
	iIndex = FindStringInArray(g_aSettings[hGroupName], sClientSteamID);	
	if (iIndex != -1)
	{
		g_aPlayerIndex[client] = iIndex;
		bDebug_FoundBySteamID = true;
	}
	
	/**
	Didn't find one, check for flags
	*/
	else
	{
		
		/**
		Search for flag in groups
		*/
		for (new i = 0; i < g_iArraySize; i++)
		{
			decl String:sGroupName[64];
			GetArrayString(g_aSettings[hGroupName], i, sGroupName, sizeof(sGroupName));
			GetArrayString(g_aSettings[hGroupFlag], i, sFlags, sizeof(sFlags));
			new iGroupFlags = ReadFlagString(sFlags);
			if (g_bDebug)
			{
				PrintToChatAll("Checking %N in %s", client, sGroupName);
				PrintToChatAll("Flag string is %s", sFlags);
				PrintToChatAll("Flag bits are %i", iGroupFlags);
			}
			if (iGroupFlags != 0 && CheckCommandAccess(client, "scc_colors", iGroupFlags, true))
			{
				if (g_bDebug)
				{
					PrintToChatAll("Passed access check");
				}
				g_aPlayerIndex[client] = i;
				iIndex = i;
				break;
			}
		}
		
		/**
		Check to see if flag was found
		*/
		if (iIndex == -1)
		{
			
			/**
			No flag, look for an "everyone" group
			*/
			iIndex = FindStringInArray(g_aSettings[hGroupName], "everyone");
			if (iIndex != -1)
			{
				g_aPlayerIndex[client] = iIndex;
			}
		}
	}
	
	new ibFlags = ReadFlagString(g_sClanFlags);
	if (ibFlags != 0 && CheckCommandAccess(client, "scc_clanflag", ibFlags, true))
	{
		g_aPlayerClanMember[client] = true;
	}
	
	/**
	Process debug messages
	*/
	if (g_bDebug)
	{
		if (g_aPlayerIndex[client] == -1)
		{
			PrintToConsole(client, "[SCC] Client %N was NOT found in colors config", client);
		}
		else
		{
			new String:sGroupName[256];
			GetArrayString(g_aSettings[hGroupName], g_aPlayerIndex[client], sGroupName, sizeof(sGroupName));
			PrintToConsole(client, "[SCC] Client %N was found in colors config", client);
			if (bDebug_FoundBySteamID)
			{
				PrintToConsole(client, "[SCC] Found steamid: %s in config file", sGroupName);
			}
			else
			{
				PrintToConsole(client, "[SCC] Found in group: %s in config file", sGroupName);
			}
		}
		
		if (g_aPlayerClanMember[client])
		{
			PrintToConsole(client, "[SCC] Client %N has the clan flag(s) %s", client, g_sClanFlags);
		}
		else
		{
			PrintToConsole(client, "[SCC] Client %N does NOT have the clan flag(s) %s", client, g_sClanFlags);
		}
	}
}

stock bool:IsStringBlank(const String:input[])
{
	new len = strlen(input);
	for (new i=0; i<len; i++)
	{
		if (!IsCharSpace(input[i]))
		{
			return false;
		}
	}
	return true;
}

stock Action:ProcessMessage(client, bool:teamchat, String:message[], maxlength)
{
	
	new e_ChatType:eChatMode;
	new bool:bSaidBadWord = false;
	
	/**
	Keep the original message
	*/
	new String:sOriginalMessage[128];
	strcopy(sOriginalMessage, sizeof(sOriginalMessage), message);
	
	/**
	Because we are dealing with a chat message, lets take out all the %'s
	*/
	ReplaceString(message, maxlength, CHAR_PERCENT, CHAR_NULL);
	
	/**
	Get the chat message and strip it down.
	*/
	StripQuotes(message);
	TrimString(message);
	
	/**
	Make sure it's not blank
	*/
	if (IsStringBlank(message))
	{
		return Plugin_Stop;
	}
	
	/**
	Bug out if they are using the admin chat symbol (admin chat)
	*/
	if (message[0] == CHAT_SYMBOL_ADMIN)
	{
		return Plugin_Continue;
	}
	
	/**
	If we are using the trigger backup, then bug out on the triggers
	*/
	if (g_bTriggerBackup && (message[0] == CHAT_TRIGGER_PUBLIC || message[0] == CHAT_TRIGGER_PRIVATE))
	{
		return Plugin_Continue;
	}
	
	/**
	Make sure it's not a override string
	*/
	if (FindStringInArray(g_aSettings[hOverrides], message) != -1)
	{
		return Plugin_Continue;
	}
	
	/**
	See if they are using clan chat
	*/
	if (message[0] == CHAT_SYMBOL_CLAN && g_aPlayerClanMember[client])
	{
		
		/**
		They are, see if enabled
		*/
		if (!g_bClanChatEnabled)
		{
			PrintToChat(client, "%t", "Clan chat is disabled!");
			return Plugin_Stop;
		}
		
		/**
		Set the mode
		*/
		eChatMode = ChatType_Clan;
		
		/**
		Strip the clan chat symbol
		*/
		decl String:sBuffer[512];
		strcopy(sBuffer, maxlength, message[1]);
		strcopy(message, maxlength, sBuffer);
		
		/**
		Make sure it's not blank
		*/
		if (IsStringBlank(message))
		{
			return Plugin_Stop;
		}
	}
	
	/**
	Check to see if auto response is enabled and display any response
	*/
	if (g_bAutoResponseEnabled)
	{
		
		new iArrayResponseSize = GetArraySize(g_aResponses[hPhrase]);
		new ResponseIndex = -1;
		
		for (new i = 0; i < iArrayResponseSize; i++)
		{
			new String:sMatchBuffer[512];
			GetArrayString(g_aResponses[hMatch], i, sMatchBuffer, sizeof(sMatchBuffer));
			if (StrEqual("exact", sMatchBuffer, false))
			{
				new String:sResponseBuffer[512];
				GetArrayString(g_aResponses[hPhrase], i, sResponseBuffer, sizeof(sResponseBuffer));
				if (StrEqual(message, sResponseBuffer, false))
				{
					ResponseIndex = i;
					break;
				}
			}
		}
		
		if (ResponseIndex == -1)
		{
			for (new x = 0; x < iArrayResponseSize; x++)
			{
				new String:sMatchBuffer[512];
				GetArrayString(g_aResponses[hMatch], x, sMatchBuffer, sizeof(sMatchBuffer));
				if (StrEqual("contains", sMatchBuffer, false))
				{
					new String:sResponseBuffer[512];
					GetArrayString(g_aResponses[hPhrase], x, sResponseBuffer, sizeof(sResponseBuffer));
					if (StrContains(message, sResponseBuffer, false) != -1)
					{
						ResponseIndex = x;
						break;
					}
				}
			}
		}
		
		if (ResponseIndex >= 0)
		{
			
			/**
			Delay the response 0.5 seconds to appear after chat
			*/
			
			if (g_bDebug)
			{
				new String:sPhraseBuffer[512];
				new String:sResponseBuffer[512];
				GetArrayString(g_aResponses[hPhrase], ResponseIndex, sPhraseBuffer, sizeof(sPhraseBuffer));
				GetArrayString(g_aResponses[hResponse], ResponseIndex, sResponseBuffer, sizeof(sResponseBuffer));
				PrintToChat(client, "Found a response on phrase: \n %s", sPhraseBuffer);
				PrintToChat(client, "Response is: \n %s", sResponseBuffer);
			}
			new Handle:hPack;
			CreateDataTimer(0.5, Timer_ChatResponse, hPack, TIMER_FLAG_NO_MAPCHANGE);
			WritePackCell(hPack, ResponseIndex);
			WritePackCell(hPack, teamchat);
			WritePackCell(hPack, client);
		}
	}
	
	/**
	Check to see if the chat filter is enabled
	*/
	if (g_bChatFilterEnabled)
	{
		
		/**
		Check to see if they said a bad word
		*/
		if (SaidBadWord(client, message, maxlength))
		{
			
			/**
			Inform them that there message was filtered.
			*/
			CPrintToChat(client, "%t", "Filter Message");
			bSaidBadWord = true;
		}
	}
	
	/**
	Set the Chatmode
	*/
	if (eChatMode != ChatType_Clan)
	{
		if (GetClientTeam(client) == g_aCurrentTeams[Spectator])
		{
			if (teamchat)
			{
				eChatMode = ChatType_SpectatorTeam;
			}
			else
			{
				eChatMode = ChatType_SpectatorAll;
			}
		}
		else if (teamchat)
		{
			eChatMode = ChatType_Team;
		}
		else
		{
			eChatMode = ChatType_All;
		}
	}
	
	/**
	Make sure the client has a color assigned
	*/
	if (g_aPlayerIndex[client] != -1)
	{
		
		/**
		Check if color tags in chat is enabled and if not remove the tags
		*/
		if (!g_bChatColorTagsEnabled)
		{
			CRemoveTags(message, maxlength);
		}
		
		
		/**
		Format the message.
		*/
		decl String:sChatMsg[512];
		if (eChatMode == ChatType_Clan)
		{
			FormatClanMessage(client, message, sChatMsg, sizeof(sChatMsg));
		}
		else
		{
			FormatChatMessage(client, GetClientTeam(client), IsPlayerAlive(client), teamchat, g_aPlayerIndex[client], message, sChatMsg, sizeof(sChatMsg));
		}
		
		/**
		Send the message.
		*/
		SendChatMessage(client, teamchat, sChatMsg, g_eDeadChatMode, eChatMode);
		
		/**
		We are done, bug out, and stop the original chat message, and send chat event
		*/
		SendChatEvent(client, sOriginalMessage);
		return Plugin_Stop;
	} 
	else if (bSaidBadWord)
	{
		
		/**
		The shouldn't be able to use color tags, strip any tags found from the message
		*/
		CRemoveTags(message, maxlength);
		
		/**
		They said a bad word but do not have a color assigned, still filter the message
		*/
		decl String:sChatMsg[512];
		FormatChatMessage(client, GetClientTeam(client), IsPlayerAlive(client), teamchat, g_aPlayerIndex[client], message, sChatMsg, sizeof(sChatMsg));
		
		/**
		Send the message
		*/
		SendChatMessage(client, teamchat, sChatMsg, g_eDeadChatMode, eChatMode);
		
		/**
		We are done, bug out, and stop the original chat message, and send chat event
		*/
		SendChatEvent(client, sOriginalMessage);
		return Plugin_Stop;
	}
	
	/**
	All else failed, bug out.
	*/
	return Plugin_Continue;
}

stock FormatChatMessage(client, team, bool:alive, bool:teamchat, index, const String:message[], String:chatmsg[], maxlength)
{
	decl	String:sDead[10],
				String:sTeam[15];

	
	if (teamchat)
	{
		if ((g_CurrentMod == GameType_L4D || g_CurrentMod == GameType_L4D2) && team == g_aCurrentTeams[Team1])
		{
			Format(sTeam, sizeof(sTeam), "%t ", "Survivor");
		}
		else if ((g_CurrentMod == GameType_L4D || g_CurrentMod == GameType_L4D2) && team == g_aCurrentTeams[Team2])
		{
			Format(sTeam, sizeof(sTeam), "%t ", "Infected");
		}
		else if (team != g_aCurrentTeams[Spectator])
		{
			Format(sTeam, sizeof(sTeam), "%t ", "TEAM");
		}
		else
		{
			Format(sTeam, sizeof(sTeam), "%t ", "Spectator");
		}
	}
	else
	{
		if (team != g_aCurrentTeams[Spectator])
		{
			Format(sTeam, sizeof(sTeam), "");
		}
		else
		{
			Format(sTeam, sizeof(sTeam), "%t ", "SPEC");
		}
	}
	
	if ((g_CurrentMod != GameType_L4D && g_CurrentMod != GameType_L4D2) && team != g_aCurrentTeams[Spectator] && !alive)
	{
		Format(sDead, sizeof(sDead), "%t ", "DEAD");
	}
	else
	{
		Format(sDead, sizeof(sDead), "");
	}
	
	new String:sTagText[24];
	new String:sTagColor[15];
	new String:sNameColor[15];
	new String:sTextColor[15];
	
	/**
	Make sure we have a valid index or use default colors
	**/
	if (index != -1)
	{
		GetArrayString(g_aSettings[hTagText], index, sTagText, sizeof(sTagText));
		GetArrayString(g_aSettings[hTagColor], index, sTagColor, sizeof(sTagColor));	
		GetArrayString(g_aSettings[hNameColor], index, sNameColor, sizeof(sNameColor));
		GetArrayString(g_aSettings[hTextColor], index, sTextColor, sizeof(sTextColor));
	}
	else
	{
		Format(sTagText, sizeof(sTagText), "%s", "");
		Format(sTagColor, sizeof(sTagColor), "%s", "");
		Format(sNameColor, sizeof(sNameColor), "%s", "{teamcolor}");
		Format(sTextColor, sizeof(sTextColor), "%s", "{default}");
	}
	
	decl String:sClientName[64];
	GetClientName(client, sClientName, sizeof(sClientName));
	
	/**
	Remove any color tags from name
	**/
	CRemoveTags(sClientName, sizeof(sClientName));
	
	Format(chatmsg, maxlength, "{default}%s%s%s%s%s%s {default}:  %s%s", sDead, sTeam, sTagColor, sTagText, sNameColor, sClientName, sTextColor, message);
}

stock FormatClanMessage(client, const String:message[], String:chatmsg[], maxlength)
{
	decl String:sClientName[64];
	decl String:sClanTag[64];
	GetClientName(client, sClientName, sizeof(sClientName));
	Format(sClanTag, sizeof(sClanTag), "%t", "Clan");
	
	/**
	Remove any color tags from name
	**/
	CRemoveTags(sClientName, sizeof(sClientName));
	
	Format(chatmsg, maxlength, "{green}%s %s {default}:  %s", sClanTag, sClientName, message);
}

stock SendChatMessage(client, bool:teamchat, const String:message[], e_DeadChat:mode, e_ChatType:type)
{

	new bool:bSenderAlive = IsPlayerAlive(client);
	new bool:bHasTeamColorTag = (StrContains(message, "{teamcolor}", false) != -1 ? true : false);
	switch (mode)
	{
		case DeadChat_Restricted:
		{
			if (!bSenderAlive && GetClientTeam(client) != g_aCurrentTeams[Spectator])
			{
				PrintToChat(client, "%t", "The dead don't talk!");
			}
			else
			{
				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsValidClient(i) && IsPlayerAlive(i) 	&& CanChatToEachOther(client, i, type))
					{
						if (g_bDebug)
						{
							PrintToChat(client, "Sending Following Message to colors.inc file: \n %s", message);
						}
						if (bHasTeamColorTag)
						{
							CPrintToChatEx(i, client, "%s", message);
						}
						else
						{
							CPrintToChat(i, "%s", message);
						}
					}
				}
			}
		}
		case DeadChat_Normal:
		{
			for (new i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) 
					&& (bSenderAlive || (!bSenderAlive && !IsPlayerAlive(i)))
					&& CanChatToEachOther(client, i, type))
				{
					if (g_bDebug)
					{
						PrintToChat(client, "Sending Following Message to colors.inc file: \n %s", message);
					}
					if (bHasTeamColorTag)
					{
						CPrintToChatEx(i, client, "%s", message);
					}
					else
					{
						CPrintToChat(i, "%s", message);
					}
				}
			}
		}
		case DeadChat_UnRestricted:
		{
			for (new i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) && CanChatToEachOther(client, i, type))
				{
					if (g_bDebug)
					{
						PrintToChat(client, "Sending Following Message to colors.inc file: \n %s", message);
					}
					if (bHasTeamColorTag)
					{
						CPrintToChatEx(i, client, "%s", message);
					}
					else
					{
						CPrintToChat(i, "%s", message);
					}
				}
			}
		}
	}
}

stock bool:CanChatToEachOther(client, target, e_ChatType:type)
{
	switch (type)
	{
		case ChatType_All:
		{
			return true;
		}
		case ChatType_Team:
		{
			if (GetClientTeam(client) == GetClientTeam(target))
			{
				return true;
			}
		}
		case ChatType_Clan:
		{
			if (g_aPlayerClanMember[client] && g_aPlayerClanMember[target])
			{
				return true;
			}
		}
		case ChatType_SpectatorAll:
		{
			return true;
		}
		case ChatType_SpectatorTeam:
		{
			if (GetClientTeam(client) == g_aCurrentTeams[Spectator] 
			&& GetClientTeam(target) == g_aCurrentTeams[Spectator])
			{
				return true;
			}
		}
	}
	return false;
}

stock bool:SaidBadWord(client, String:message[], maxlength)
{
	
	new index = 0;
	new iArrayBannedSize = GetArraySize(g_aBadWords);
	new bool:bBad = false;
	new String:sWords[64][128];
	
	/**
	Strip the quotes and explode the string into words (limit 64 words of 128 chars in length)
	*/
	StripQuotes(message);
	ExplodeString(message, " ", sWords, sizeof(sWords), sizeof(sWords[]));
	
	/**
	Loop through all the words
	*/
	do
	{

		TrimString(sWords[index]);
		
		if (g_bDebug)
		{
			PrintToChat(client, "Checking word: %s", sWords[index]);
		}
		
		/**
		Check to see if the word is in the banned word list
		*/
		new BannedIndex = -1;
		
		for (new i = 0; i < iArrayBannedSize; i++)
		{
			new String:sBuffer[512];
			GetArrayString(g_aBadWords, i, sBuffer, sizeof(sBuffer));
			if (StrContains(sWords[index], sBuffer, false) != -1)
			{
				BannedIndex = i;
				break;
			}
		}
		
		if (BannedIndex != -1)
		{
			
			/**
			It is, create the filter
			*/
			FilterWord(sWords[index], sizeof(sWords[]));
			bBad = true;
		}
		
		index++;
	} while !IsStringBlank(sWords[index]);
	
	/**
	Rebuild the message and return the result
	*/
	ImplodeStrings(sWords, sizeof(sWords), " ", message, maxlength);
	TrimString(message);
	return bBad;
}

stock FilterWord(String:word[], maxlength)
{
	new String:sFilter[128];
	for (new x = 0; x < strlen(word); x++)
	{
		decl String:sBuffer[128];
		strcopy(sBuffer, sizeof(sBuffer), sFilter);
		Format(sFilter, sizeof(sFilter), "%s%s", CHAR_FILTER, sBuffer);
	}
	strcopy(word, maxlength, sFilter);
}

public Action:Timer_ChatResponse(Handle:timer, any:pack)
{
	ResetPack(pack);
	new ResponseIndex = ReadPackCell(pack),
			teamchat 			= ReadPackCell(pack),
			client				= ReadPackCell(pack);
	
	new String:sResponse[512];
			
	GetArrayString(g_aResponses[hResponse], ResponseIndex, sResponse, sizeof(sResponse));
	if (StrContains(sResponse, "{teamcolor}", false))
	{
		if (teamchat)
		{
			for (new i = 0; i < MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					CPrintToChatEx(i, client, sResponse);
				}
			}
		}
		else
		{
			CPrintToChatAllEx(client, sResponse);
		}
	}
	else
	{
		if (teamchat)
		{
			for (new i = 0; i < MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					CPrintToChat(i, sResponse);
				}
			}
		}
		else
		{
			CPrintToChatAll(sResponse);
		}
	}
	
	return Plugin_Handled;
}

stock SendChatEvent(client, const String:message[])
{
	new userid = GetClientUserId(client);
	new Handle:event = CreateEvent("player_say");
	SetEventInt(event, "userid", userid);
	SetEventString(event, "text", message);
	FireEvent(event);
}

/**
Load the bad words
*/
stock LoadBadWords()
{
	new String:sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/simple-chatfilter.cfg");
	if (!FileExists(sConfigFile)) 
	{
		/**
		Config file doesn't exists, stop the plugin
		*/
		LogError("[SCF] Simple Chat Colors is not running! Could not find file %s", sConfigFile);
		SetFailState("Could not find file %s", sConfigFile);
	}
	else
	{
		new Handle:hFile = OpenFile(sConfigFile, "r");
		new String:sBadWord[128];
		do
		{
			ReadFileLine(hFile, sBadWord, sizeof(sBadWord));
			TrimString(sBadWord);
			if (sBadWord[0] == '\0' || sBadWord[0] == ';' || (sBadWord[0] == '/' && sBadWord[1] == '/'))
			{
				continue;
			}
			PushArrayString(g_aBadWords, sBadWord);
		} while (!IsEndOfFile(hFile));
		CloseHandle(hFile);
	}
}

/**
Parse the config file
*/
stock ProcessConfigFile(const String:file[])
{
	new String:sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), file);
	if (!FileExists(sConfigFile)) 
	{
		/**
		Config file doesn't exists, stop the plugin
		*/
		LogError("[SCC] Simple Chat Colors is not running! Could not find file %s", sConfigFile);
		SetFailState("Could not find file %s", sConfigFile);
	}
	else if (!ParseConfigFile(sConfigFile))
	{
		/**
		Config file doesn't exists, stop the plugin
		*/
		LogError("[SCC] Simple Chat Colors is not running! Failed to parse %s", sConfigFile);
		SetFailState("Parse error on file %s", sConfigFile);
	}
}

stock ReloadConfigFiles()
{
	
	/**
	Clear the arrays
	*/
	for (new e_Settings:i; i < e_Settings:sizeof(g_aSettings); i++)
	{
		ClearArray(g_aSettings[i]);
	}
	
	for (new e_AutoResponses:i; i < e_AutoResponses:sizeof(g_aResponses); i++)
	{
		ClearArray(g_aResponses[i]);
	}
	
	ClearArray(g_aBadWords);
	
	/**
	Process the different config files
	*/
	ProcessConfigFile("configs/simple-chatcolors.cfg");
	ProcessConfigFile("configs/simple-chatresponses.cfg");
	g_iArraySize = GetArraySize(g_aSettings[hGroupName]) - 1;
	
	LoadBadWords();
	
	
	/**
	Recheck all the online players for assigned colors
	*/
	for (new index = 1; index <= MaxClients; index++)
	{
		if (IsClientConnected(index) && IsClientInGame(index))
		{
			CheckPlayer(index);
		}
	}
}

bool:ParseConfigFile(const String:file[]) 
{

	new Handle:hParser = SMC_CreateParser();
	new String:error[128];
	new line = 0;
	new col = 0;
	
	if (StrEqual(file, "addons/sourcemod/configs/simple-chatresponses.cfg", false))
	{
		
		/**
		Define the response config functions
		*/
		SMC_SetReaders(hParser, Config_Responses_NewSection, Config_Responses_KeyValue, Config_Responses_EndSection);
		SMC_SetParseEnd(hParser, Config_End);
	}
	else 
	{

		/**
		Define the color config functions
		*/
		SMC_SetReaders(hParser, Config_Colors_NewSection, Config_Colors_KeyValue, Config_Colors_EndSection);
		SMC_SetParseEnd(hParser, Config_End);
	}
	
	/**
	Parse the file and get the result
	*/
	new SMCError:result = SMC_ParseFile(hParser, file, line, col);
	CloseHandle(hParser);

	if (result != SMCError_Okay) 
	{
		SMC_GetErrorString(result, error, sizeof(error));
		LogError("%s on line %d, col %d of %s", error, line, col, file);
	}
	
	return (result == SMCError_Okay);
}

public SMCResult:Config_Responses_NewSection(Handle:parser, const String:section[], bool:quotes) 
{
	if (StrEqual(section, "auto_responses"))
	{
		return SMCParse_Continue;
	}
	if (g_bDebug)
	{
		PrintToChatAll("Storing Phrase: %s", section);
	}
	PushArrayString(g_aResponses[hPhrase], section);
	return SMCParse_Continue;
}

public SMCResult:Config_Responses_KeyValue(Handle:parser, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	
	if(StrEqual(key, "text", false))
	{
		PushArrayString(g_aResponses[hResponse], value);
		if (g_bDebug)
		{
			PrintToChatAll("Storing Response: %s", value);
		}
	}
	
	if(StrEqual(key, "match", false))
	{
		PushArrayString(g_aResponses[hMatch], value);
		if (g_bDebug)
		{
			PrintToChatAll("Match Type: %s", value);
		}
	}
	
	return SMCParse_Continue;
}

public SMCResult:Config_Responses_EndSection(Handle:parser) 
{
	return SMCParse_Continue;
}

public SMCResult:Config_Colors_NewSection(Handle:parser, const String:section[], bool:quotes) 
{
	if (StrEqual(section, "admin_colors"))
	{
		return SMCParse_Continue;
	}
	else if (StrEqual(section, "Overrides"))
	{
		g_bOverrideSection = true;
		if (g_bDebug)
		{
			PrintToChatAll("In override");
		}
	}
	else
	{
		g_bOverrideSection = false;
		if (g_bDebug)
		{
			PrintToChatAll("In section: %s", section);
		}
	}
	PushArrayString(g_aSettings[hGroupName], section);
	return SMCParse_Continue;
}

public SMCResult:Config_Colors_KeyValue(Handle:parser, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	if (g_bOverrideSection)
	{
		PushArrayString(g_aSettings[hOverrides], key);
		if (g_bDebug)
		{
			PrintToChatAll("Storing override: %s", key);
		}
	}
	else
	{
		if(StrEqual(key, "flag", false))
		{
			PushArrayString(g_aSettings[hGroupFlag], value);
		}
		else if(StrEqual(key, "tag", false))
		{
			PushArrayString(g_aSettings[hTagText], value);
		}
		else if(StrEqual(key, "tagcolor", false))
		{
			PushArrayString(g_aSettings[hTagColor], value);
		}
		else if(StrEqual(key, "namecolor", false))
		{
			PushArrayString(g_aSettings[hNameColor], value);
		}
		else if(StrEqual(key, "textcolor", false))
		{
			PushArrayString(g_aSettings[hTextColor], value);
		}
		if (g_bDebug)
		{
			PrintToChatAll("Storing %s: %s", key,value);
		}
	}
	return SMCParse_Continue;
}

public SMCResult:Config_Colors_EndSection(Handle:parser) 
{
	if (g_bOverrideSection)
	{
		g_bOverrideSection = false;
	}
	if (g_bDebug)
	{
		PrintToChatAll("Leaving section");
	}
	return SMCParse_Continue;
}

public Config_End(Handle:parser, bool:halted, bool:failed) 
{
	if (failed)
	{
		SetFailState("Plugin configuration error");
	}
}

