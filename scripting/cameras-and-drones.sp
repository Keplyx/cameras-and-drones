/*
*   This file is part of Cameras and Drones.
*   Copyright (C) 2017  Keplyx
*
*   This program is free software: you can redistribute it and/or modify
*   it under the terms of the GNU General Public License as published by
*   the Free Software Foundation, either version 3 of the License, or
*   (at your option) any later version.
*
*   This program is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*
*   You should have received a copy of the GNU General Public License
*   along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#include <sourcemod>
#include <csgocolors>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <usermessages>
#include <csgocolors>
#include <camerasanddrones>

#undef REQUIRE_PLUGIN
#include <tacticalshield>

#pragma newdecls required;

#include "cameras-and-drones/cameramenus.sp"
#include "cameras-and-drones/dronemenus.sp"
#include "cameras-and-drones/init.sp"

/*  New in this version
*	Fixed errors when exiting/entering gear
*
*/

#define VERSION "1.1.7"
#define AUTHOR "Keplyx"
#define PLUGIN_NAME "Cameras and Drones"

#define HIDEHUD_WEAPONSELECTION ( 1<<0 ) // Hide ammo count & weapon selection
#define FFADE_STAYOUT       0x0008        // ignores the duration, stays faded out until new ScreenFade message received
#define FFADE_PURGE         0x0010        // Purges all other fades, replacing them with this one

#define customModelsPath "gamedata/cameras-and-drones/custom_models.txt"

#define droneHTML "<font color='#f6c65e'>Drone</font>"
#define camHTML "<font color='#9e5ef6'>Camera</font>"

bool lateload;

int clientsViewmodels[MAXPLAYERS + 1];

char gearOverlay[] = "vgui/screens/vgui_overlay";

char cantBuyGearSound[] = "ui/weapon_cant_buy.wav";
char getGearSound[] = "items/itempickup.wav";

bool canDisplayThrowWarning[MAXPLAYERS + 1];
bool canDroneJump[MAXPLAYERS + 1];
bool isDroneJumping[MAXPLAYERS + 1];

int collisionOffsets;

int availabletGear[MAXPLAYERS + 1];
bool canBuy[MAXPLAYERS + 1];
int playerGearOverride[MAXPLAYERS + 1];
float buyTime;


/************************************************************************************************************
*											INIT
************************************************************************************************************/

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = AUTHOR,
	description = "CSGO plugin adding cameras and drones to the game.",
	version = VERSION,
	url = "https://github.com/Keplyx/cameras-and-drones"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("BuyPlayerGear", Native_BuyPlayerGear);
	CreateNative("OverridePlayerGear", Native_OverridePlayerGear);
	CreateNative("IsPlayerInGear", Native_IsPlayerInGear);
	RegPluginLibrary("cameras-and-drones");
	lateload = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	AddCommandListener(CommandDrop, "drop");
	AddCommandListener(CommandJoinTeam, "jointeam");
	
	CreateConVars(VERSION);
	RegisterCommands();
	ReadCustomModelsFile();
	
	collisionOffsets = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	
	InitVars(false);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
			OnClientPostAdminCheck(i);
	}
	
	if (lateload)
		ServerCommand("mp_restartgame 1");
}

public void OnAllPluginsLoaded()
{
	dTacticalShield = LibraryExists("tacticalshield");
	cTacticalShield = dTacticalShield;
}
 
public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "tacticalshield"))
	{
		dTacticalShield = false;
		cTacticalShield = dTacticalShield;
	}
}
 
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "tacticalshield"))
	{
		dTacticalShield = true;
		cTacticalShield = dTacticalShield;
	}
}

public int GetCollOffset()
{
	return collisionOffsets;
}

/**
* Precache models and sounds when the map starts.
*/
public void OnMapStart()
{
	PrecacheModel(inCamModel, true);
	PrecacheModel(defaultDronePhysModel, true);
	PrecacheModel(defaultCamPhysModel, true);
	
	PrecacheSound(cantBuyGearSound, true);
	PrecacheSound(getGearSound, true);
	PrecacheSound(droneSound, true);
	PrecacheSound(droneJumpSound, true);
	PrecacheSound(openDroneSound, true);
	PrecacheSound(destroyDroneSound, true);
	PrecacheSound(openCamSound, true);
	PrecacheSound(destroyCamSound, true);
}

/**
* Hook player weapons and creates a timer to display the welcome message.
*
* @param client_index    index of the client disconnecting.
*/
public void OnClientPostAdminCheck(int client_index)
{
	SDKHook(client_index, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	SDKHook(client_index, SDKHook_PostThink, Hook_PostThinkPlayer);
	int ref = EntIndexToEntRef(client_index);
	CreateTimer(3.0, Timer_WelcomeMessage, ref);
}

/**
* Resets the player on disconect to prevent problems when new player with same index connects.
*
* @param client_index    index of the client disconnecting.
*/
public void OnClientDisconnect(int client_index)
{
	ResetPlayer(client_index);
	SDKUnhook(client_index, SDKHook_PostThink, Hook_PostThinkPlayer);
	SDKUnhook(client_index, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
}

/**
* Resets variables associated to the given player.
*
* @param client_index    index of the client to reset.
*/
public void ResetPlayer(int client_index)
{
	if (dronesList != null)
	{
		for (int i = 0; i < dronesList.Length; i++)
		{
			if (dronesOwnerList.Get(i) == client_index)
				DestroyDrone(dronesList.Get(i), true);
		}
	}
	if (camerasList != null)
	{
		for (int i = 0; i < camerasList.Length; i++)
		{
			if (camOwnersList.Get(i) == client_index)
				DestroyCamera(camerasList.Get(i), true);
		}
	}
	
	availabletGear[client_index] = 0;
	canDisplayThrowWarning[client_index] = true;
	canDroneJump[client_index] = true;
	isDroneJumping[client_index] = false;
	playerGearOverride[client_index] = 0;
	canBuy[client_index] = true;
}

/**
* Initializes variables with default values.
*
*/
public void InitVars(bool isNewRound)
{
	camerasList = new ArrayList();
	camerasModelList = new ArrayList();
	camOwnersList = new ArrayList();
	dronesList = new ArrayList();
	dronesModelList = new ArrayList();
	dronesOwnerList = new ArrayList();
	camerasProjectiles = new ArrayList();
	
	droneSpeed = cvar_dronespeed.FloatValue;
	droneJumpForce = cvar_dronejump.FloatValue;
	droneHoverHeight = cvar_dronehoverheight.FloatValue;
	useCamAngles = cvar_use_cam_angles.BoolValue;
	useCustomCamModel = cvar_custom_model_cam.BoolValue;
	useCustomDroneModel = cvar_custom_model_drone.BoolValue;
	SetBuyTime();
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		if (isNewRound && cvar_keep_between_rounds.BoolValue)
		{
			if (availabletGear[i] <= 0)
			{
				availabletGear[i] = 0;
				playerGearOverride[i] = 0;
			}
		}
		else
		{
			availabletGear[i] = 0;
			playerGearOverride[i] = 0;
		}
		
		for (int j = 0; j < sizeof(activeCam[]); j++)
		{
			activeCam[i][j] = -1;
		}
		for (int j = 0; j < sizeof(activeDrone[]); j++)
		{
			activeDrone[i][j] = -1;
		}
		fakePlayersListCamera[i] = -1;
		fakePlayersListDrones[i] = -1;
		canDisplayThrowWarning[i] = true;
		canDroneJump[i] = true;
		isDroneJumping[i] = false;
		canBuy[i] = true;
	}
}

/**
* Set whether a specific client or every clients can buy gear.
*
* @param client_index		Index of the client. -1 for every client.
* @param state				Whether the client can buy.
*/
public void SetBuyState(int client_index, bool state)
{
	if (IsValidClient(client_index))
		canBuy[client_index] = state;
	else
	{
		for (int i = 0; i < sizeof(canBuy); i++)
		{
			canBuy[i] = state;
		}
	}
}

/**
* Set the buy time based on the cvar value.
*/
public void SetBuyTime()
{
	if (cvar_buytime.IntValue == -1)
		buyTime = -1.0;
	else if (cvar_buytime.IntValue == -2)
		buyTime = FindConVar("mp_buytime").FloatValue;
	else
		buyTime = cvar_buytime.FloatValue;
}

/************************************************************************************************************
*											NATIVES
************************************************************************************************************/

public int Native_BuyPlayerGear(Handle plugin, int numParams)
{
	int client_index = GetNativeCell(1);
	if (!IsValidClient(client_index))
	{
		PrintToServer("Invalid client (%d)", client_index)
		return;
	}
	if (IsClientTeamCameras(client_index))
		BuyCamera(client_index, true);
	else if (IsClientTeamDrones(client_index))
		BuyDrone(client_index, true);
}

public int Native_OverridePlayerGear(Handle plugin, int numParams)
{
	int client_index = GetNativeCell(1);
	if (!IsValidClient(client_index))
	{
		PrintToServer("Invalid client (%d)", client_index)
		return;
	}
	int gearNum = GetNativeCell(2);
	
	if (gearNum > 2 || gearNum < -1)
		gearNum = 0;
	
	playerGearOverride[client_index] = gearNum;
	
	switch (gearNum)
	{
		case -1: PrintToConsole(client_index, "You can't use any gear");
		case 0: PrintToConsole(client_index, "You are now using your team gear");
		case 1: PrintToConsole(client_index, "You are now using cameras");
		case 2: PrintToConsole(client_index, "You are now using drones");
	}
}

public int Native_IsPlayerInGear(Handle plugin, int numParams)
{
	int client_index = GetNativeCell(1);
	if (!IsValidClient(client_index))
	{
		PrintToServer("Invalid client (%d)", client_index)
		return false;
	}
	return IsClientInGear(client_index);
}

/************************************************************************************************************
*											EVENTS
************************************************************************************************************/

/**
* Resets variables and closes player menus on round start.
*/
public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	InitVars(true);
	ResetDronesMenuAll();
	ResetCamerasMenuAll();
	for(int i = 0;  i < MAXPLAYERS; i++)
	{
		if (IsValidClient(i))
			CloseGear(i);
	}
	if (cvar_buytime_start.IntValue == 0)
	{
		SetBuyState(-1, true);
		if (buyTime >= 0.0)
			CreateTimer(buyTime, Timer_BuyTime, -1);
	}
}

/**
* Gets the player's view model index for future usage.
*/
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	int ref = EntIndexToEntRef(client_index);
	clientsViewmodels[client_index] = GetViewModelIndex(client_index);
	CloseGear(client_index);
	if (cvar_buytime_start.IntValue == 1)
	{
		SetBuyState(client_index, true);
		if (buyTime >= 0.0)
			CreateTimer(buyTime, Timer_BuyTime, ref);
	}
}

/************************************************************************************************************
*											COMMANDS
************************************************************************************************************/

/**
* Reads the custom models file.
*/
public Action ReloadModelsList(int client_index, int args)
{
	ReadCustomModelsFile();
	return Plugin_Handled;
}

/**
* Displays help to the player in console and chat.
*/
public Action ShowHelp(int client_index, int args)
{
	PrintToConsole(client_index, "|-------------------------------------------------------|");
	PrintToConsole(client_index, "|----------- CAMERAS AND DRONES HELP -------------------|");
	PrintToConsole(client_index, "|---- CONSOLE ----|-- IN CHAT --|-- DESCRIPTION --------|");
	PrintToConsole(client_index, "|cd_buy           |             |Buy team gear          |");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|cd_deploy        |             |Deploy gear            |");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|cd_toggle        |             |Toggle gear open/closed|");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|cd_help          |!cd_help     |Display this help      |");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|-----------        ADMIN ONLY       -------------------|");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|cd_override      |             |Override player gear   |");
	PrintToConsole(client_index, "|-----------------|-------------|-----------------------|");
	PrintToConsole(client_index, "|cd_reloadmodels  |             |Reload custom models   |");
	PrintToConsole(client_index, "|-------------------------------------------------------|");
	PrintToConsole(client_index, "");
	PrintToConsole(client_index, "For a better experience, you should bind cd_buy and cd_cam to a key:");
	PrintToConsole(client_index, "bind 'KEY' 'COMMAND' | This will bind 'COMMAND to 'KEY'");
	PrintToConsole(client_index, "EXAMPLE:");
	PrintToConsole(client_index, "bind \"z\" \"cd_buy\" | This will bind the buy command to the <Z> key");
	PrintToConsole(client_index, "bind \"x\" \"cd_deploy\" | This will bind the deploy command to the <X> key");
	PrintToConsole(client_index, "bind \"c\" \"cd_toggle\" | This will bind the toggle command to the <C> key");
	
	CPrintToChat(client_index, "{green}----- CAMERAS AND DRONES HELP -----");
	CPrintToChat(client_index, "{lime}>>> START");
	CPrintToChat(client_index, "This plugin is used with the console:");
	CPrintToChat(client_index, "To enable the console, do the following:");
	CPrintToChat(client_index, "{yellow}Options -> Game Option -> Enable Developper Console");
	CPrintToChat(client_index, "To set the toggle key, do the following:");
	CPrintToChat(client_index, "{yellow}Options -> Keyboard/Mouse -> Toggle Console");
	CPrintToChat(client_index, "{lime}Open the console for more information");
	CPrintToChat(client_index, "{green}----- ---------- ---------- -----");
	return Plugin_Handled;
}

/**
* Overrides the given player's gear.
* This way you can have a ct using a camera while his team uses drones.
*/
public Action OverrideGear(int client_index, int args)
{
	if (args == 0)
	{
		PrintToConsole(client_index, "Usage: cd_override <player> <gear_num>");
		PrintToConsole(client_index, "<gear_num> = 0 | no override");
		PrintToConsole(client_index, "<gear_num> = 1 | force camera");
		PrintToConsole(client_index, "<gear_num> = 1 | force drone");
		return Plugin_Handled;
	}
	
	char name[32];
	int target = -1;
	GetCmdArg(1, name, sizeof(name));
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
		{
			continue;
		}
		char other[32];
		GetClientName(i, other, sizeof(other));
		if (StrEqual(name, other))
		{
			target = i;
		}
	}
	if (target == -1)
	{
		PrintToConsole(client_index, "Could not find any player with the name: \"%s\"", name);
		PrintToConsole(client_index, "Available players:");
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientConnected(i))
			{
				continue;
			}
			char player[32];
			GetClientName(i, player, sizeof(player));
			PrintToConsole(client_index, "\"%s\"", player);
		}
		return Plugin_Handled;
	}
	
	char gear[32];
	GetCmdArg(2, gear, sizeof(gear));
	int gearNum = StringToInt(gear);
	
	if (gearNum > 2 || gearNum < -1)
		gearNum = 0;
	
	playerGearOverride[target] = gearNum;
	
	switch (gearNum)
	{
		case -1:
		{
			PrintToConsole(client_index, "% now doesn't have gear", name);
			PrintToConsole(target, "You can't use any gear");
		}
		case 0:
		{
			PrintToConsole(client_index, "%s now doesn't have gear override", name);
			PrintToConsole(target, "You are now using your team gear");
		}
		case 1:
		{
			PrintToConsole(client_index, "%s now has cameras", name);
			PrintToConsole(target, "You are now using cameras");
		}
		case 2:
		{
			PrintToConsole(client_index, "%s now has drones", name);
			PrintToConsole(target, "You are now using drones");
		}
	}
	
	return Plugin_Handled;
}

/**
* Buys the correct gear for the player.
*/
public Action BuyGear(int client_index, int args)
{
	if (IsClientTeamCameras(client_index))
		BuyCamera(client_index, false);
	else if (IsClientTeamDrones(client_index))
		BuyDrone(client_index, false);
	
	return Plugin_Handled;
}

/**
* Gives the given player a camera if he has enough money and doesn't already have one.
*
* @param client_index    index of the client.
* @param isFree    whether to give the camera for free or not.
*/
public void BuyCamera(int client_index, bool isFree)
{
	if (!canBuy[client_index])
	{
		PrintHintText(client_index, "<font color='#ff0000'>Buy time expired</font>");
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	if (!isFree)
	{
		int money = GetEntProp(client_index, Prop_Send, "m_iAccount");
		if (cvar_camprice.IntValue > money)
		{
			PrintHintText(client_index, 
			"<font color='#ff0000'>Not enough money</font><br>Needed: <font color='#ff0000'>%i</font><br>Have: <font color='#00ff00'>%i</font>", 
			cvar_camprice.IntValue, money);
			EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
			return;
		}
		SetEntProp(client_index, Prop_Send, "m_iAccount", money - cvar_camprice.IntValue);
	}
	
	EmitSoundToClient(client_index, getGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	PrintHintText(client_index, "<font color='#0fff00'>You just bought a</font> %s<br>Use <font color='#00ff00'>cd_deploy</font> to deploy it.", camHTML);
	availabletGear[client_index]++;
}

/**
* Gives the given player a drone if he has enough money and doesn't already have one.
*
* @param client_index    index of the client.
* @param isFree    whether to give the drone for free or not.
*/
public void BuyDrone(int client_index, bool isFree)
{
	if (!canBuy[client_index])
	{
		PrintHintText(client_index, "<font color='#ff0000'>Buy time expired</font>");
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	if (!isFree)
	{
		int money = GetEntProp(client_index, Prop_Send, "m_iAccount");
		if (cvar_droneprice.IntValue > money)
		{
			PrintHintText(client_index, 
			"<font color='#ff0000'>Not enough money</font><br>Needed: <font color='#ff0000'>%i</font><br>Have: <font color='#00ff00'>%i</font>", 
			cvar_droneprice.IntValue, money);
			EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
			return;
		}
		SetEntProp(client_index, Prop_Send, "m_iAccount", money - cvar_droneprice.IntValue);
	}
	EmitSoundToClient(client_index, getGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	PrintHintText(client_index, "<font color='#0fff00'>You just bought a</font> %s<br>Use <font color='#00ff00'>cd_deploy</font> to deploy it.", droneHTML);
	availabletGear[client_index]++;
}

/**
* Deploy the camera or drone depending on the player gear.
*/
public Action DeployGear(int client_index, int args)
{
	if (availabletGear[client_index] <= 0)
	{
		PrintHintText(client_index, "<font color='#ff0000'>No gear available</font>");
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return Plugin_Handled;
	}
	if (!CanThrowGear(client_index))
	{
		
	}
	float pos[3], rot[3], vel[3];
	GetClientEyePosition(client_index, pos)
	GetClientEyeAngles(client_index, rot);
	GetAngleVectors(rot, vel, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vel, 200.0);
	vel[2] += 50.0;
	
	if (IsClientTeamCameras(client_index))
		CreateCamera(client_index, pos, rot, vel);
	else if (IsClientTeamDrones(client_index))
		CreateDrone(client_index, pos, rot, vel);
	
	availabletGear[client_index]--;
	if (IsClientTeamCameras(client_index))
		PrintHintText(client_index, "%s deployed.<br>Remaining: %i<br>Use <font color='#00ff00'>cd_toggle</font> to use it.", camHTML, availabletGear[client_index]);
	else if (IsClientTeamDrones(client_index))
		PrintHintText(client_index, "%s deployed.<br>Remaining: %i<br>Use <font color='#00ff00'>cd_toggle</font> to use it.", droneHTML, availabletGear[client_index]);
	return Plugin_Handled;
}

/**
* Opens the camera or drone depending on the player gear.
* If the given player is already in gear, close it.
*/
public Action ToggleGear(int client_index, int args)
{
	if (IsClientInGear(client_index))
	{
		CloseGear(client_index);
		return Plugin_Handled;
	}
	
	if (IsClientTeamCameras(client_index))
		OpenCamera(client_index);
	else if (IsClientTeamDrones(client_index))
		OpenDrone(client_index);
	
	return Plugin_Handled;
}

/**
* If the given player is not in the air and at least one camera is available,
* puts the player in his camera, or in an other one available if the player doesn't have any.
*
* @param client_index    index of the client.
*/
public void OpenCamera(int client_index)
{
	if (!(GetEntityFlags(client_index) & FL_ONGROUND))
	{
		PrintHintText(client_index, "<font color='#ff0000'>Cannot use %s while jumping</font>", camHTML);
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	if (camerasList.Length == 0)
	{
		PrintHintText(client_index, "<font color='#ff0000'>No %s available</font>", camHTML);
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	int owner;
	int target = -1;
	for (int i = 0; i < camerasList.Length; i++)
	{
		if (IsValidEntity(i) && IsValidClient(client_index))
		{
			owner = camOwnersList.Get(i);
			if (owner == client_index)
			{
				target = camerasList.Get(i);
				break;
			}
		}
	}
	if (target == -1)
		target = camerasList.Get(0);
	
	Menu_Cameras(client_index, camerasList.FindValue(target));
	TpToCam(client_index, target);
}

/**
* If the given player is not in the air and has at least one drone available,
* puts the player in one of his drones.
*
* @param client_index    index of the client.
*/
public void OpenDrone(int client_index)
{
	if (!(GetEntityFlags(client_index) & FL_ONGROUND))
	{
		PrintHintText(client_index, "<font color='#ff0000'>Cannot use %s while jumping</font>", droneHTML);
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	if (dronesList.Length == 0)
	{
		PrintHintText(client_index, "<font color='#ff0000'>No %s available</font>", droneHTML);
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	int owner;
	int target = -1;
	for (int i = 0; i < dronesList.Length; i++)
	{
		if (IsValidEntity(i) && IsValidClient(client_index))
		{
			owner = dronesOwnerList.Get(i);
			if (owner == client_index)
			{
				target = dronesList.Get(i);
				break;
			}
		}
	}
	if (target == -1)
	{
		PrintHintText(client_index, "<font color='#ff0000'>No %s available</font>", droneHTML);
		EmitSoundToClient(client_index, cantBuyGearSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		return;
	}
	
	Menu_Drones(client_index, dronesList.FindValue(target));
	TpToDrone(client_index, target);
}

/************************************************************************************************************
*											GEAR SPECIFIC METHODS
************************************************************************************************************/

/**
* Checks if the given player can throw his camera/drone.
*
* @param client_index		index of the client.
* @return 					true if the player can throw his gear, false otherwise.
*/
public bool CanThrowGear(int client_index)
{
	if (IsClientTeamCameras(client_index))
		return CanThrowCamera(client_index);
	else if (IsClientTeamDrones(client_index))
		return CanThrowDrone(client_index);
	else
		return false;
}

/**
* If the given player hasn't reached the camera limit, allow him to throw more.
* Otherwise, display an error message.
*
* @param client_index		index of the client.
* @return 					true if the player can throw the camera, false otherwise.
*/
public bool CanThrowCamera(int client_index)
{
	int counter;
	for (int i = 0; i < camOwnersList.Length; i++)
	{
		if (camOwnersList.Get(i) == client_index)
			counter++;
	}
	if (cvar_totalmax_cam.IntValue > counter)
		return true;
	else
	{
		if (canDisplayThrowWarning[client_index])
		{
			canDisplayThrowWarning[client_index] = false;
			PrintHintText(client_index, "<font color='#ff0000'>You cannot place any more</font> %s", camHTML);
			int ref = EntIndexToEntRef(client_index);
			CreateTimer(1.0, Timer_DisplayThrowWarning, ref);
		}
		return false;
	}
}

/**
* If the given player hasn't reached the drone limit, allow him to throw more.
* Otherwise, display an error message.
*
* @param client_index		index of the client.
* @return 					true if the player can throw the drone, false otherwise.
*/
public bool CanThrowDrone(int client_index)
{
	int counter;
	for (int i = 0; i < dronesOwnerList.Length; i++)
	{
		if (dronesOwnerList.Get(i) == client_index)
			counter++;
	}
	if (cvar_totalmax_drone.IntValue > counter)
		return true;
	else
	{
		if (canDisplayThrowWarning[client_index])
		{
			canDisplayThrowWarning[client_index] = false;
			PrintHintText(client_index, "<font color='#ff0000'>You cannot place any more</font> %s", droneHTML);
			int ref = EntIndexToEntRef(client_index);
			CreateTimer(1.0, Timer_DisplayThrowWarning, ref);
		}
		return false;
	}
}

/**
* If the given player is close enough of his gear (chosen by cvar),
* allow him to pick it up.
*
* @param client_index		index of the client.
* @param i					index of the gear in its list.
*/
public void PickupGear(int client_index, int i)
{
	float pos[3], gearPos[3];
	GetClientEyePosition(client_index, pos);
	
	if (IsClientTeamCameras(client_index))
	{
		int cam = camerasList.Get(i);
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", gearPos);
		if (GetVectorDistance(pos, gearPos, false) < cvar_pickuprange.FloatValue)
			PickupCamera(client_index, cam);
	}
	else if (IsClientTeamDrones(client_index))
	{
		int drone = dronesList.Get(i);
		GetEntPropVector(drone, Prop_Send, "m_vecOrigin", gearPos);
		if (GetVectorDistance(pos, gearPos, false) < cvar_pickuprange.FloatValue)
			PickupDrone(client_index, drone);
	}
}

/**
* Destroys the given camera and gives one back to the player.
*
* @param client_index		index of the client.
* @param cam				index of the camera.
*/
public void PickupCamera(int client_index, int cam)
{
	DestroyCamera(cam, true);
	availabletGear[client_index]++;
	PrintHintText(client_index, "%s recovered<br><font color='#ffffff'>Available gear:</font> <font color='#00ff00'>%i</font>", camHTML, availabletGear[client_index]);
}

/**
* Destroys the given drone and gives one back to the player.
*
* @param client_index		index of the client.
* @param drone				index of the drone.
*/
public void PickupDrone(int client_index, int drone)
{
	DestroyDrone(drone, true);
	availabletGear[client_index]++;
	PrintHintText(client_index, "%s recovered</font><br><font color='#ffffff'>Available gear:</font> <font color='#00ff00'>%i</font>", droneHTML, availabletGear[client_index]);
}

/**
* Closes the camera/drone for the given player.
*
* @param client_index		index of the client.
*/
public void CloseGear(int client_index)
{
	if (IsClientTeamCameras(client_index))
		CloseCamera(client_index);
	else if (IsClientTeamDrones(client_index))
		CloseDrone(client_index);
}

/**
* Exits the camera for the given player and closes the cameras menu.
*
* @param client_index		index of the client.
*/
public void CloseCamera(int client_index)
{
	ExitCam(client_index);
	if (playerCamMenus[client_index] != null)
	{
		delete playerCamMenus[client_index];
		playerCamMenus[client_index] = null;
	}
}

/**
* Exits the drone for the given player and closes the drones menu.
*
* @param client_index		index of the client.
*/
public void CloseDrone(int client_index)
{
	ExitDrone(client_index);
	if (playerDroneMenus[client_index] != null)
	{
		delete playerDroneMenus[client_index];
		playerDroneMenus[client_index] = null;
	}
}

/************************************************************************************************************
*											INPUT
************************************************************************************************************/

public Action OnPlayerRunCmd(int client_index, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsPlayerAlive(client_index))
		return Plugin_Continue;
	
	if (IsClientInGear(client_index)) // in gear input
	{
		//Disable weapons
		float fUnlockTime = GetGameTime() + 1.0;
		SetEntPropFloat(client_index, Prop_Send, "m_flNextAttack", fUnlockTime);
		
		if (buttons & IN_DUCK) // Prevent crouching camera bugs
		{
			buttons &= ~IN_DUCK;
			CloseGear(client_index);
		}
		if (buttons & IN_USE) // Prevent interaction with the world
		{
			buttons &= ~IN_USE;
		}
	}
	else // normal player input
	{
		if (buttons & IN_USE && camerasList != INVALID_HANDLE && dronesList != INVALID_HANDLE) // pickup
		{
			int target = GetClientAimTarget(client_index, false);
			int cam = camerasList.FindValue(target);
			int drone = dronesList.FindValue(target);
			if (cam != -1 && camOwnersList.Length > 0 && camOwnersList.Get(cam) == client_index)
				PickupGear(client_index, cam);
			else if (drone  != -1 && dronesOwnerList.Length > 0 && dronesOwnerList.Get(drone) == client_index)
				PickupGear(client_index, drone);
		}
	}
	
	if (IsClientInDrone(client_index)) // Drone specific input
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 0.0;
		if (buttons & IN_FORWARD)
		{
			isDroneMoving[client_index] = true;
			if (!isDroneJumping[client_index]) // Prevent moving reset vel while trying to jump
				MoveDrone(client_index, activeDrone[client_index][0]);
		}
		if ((buttons & IN_JUMP) && canDroneJump[client_index])
		{
			canDroneJump[client_index] = false;
			isDroneJumping[client_index] = true;
			JumpDrone(client_index, activeDrone[client_index][0]);
			CreateTimer(0.1, Timer_IsJumping, client_index);
			CreateTimer(cvar_jumpcooldown.FloatValue, Timer_CanJump, client_index);
		}
		if (buttons & IN_SPEED)
			isDroneMoving[client_index] = true;
		else if (!(buttons & IN_FORWARD))
			isDroneMoving[client_index] = false;
	}
	return Plugin_Changed;
}

/************************************************************************************************************
*											TIMERS
************************************************************************************************************/

/**
* Displays a welcome message to the given player, presenting the plugin name, author and how to show help.
*/
public Action Timer_WelcomeMessage(Handle timer, any ref)
{
	int client_index = EntRefToEntIndex(ref);
	if (cvar_welcome_message.BoolValue && IsValidClient(client_index))
	{
		//Welcome message (white text in red box)
		CPrintToChat(client_index, "{darkred}********************************");
		CPrintToChat(client_index, "{darkred}* {default}This server uses {lime}%s", PLUGIN_NAME);
		CPrintToChat(client_index, "{darkred}*            {default}Made by {lime}%s", AUTHOR);
		CPrintToChat(client_index, "{darkred}* {default}Use {lime}!cd_help{default} in chat to learn");
		CPrintToChat(client_index, "{darkred}*                  {default}how to play");
		CPrintToChat(client_index, "{darkred}********************************");
	}
}

/**
* Resets the throw warning variable for the given player.
*/
public Action Timer_DisplayThrowWarning(Handle timer, any ref)
{
	int client_index = EntRefToEntIndex(ref);
	if (IsValidClient(client_index))
	{
		canDisplayThrowWarning[client_index] = true;
	}
}

/**
* Resets the can jump variable for the given player.
*/
public Action Timer_CanJump(Handle timer, any ref)
{
	int client_index = EntRefToEntIndex(ref);
	if (IsValidClient(client_index))
	{
		canDroneJump[client_index] = true;
	}
}

/**
* Resets the is drone jumping variable for the given player.
*/
public Action Timer_IsJumping(Handle timer, any ref)
{
	int client_index = EntRefToEntIndex(ref);
	if (IsValidClient(client_index))
	{
		isDroneJumping[client_index] = false;
	}
}

 /**
 * Stops players from buying after a time limit.
 * This limit can be set by cvar.
 */
public Action Timer_BuyTime(Handle timer, any ref)
{
	int client_index = EntRefToEntIndex(ref);
	if (IsValidClient(client_index))
		SetBuyState(client_index, false);
	else
		SetBuyState(-1, false);
}

/************************************************************************************************************
*											HOOKS
************************************************************************************************************/

public Action Hook_PostThinkPlayer(int client_index)
{
	if (camerasProjectiles == null || camerasProjectiles.Length == 0 || cvar_cam_box_size.IntValue == 0)
		return Plugin_Continue;
	
	for (int i = 0; i < camerasProjectiles.Length; i++)
	{
		int cam = camerasProjectiles.Get(i);
		float x = cvar_cam_box_size.FloatValue / 2.0;
		float boxMin[3], boxMax[3], pos[3];
		for (int j = 0; j < sizeof(boxMax); j++)
		{
			boxMin[j] = -x;
			boxMax[j] = x;
		}
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
		TR_TraceHullFilter(pos, pos, boxMin, boxMax, MASK_SOLID, TRFilter_NoPlayer, cam);
		if (TR_DidHit())
		{
			SetEntityMoveType(cam, MOVETYPE_NONE)
			camerasProjectiles.Erase(i);
		}
	}
	return Plugin_Continue;
}

/**
* Hide player only if using cam/drone.
*/
public Action Hook_SetTransmitPlayer(int entity_index, int client_index)
{
	if (client_index != entity_index && IsValidClient(entity_index) && IsClientInGear(entity_index))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

/**
* Hide cam/drone only to the one using it.
*/
public Action Hook_SetTransmitGear(int entity_index, int client_index)
{
	if (IsValidClient(client_index) && ((activeCam[client_index][1] == entity_index || activeCam[client_index][2] == entity_index) || activeDrone[client_index][1] == entity_index))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

/**
* Transmits damage given to the fake model to its owner.
*/
public Action Hook_TakeDamageFakePlayer(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	int owner = GetEntPropEnt(victim, Prop_Send, "m_hOwnerEntity");
	char weapon[64];
	GetClientWeapon(attacker, weapon, sizeof(weapon))
	RemoveHealth(owner, damage, attacker, damagetype, weapon);
}

/**
* Prevents player in camera/drone from picking up weapons.
*/
public Action Hook_WeaponCanUse(int client_index, int weapon_index)
{
	if (IsClientInGear(client_index))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

/**
* Destroy the gear if an enemy or the owner is shooting at it,
* or if a teammate is shooting at it and tk is enabled (with a cvar).
*/
public Action Hook_TakeDamageGear(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	int client_index = -1;
	if (camerasList.FindValue(victim) != -1)
		client_index = camOwnersList.Get(camerasList.FindValue(victim));
	else if (dronesList.FindValue(victim) != -1)
		client_index = dronesOwnerList.Get(dronesList.FindValue(victim));
	if (!IsValidClient(client_index) || !IsValidClient(inflictor))
		return Plugin_Handled;
	if (cvar_tkprotect.BoolValue && GetClientTeam(client_index) == GetClientTeam(inflictor) && client_index != inflictor)
		return Plugin_Handled;
	
	if (IsClientTeamCameras(client_index))
		DestroyCamera(victim, false);
	else if (IsClientTeamDrones(client_index))
		DestroyDrone(victim, false);
	
	return Plugin_Continue;
}

/**
* Prevent players in gear from taking damage.
*/
public Action Hook_TakeDamagePlayer(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (IsClientInGear(victim))
		return Plugin_Handled;
	else
		return Plugin_Continue;
}

/**
* Stops drop command if the player is in gear.
*/
public Action CommandDrop(int client_index, const char[] command, int argc)
{
	if (IsClientInGear(client_index))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

/**
* Resets player variables if switching teams while in gear.
*/
public Action CommandJoinTeam(int client_index, const char[] command, int argc)
{
	if (IsClientInGear(client_index))
		ResetPlayer(client_index)
	return Plugin_Continue;
}

/************************************************************************************************************
*											FAKE PLAYER RELATED
************************************************************************************************************/

/**
* Removes the specified health to the given player, and kills him if his health is lower than the damage taken.
*
* @param client_index		index of the client taking damage.
* @param damage			damage to deal to the player.
* @param attacker			index of the player doing damage.
* @param damagetype		damage type received by the player.
* @param weapon			classname of the weapon with which the attacked is shooting.
*/
public void RemoveHealth(int client_index, float damage, int attacker, int damagetype, char[] weapon)
{
	
	int health = GetClientHealth(client_index);
	int dmg = RoundToNearest(damage);
	if (health > dmg)
		SetEntityHealth(client_index, health - dmg);
	else
	{
		CloseGear(client_index);
		SetEntityHealth(client_index, 1);// Make sure he dies from the dealdamage
		DealDamage(client_index, dmg, attacker, damagetype, weapon);
	}
}

/**
* Deals damage to the given player.
*
* @param client_index		index of the client taking damage.
* @param damage			damage to deal to the player.
* @param attacker			index of the player doing damage.
* @param dmgType			damage type received by the player.
* @param weapon			classname of the weapon with which the attacked is shooting.
*/
public void DealDamage(int victim, int damage, int attacker, int dmgType, char[] weapon)
{
	if(victim > 0 && IsValidEdict(victim) && IsClientInGame(victim) && IsPlayerAlive(victim) && damage > 0)
	{
		char c_dmg[16];
		IntToString(damage, c_dmg, sizeof(c_dmg));
		char c_dmgType[32];
		IntToString(dmgType, c_dmgType, sizeof(c_dmgType));
		char c_victim[16];
		IntToString(victim, c_victim, sizeof(c_victim));
		int pointHurt = CreateEntityByName("point_hurt");
		if(IsValidEntity(pointHurt))
		{
			DispatchKeyValue(victim, "targetname", c_victim);
			DispatchKeyValue(pointHurt, "DamageTarget", c_victim);
			DispatchKeyValue(pointHurt, "Damage", c_dmg);
			DispatchKeyValue(pointHurt, "DamageType", c_dmgType);
			if(!StrEqual(weapon,""))
			{
				DispatchKeyValue(pointHurt, "classname", weapon);
			}
			DispatchSpawn(pointHurt);
			AcceptEntityInput(pointHurt, "Hurt", (attacker > 0) ? attacker : -1);
			DispatchKeyValue(pointHurt, "classname", "point_hurt");
			DispatchKeyValue(victim, "targetname", "donthurtme");
			RemoveEdict(pointHurt);
		}
	}
}

/**
* Creates a fake player model for the given player.
* This model will not have any animation, but will redirect the damage taken to the player.
* The fake player is solid (even for teammates) and uses the model hitbox, instead of player collision box
* (This means you can climb on a standing fake player).
*
* @param client_index		index of the client.
* @param isCam				whether the player is using a camera or a drone.
*/
public void CreateFakePlayer(int client_index, bool isCam)
{
	int fake = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(fake)) {
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(client_index, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		SetEntityModel(fake, modelName);
		SetEntPropEnt(fake, Prop_Send, "m_hOwnerEntity", client_index);
		
		float pos[3], rot[3];
		GetClientEyeAngles(client_index, rot);
		rot[0] = 0.0;
		GetEntPropVector(client_index, Prop_Send, "m_vecOrigin", pos);
		TeleportEntity(fake, pos, rot, NULL_VECTOR);
		DispatchKeyValue(fake, "Solid", "6");
		DispatchSpawn(fake);
		ActivateEntity(fake);
		
		
		SDKHook(fake, SDKHook_OnTakeDamage, Hook_TakeDamageFakePlayer);
		
		//SetVariantString("ACT_IDLE"); AcceptEntityInput(fake, "SetAnimation"); // Can't find sequence ?!
		
		if (isCam)
			fakePlayersListCamera[client_index] = fake;
		else
			fakePlayersListDrones[client_index] = fake;
	}
}

/************************************************************************************************************
*											TESTS
************************************************************************************************************/

/**
* Checks whether the given player is using his gear or not.
*
* @param client_index		index of the client.
* @return					true if the player is using his gear, false otherwise.
*/
public bool IsClientInGear(int client_index)
{
	return IsClientInCam(client_index) || IsClientInDrone(client_index);
}

/**
* Checks if the given player's team gear is cameras.
* Also checks if the player's gear has been overriden.
*
* @param client_index		index of the client.
* @return					true if the player gear is cameras, false otherwise.
*/
public bool IsClientTeamCameras(int client_index)
{
	return playerGearOverride[client_index] != -1 && GetClientTeam(client_index) > 1 && (((GetClientTeam(client_index) == cvar_gearteam.IntValue || cvar_gearteam.IntValue == 1) && playerGearOverride[client_index] == 0) || playerGearOverride[client_index] == 1);
}

/**
* Checks if the given player's team gear is drones.
* Also checks if the player's gear has been overriden.
*
* @param client_index		index of the client.
* @return					true if the player gear is drones, false otherwise.
*/
public bool IsClientTeamDrones(int client_index)
{
	return playerGearOverride[client_index] != -1 && GetClientTeam(client_index) > 1 && (((GetClientTeam(client_index) != cvar_gearteam.IntValue || cvar_gearteam.IntValue == 0) && playerGearOverride[client_index] == 0) || playerGearOverride[client_index] == 2);
}

/**
* Checks if the given player is valid.
* In order for a player to be valid, his index must be between 1 and the max,
* he must be connected and be in game.
*
* @param client_index		index of the client.
* @return					true if the player is valid, false otherwise.
*/
stock bool IsValidClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client))
	{
		return false;
	}
	return IsClientInGame(client);
}

/************************************************************************************************************
*											PLAYER VIEW
************************************************************************************************************/

/**
* Gets the given player's view model index.
*
* @param client_index		index of the client.
* @return					player's view model index.
*/
public int GetViewModelIndex(int client_index)
{
	int index = MAXPLAYERS;
	while ((index = FindEntityByClassname(index, "predicted_viewmodel")) != -1)
	{
		int owner = GetEntPropEnt(index, Prop_Send, "m_hOwner");
		
		if (owner != client_index)
			continue;
		
		return index;
	}
	return -1;
}

/**
* Sets the given player's view model hidden or shown.
*
* @param client_index		index of the client.
* @param enabled			whether to show the view model or not.
*/
public void SetViewModel(int client_index, bool enabled)
{
	int EntEffects = GetEntProp(clientsViewmodels[client_index], Prop_Send, "m_fEffects");
	if (enabled)
		EntEffects |= ~32;
	else
		EntEffects |= 32; // Set to Nodraw
	SetEntProp(clientsViewmodels[client_index], Prop_Send, "m_fEffects", EntEffects);
}

/**
* Sets the given player's screen tint to grey if he is in gear.
*
* @param client_index		index of the client.
* @param isActive			whether to show the gear screen or not.
*/
public void SetGearScreen(int client, bool isActive)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return;
	
	if (isActive)
		DisplayOverlay(client, gearOverlay);
	else
		ClearOverlay(client);
	
	
	int duration = 255;
	int holdtime = 255;
	int color[4];
	if (isActive)
		color[3] = 128
	else
		color[3] = 0;
	color[0] = 120;
	color[1] = 120;
	color[2] = 120;
	
	Handle message = StartMessageOne("Fade",client);
	if (GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(message, "duration", duration); //fade
		PbSetInt(message, "hold_time", holdtime); //blind
		PbSetInt(message, "flags", FFADE_STAYOUT|FFADE_PURGE);
		PbSetColor(message, "clr", color);
	}
	else
	{
		BfWriteShort(message,duration);
		BfWriteShort(message,holdtime);
		BfWriteShort(message, FFADE_STAYOUT|FFADE_PURGE);
		BfWriteByte(message,color[0]);
		BfWriteByte(message,color[1]);
		BfWriteByte(message,color[2]);
		BfWriteByte(message,color[3]);
	}
	
	EndMessage();
}

/**
* Hides the given player's hud.
* This must be called each frame in order to work.
*
* @param client_index		index of the client.
*/
public void HideHudGuns(int client_index)
{
	SetEntProp(client_index, Prop_Send, "m_iHideHUD", HIDEHUD_WEAPONSELECTION);
}

/************************************************************************************************************
*											CONVARS
************************************************************************************************************/

/**
* Changes the variables associated to the cvars when changed.
*/
public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == cvar_dronespeed)
		droneSpeed = convar.FloatValue;
	else if (convar == cvar_dronejump)
		droneJumpForce = convar.FloatValue;
	else if (convar == cvar_dronehoverheight)
		droneHoverHeight = convar.FloatValue;
	else if (convar == cvar_buytime)
		SetBuyTime();
	else if (convar == cvar_use_cam_angles)
		useCamAngles = convar.BoolValue;
	else if (convar == cvar_custom_model_drone)
		useCustomDroneModel = convar.BoolValue;
	else if (convar == cvar_custom_model_cam)
		useCustomCamModel = convar.BoolValue;
}

/**
* If the custom models file exists, read its content and set the custom models
* to the ones specified in the file, if they are valid.
* Invalid models will be set to default.
*/
public void ReadCustomModelsFile()
{
	char path[PLATFORM_MAX_PATH], line[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s", customModelsPath);
	if (!FileExists(path))
	{
		customCamModel = "";
		customCamPhysModel = "";
		customDroneModel = "";
		customDronePhysModel = "";
		PrintToServer("Could not find custom models file. Falling back to default");
		return;
	}
	File file = OpenFile(path, "r");
	while (file.ReadLine(line, sizeof(line)))
	{
		if (StrContains(line, "//", false) == 0)
			continue;
		
		if (StrContains(line, "cammodel=", false) == 0)
			ReadModel(line, "cammodel=", 0)
		if (StrContains(line, "camphys=", false) == 0)
			ReadModel(line, "camphys=", 1)
		else if (StrContains(line, "dronemodel=", false) == 0)
			ReadModel(line, "dronemodel=", 2)
		else if (StrContains(line, "dronephys=", false) == 0)
			ReadModel(line, "dronephys=", 3)
		else if (StrContains(line, "camrot{", false) == 0)
			SetCustomRotation(file, false);
		else if (StrContains(line, "dronerot{", false) == 0)
			SetCustomRotation(file, true);
		
		if (file.EndOfFile())
			break;
	}
	CloseHandle(file);
}

/**
* Reads the given line and extracts the model name.
* If the model name is valid, sets the associated custom model variable.
*
* @param line				line to extract the model name from.
* @param trigger			trigger name used for this model.
* @param type				model type. 0 = camera model ; 1 = camera physics model ; 2 = drone model ; 3 = drone physics model.
*/
public void ReadModel(char line[PLATFORM_MAX_PATH], char[] trigger, int type)
{
	ReplaceString(line, sizeof(line), trigger, "", false);
	ReplaceString(line, sizeof(line), "\n", "", false);
	if (TryPrecacheCamModel(line))
	{
		switch (type)
		{
			case 0: Format(customCamModel, sizeof(customCamModel), "%s", line);
			case 1: Format(customCamPhysModel, sizeof(customCamPhysModel), "%s", line);
			case 2: Format(customDroneModel, sizeof(customDroneModel), "%s", line);
			case 3: Format(customDronePhysModel, sizeof(customDronePhysModel), "%s", line);
		}
	}
	else
	{
		switch (type)
		{
			case 0: customCamModel = "";
			case 1: customCamPhysModel = "";
			case 2: customDroneModel = "";
			case 3: customDronePhysModel = "";
		}
	}
}

/**
* Reads the given file and extracts the custom rotation parameters.
*
* @param file				file to extract the rotation parameters from.
* @param isDrone			whether the parameters are for a drone or a camera.
*/
public void SetCustomRotation(File file, bool isDrone)
{
	char line[512];
	while (file.ReadLine(line, sizeof(line)))
	{
		int i = 0;
		if (StrContains(line, "x=", false) == 0)
			ReplaceString(line, sizeof(line), "x=", "", false);
		else if (StrContains(line, "y=", false) == 0)
		{
			ReplaceString(line, sizeof(line), "y=", "", false);
			i = 1;
		}
		else if (StrContains(line, "z=", false) == 0)
		{
			ReplaceString(line, sizeof(line), "z=", "", false);
			i = 2;
		}
		else if (StrContains(line, "}", false) == 0)
			return;
		ReplaceString(line, sizeof(line), "\n", "", false);
		if (isDrone)
		{
			customDroneModelRot[i] = StringToFloat(line);
			PrintToServer("Drone rotation: %i: %f", i, customDroneModelRot[i]);
		}
		else
		{
			customCamModelRot[i] = StringToFloat(line);
			PrintToServer("Camera rotation: %i: %f", i, customCamModelRot[i]);
		}
	}
}

/**
* Tries to precache the given model.
* If the model cannot precache, it means it is invalid.
*
* @param model				model name.
* @return					true if the model could be precached, false otherwise.
*/
public bool TryPrecacheCamModel(char[] model)
{
	int result = PrecacheModel(model);
	if (result < 1)
	{
		PrintToServer("Error precaching custom model '%s'. Falling back to default", model);
		return false;
	}
	PrintToServer("Successfully precached custom model '%s'", model);
	return true;
}

/**
* displays an overlay to the client.
*
* @param client_index			index of the client.
* @param file index				file to display.
*/
public void DisplayOverlay(int client_index, char[] file)
{
	if (IsValidClient(client_index))
		ClientCommand(client_index, "r_screenoverlay \"%s.vtf\"", file);
}

/**
* clears all overlays for the specified client.
*
* @param client_index			index of the client.
*/
public void ClearOverlay(int client_index)
{
	if (IsValidClient(client_index))
		ClientCommand(client_index, "r_screenoverlay \"\"");
}
