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

#include "cameras-and-drones/init.sp"


/*  New in this version
*	First release!
*
*/

#define VERSION "0.1.0"
#define PLUGIN_NAME "Cameras and Drones",

bool lateload;

ArrayList camerasList;
bool isClientInCam[MAXPLAYERS + 1];

int clientsViewmodels[MAXPLAYERS + 1];


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
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
			OnClientPostAdminCheck(i);
	}
	
	if (lateload)
		ServerCommand("mp_restartgame 1");
}

public void OnConfigsExecuted()
{
	IntiCvars();
}

public void OnClientPostAdminCheck(int client_index)
{
	SDKHook(client_index, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	camerasList = new ArrayList();
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		isClientInCam[i] = false;
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
	if (IsValidClient(entity_index))
	{
		SetViewModel(entity_index, !isClientInCam[entity_index]);
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
		SDKHook(entity_index, SDKHook_StartTouch, StartTouchGrenade);
	}
}

public Action StartTouchGrenade(int entity1, int entity2)
{
	if (IsValidEdict(entity1))
	{
		float pos[3];
		float rot[3];
		GetEntPropVector(entity1, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(entity1, Prop_Send, "m_angRotation", rot);
		int owner = GetEntPropEnt(entity1, Prop_Send, "m_hOwnerEntity");
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(entity1, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		RemoveEdict(entity1);
		CreateCamera(owner, pos, rot, modelName);
	}
}

void CreateCamera(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
{
	int cam = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(cam)) {
		SetEntityModel(cam, modelName);
		
		SetEntPropEnt(cam, Prop_Send, "m_hOwnerEntity", client_index);
		TeleportEntity(cam, pos, rot, NULL_VECTOR);
		// Disable collisions
		DispatchKeyValue(cam, "solid", "0");
		
		DispatchSpawn(cam);
		ActivateEntity(cam);
		camerasList.Push(cam);
	}
}

public Action BuyGear(int client_index, int args) //Set player skin if authorized
{
	GivePlayerItem(client_index, "weapon_tagrenade");
	PrintHintText(client_index, "You just bought a camera");
	return Plugin_Handled;
}

public Action OpenCamera(int client_index, int args) //Set player skin if authorized
{
	if (camerasList.Length == 0)
	{
		PrintHintText(client_index, "No cameras available");
		return Plugin_Handled;
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
	
	isClientInCam[client_index] = true;
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	//SetEntityRenderMode(client_index, RENDER_NONE);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 0.0);
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	float pos[3], absPos[3], eyePos[3];
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
	GetClientAbsOrigin(client_index, absPos);
	GetClientEyePosition(client_index, eyePos);
	pos[2] -= eyePos[2] - absPos[2];
	TeleportEntity(client_index, pos, NULL_VECTOR, NULL_VECTOR);
	return Plugin_Handled;
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

public Action OnPlayerRunCmd(int client_index, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsPlayerAlive(client_index))
		return Plugin_Continue;
	
	if (isClientInCam[client_index])
	{
		if (buttons & IN_DUCK)
		{
			buttons &= ~IN_DUCK;
			return Plugin_Continue;
		}
		//Disable knife cuts
		float fUnlockTime = GetGameTime() + 1.0;
		SetEntPropFloat(client_index, Prop_Send, "m_flNextAttack", fUnlockTime);
	}
	return Plugin_Changed;
}

stock bool IsValidClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client))
	{
		return false;
	}
	return IsClientInGame(client);
}

public Action Hook_SetTransmit(int entity, int client) 
{ 
    if (client != entity && IsValidClient(entity) && isClientInCam[entity]) 
        return Plugin_Handled; 
     
    return Plugin_Continue; 
}  