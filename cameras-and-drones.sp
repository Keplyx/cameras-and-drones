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

#include "cameras-and-drones/dronemanager.sp"
#include "cameras-and-drones/menus.sp"
#include "cameras-and-drones/init.sp"


/*  New in this version
*	First release!
*
*/

#define VERSION "0.1.0"
#define PLUGIN_NAME "Cameras and Drones",

#define HIDEHUD_WEAPONSELECTION ( 1<<0 ) // Hide ammo count & weapon selection

bool lateload;

int clientsViewmodels[MAXPLAYERS + 1];

char gearWeapon[] = "weapon_tagrenade";
int collisionOffsets;

int boughtGear[MAXPLAYERS + 1];

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
	InitVars();
	AddNormalSoundHook(NormalSoundHook);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	AddCommandListener(CommandDrop, "drop"); 
	
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

public int GetCollOffset()
{
	return collisionOffsets;
}

public void OnMapStart()
{
	PrecacheModel(InCamModel, true);
	PrecacheModel("models/props/de_inferno/hr_i/ground_stone/ground_stone.mdl", true);
}

public void OnConfigsExecuted()
{
	IntiCvars();
}

public void OnClientPostAdminCheck(int client_index)
{
	// Nothing yet
}

public void OnClientDisconnect(int client_index)
{
	if (activeCam[client_index][0] > MAXPLAYERS)
		CloseCamera(client_index);
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	InitVars();
}

public void InitVars()
{
	camerasList = new ArrayList();
	camOwnersList = new ArrayList();
	dronesList = new ArrayList();
	dronesModelList = new ArrayList();
	dronesOwnerList = new ArrayList();
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		activeCam[i][0] = -1;
		activeCam[i][1] = -1;
		activeDrone[i][0] = -1;
		activeDrone[i][1] = -1;
		fakePlayersListCamera[i] = -1;
		fakePlayersListDrones[i] = -1;
		boughtGear[i] = 0;
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
	if (StrEqual(classname, "weapon_tagrenade", false))
	{
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(entity_index, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		if (StrEqual(modelName, "models/weapons/w_eq_sensorgrenade_dropped.mdl", false)) 
			RemoveEdict(entity_index);
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
		else if (GetClientTeam(owner) > 1)
			CreateDrone(owner, pos, rot, "models/props/de_inferno/hr_i/ground_stone/ground_stone.mdl");
	}
}

public Action BuyGear(int client_index, int args) //Set player skin if authorized
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		BuyCamera(client_index);
	else if (GetClientTeam(client_index) > 1)
		BuyDrone(client_index);
	
	return Plugin_Handled;
}

public void BuyCamera(int client_index)
{
	if (boughtGear[client_index] >= 1)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>You already bought a camera</font>");
		return;
	}
	int money = GetEntProp(client_index, Prop_Send, "m_iAccount");
	if (cvar_camprice.IntValue > money)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>Not enough money</font>");
		return;
	}
	SetEntProp(client_index, Prop_Send, "m_iAccount", money - cvar_camprice.IntValue);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>You just bought a camera</font>");
	boughtGear[client_index]++;
}

public void BuyDrone(int client_index)
{
	if (boughtGear[client_index] >= 1)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>You already bought a drone</font>");
		return;
	}
	int money = GetEntProp(client_index, Prop_Send, "m_iAccount");
	if (cvar_droneprice.IntValue > money)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>Not enough money</font>");
		return;
	}
	SetEntProp(client_index, Prop_Send, "m_iAccount", money - cvar_droneprice.IntValue);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>You just bought a drone</font>");
	boughtGear[client_index]++;
}

public Action OpenGear(int client_index, int args) //Set player skin if authorized
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		OpenCamera(client_index);
	else if (GetClientTeam(client_index) > 1)
		OpenDrone(client_index);
	
	return Plugin_Handled;
}

public void OpenCamera(int client_index)
{
	if (activeCam[client_index][0] != -1)
	{
		CloseGear(client_index);
		return;
	}
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

public void OpenDrone(int client_index)
{
	if (activeDrone[client_index][0] != -1)
	{
		CloseGear(client_index);
		return;
	}
	if (!(GetEntityFlags(client_index) & FL_ONGROUND))
	{
		PrintHintText(client_index, "<font color='#ff0000' size='25'>Cannot use drones while jumping</font>");
		return;
	}
	if (dronesList.Length == 0)
	{
		PrintHintText(client_index, "<font color='#ff0000' size='30'>No drones available</font>");
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
		PrintHintText(client_index, "<font color='#ff0000' size='30'>No drones available</font>");
		return;
	}
	
	TpToDrone(client_index, target);
}

public Action OnPlayerRunCmd(int client_index, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsPlayerAlive(client_index))
		return Plugin_Continue;
	
	if (buttons & IN_USE)
	{
		int target = GetClientAimTarget(client_index, false);
		int cam = camerasList.FindValue(target);
		int drone = dronesList.FindValue(target);
		if (cam != -1 && camOwnersList.Length > 0 && camOwnersList.Get(cam) == client_index)
			PickupGear(client_index, cam);
		else if (drone  != -1 && dronesOwnerList.Length > 0 && dronesOwnerList.Get(drone) == client_index)
			PickupGear(client_index, drone);
	}
	
	if (activeCam[client_index][0] != -1 || activeDrone[client_index][0] != -1)
	{
		//Disable knife cuts
		float fUnlockTime = GetGameTime() + 1.0;
		SetEntPropFloat(client_index, Prop_Send, "m_flNextAttack", fUnlockTime);
		
		if (buttons & IN_DUCK)
		{
			buttons &= ~IN_DUCK;
			CloseGear(client_index);
		}
		if (buttons & IN_USE)
		{
			buttons &= ~IN_USE;
		}
	}
	else if (buttons & IN_ATTACK) // Stop player from throwing the gear too far
	{
		int weapon_index = GetEntPropEnt(client_index, Prop_Send, "m_hActiveWeapon");
		char weapon_name[64];
		GetEntityClassname(weapon_index, weapon_name, sizeof(weapon_name))
		if (StrEqual(weapon_name, gearWeapon, false))
		{
			buttons &= ~IN_ATTACK;
			buttons |= IN_ATTACK2;
		}
	}
	
	if (activeDrone[client_index][0] != -1)
	{
		if (buttons & IN_FORWARD)
		{
			vel[0] = 0.0;
			vel[1] = 0.0;
			vel[2] = 0.0;
			isDroneMoving[client_index] = true;
			MoveDrone(client_index, activeDrone[client_index][0]);
		}
		else if (buttons & IN_SPEED)
			isDroneMoving[client_index] = true;
		else
			isDroneMoving[client_index] = false;
		if (buttons & IN_JUMP)
		{
			JumpDrone(client_index, activeDrone[client_index][0]);
		}
		if ((buttons & IN_BACK) || (buttons & IN_MOVELEFT) || (buttons & IN_MOVERIGHT))
		{
			vel[0] = 0.0;
			vel[1] = 0.0;
			vel[2] = 0.0;
		}
	}
	
	return Plugin_Changed;
}

public void PickupGear(int client_index, int i)
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		PickupCamera(client_index, camerasList.Get(i));
	else if (GetClientTeam(client_index) > 1)
		PickupDrone(client_index, dronesList.Get(i));
}

public void PickupCamera(int client_index, int cam)
{
	DestroyCamera(cam);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>Camera recovered</font>");
}

public void PickupDrone(int client_index, int cam)
{
	DestroyDrone(cam);
	GivePlayerItem(client_index, gearWeapon);
	PrintHintText(client_index, "<font color='#0fff00' size='25'>Drone recovered</font>");
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

public Action Hook_SetTransmitPlayer(int entity, int client) // hide player only if using cam/drone
{
	if (client != entity && IsValidClient(entity) && (activeCam[entity][0] != -1 || activeDrone[client][0] != -1))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Hook_SetTransmitGear(int entity, int client) // Hide cam/drone only to the one using it
{
	if (IsValidClient(client) && ((activeCam[client][0] == entity || activeCam[client][1] == entity) || (activeDrone[client][0] == entity || activeDrone[client][1] == entity)))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public void CloseGear(int client_index)
{
	if (GetClientTeam(client_index) == cvar_camteam.IntValue)
		CloseCamera(client_index);
	else if (GetClientTeam(client_index) > 1)
		CloseDrone(client_index);
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

public void CloseDrone(int client_index)
{
	ExitDrone(client_index);
}

void RemoveHealth(int client_index, float damage, int attacker, int damagetype, char[] weapon)
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

public Action Hook_TakeDamageFakePlayer(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	int owner = GetEntPropEnt(victim, Prop_Send, "m_hOwnerEntity");
	char weapon[64];
	GetClientWeapon(attacker, weapon, sizeof(weapon))
	RemoveHealth(owner, damage, attacker, damagetype, weapon);
}

public void CreateFakePlayer(int client_index, bool isCam)
{
	int fake = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(fake)) {
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(client_index, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		SetEntityModel(fake, modelName);
		SetEntPropEnt(fake, Prop_Send, "m_hOwnerEntity", client_index);
		
		float pos[3], rot[3];
		GetEntPropVector(client_index, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(client_index, Prop_Send, "m_angRotation", rot);
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

public void HideHudGuns(int client_index)
{
	SetEntProp(client_index, Prop_Send, "m_iHideHUD", HIDEHUD_WEAPONSELECTION);
}

public Action Hook_WeaponCanUse(int client_index, int weapon_index)  
{
	return Plugin_Handled;
}

public Action CommandDrop(int client_index, const char[] command, int argc)
{
	if (activeCam[client_index][0] != -1 || activeDrone[client_index][0] != -1)
		return Plugin_Handled;
	return Plugin_Continue;
}