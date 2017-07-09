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
#include <csgocolors>


#pragma newdecls required;

#include "cameras-and-drones/menus.sp"
#include "cameras-and-drones/init.sp"


/*  New in this version
*	First release!
*
*/

#define VERSION "0.1.0"
#define PLUGIN_NAME "Cameras and Drones",

bool lateload;

int clientsViewmodels[MAXPLAYERS + 1];

char gearWeapon[] = "weapon_tagrenade";

public Plugin myinfo =
{
	name = PLUGIN_NAME
	author = "Keplyx",
	description = "CSGO plugin adding cameras and drones to the game.",
	version = VERSION,
	url = "https://github.com/Keplyx/cameras-and-drones"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateload = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	
	AddNormalSoundHook(NormalSoundHook);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	CreateConVars(VERSION);
	RegisterCommands();
	
	collisionOffsets = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
			OnClientPostAdminCheck(i);
	}
	
	if (lateload)
		ServerCommand("mp_restartgame 1");
}

public void OnMapStart()
{
	//PrecacheModel("models/props/cs_assault/camera.mdl", true);
}

public void OnConfigsExecuted()
{
	IntiCvars();
}

public void OnClientPostAdminCheck(int client_index)
{
	SDKHook(client_index, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
}

public void OnClientDisconnect(int client_index)
{
	if (activeCam[client_index][0] != -1)
		CloseCamera(client_index);
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	camerasList = new ArrayList();
	OwnersList = new ArrayList();
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		activeCam[i][0] = -1;
		activeCam[i][1] = -1;
		fakePlayersList[i] = -1;
	}
}

public Action NormalSoundHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
	if (IsValidEntity(entity))
	{
		if (StrContains(sample, "sensor") != -1)
			return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void Hook_OnPostThinkPost(int entity_index)
{
	if (IsValidClient(entity_index) && activeCam[entity_index][0] != -1)
	{
		SetViewModel(entity_index, false);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	clientsViewmodels[client_index] = GetViewModelIndex(client_index);
}

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

public void OnEntityCreated(int entity_index, const char[] classname)
{
	if (StrEqual(classname, "tagrenade_projectile", false))
	{
		SDKHook(entity_index, SDKHook_Spawn, OnEntitySpawned);
	}
}

public void OnEntitySpawned (int entity_index)
{
	// DO not hook flash
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][1] == entity_index)
			return;
	}
	SDKHook(entity_index, SDKHook_StartTouch, StartTouchGrenade);
}  



public Action StartTouchGrenade(int entity1, int entity2)
{
	if (IsValidEdict(entity1))
	{
		float pos[3], rot[3];
		GetEntPropVector(entity1, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(entity1, Prop_Send, "m_angRotation", rot);
		int owner = GetEntPropEnt(entity1, Prop_Send, "m_hOwnerEntity");
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(entity1, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		RemoveEdict(entity1);
		
		if (GetClientTeam(owner) == cvar_camteam.IntValue)
			CreateCamera(owner, pos, rot, modelName);
	}
}

public Action BuyGear(int client_index, int args) //Set player skin if authorized
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		BuyCamera(client_index);
	
	return Plugin_Handled;
}

public void BuyCamera(int client_index)
{
	int money = GetEntProp(client_index, Prop_Send, "m_iAccount");
	if (cvar_camprice.IntValue > money)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>Not enough money</font>");
		return;
	}
	SetEntProp(client_index, Prop_Send, "m_iAccount", money - cvar_camprice.IntValue);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>You just bought a camera</font>");
}

public Action OpenGear(int client_index, int args) //Set player skin if authorized
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		OpenCamera(client_index);
	
	return Plugin_Handled;
}

public void OpenCamera(int client_index)
{
	if (!(GetEntityFlags(client_index) & FL_ONGROUND))
	{
		PrintHintText(client_index, "<font color='#ff0000' size='25'>Cannot use cameras while jumping</font>");
		return;
	}
	if (camerasList.Length == 0)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>No cameras available</font>");
		return;
	}
	int owner;
	int target = -1;
	for (int i = 0; i < camerasList.Length; i++)
	{
		if (IsValidEntity(i) && IsValidClient(client_index))
		{
			owner = GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity");
			if (owner == client_index)
			{
				target = i;
				break;
			}
		}
	}
	if (target == -1)
		target = camerasList.Get(0);
	
	Menu_Cameras(client_index, camerasList.FindValue(target));
	TpToCam(client_index, target);
}



public Action OnPlayerRunCmd(int client_index, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsPlayerAlive(client_index))
		return Plugin_Continue;
	
	if (buttons & IN_USE)
	{
		int target = GetClientAimTarget(client_index, false);
		int i = camerasList.FindValue(target);
		if (i != -1 && OwnersList.Get(i) == client_index)
			PickupGear(client_index, i);
	}
	
	if (activeCam[client_index][0] != -1)
	{
		//Disable knife cuts
		float fUnlockTime = GetGameTime() + 1.0;
		SetEntPropFloat(client_index, Prop_Send, "m_flNextAttack", fUnlockTime);
		
		if (buttons & IN_DUCK)
		{
			buttons &= ~IN_DUCK;
			
		}
	}
	return Plugin_Changed;
}

public void PickupGear(int client_index, int i)
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		PickupCamera(client_index, camerasList.Get(i));
}

public void PickupCamera(int client_index, int cam)
{
	DestroyCamera(cam);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>Camera recovered</font>");
}

stock bool IsValidClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client))
	{
		return false;
	}
	return IsClientInGame(client);
}

public void SetViewModel(int client_index, bool enabled)
{
	int EntEffects = GetEntProp(clientsViewmodels[client_index], Prop_Send, "m_fEffects");
	if (enabled)
		EntEffects |= ~32;
	else
		EntEffects |= 32; // Set to Nodraw
	SetEntProp(clientsViewmodels[client_index], Prop_Send, "m_fEffects", EntEffects);
}

public Action Hook_SetTransmit(int entity, int client)
{
	if (client != entity && IsValidClient(entity) && activeCam[entity][0] != -1)
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Hook_SetTransmitCamera(int entity, int client)
{
	if (IsValidClient(client) && activeCam[client][0] == entity)
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public void CloseCamera(int client_index)
{
	ExitCam(client_index);
	activeCam[client_index][0] = -1;
	if (playerMenus[client_index] != null)
	{
		delete playerMenus[client_index];
	}
}