/*
*   This file is part of droneeras and Drones.
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

#include <sdktools>
#include <sdkhooks>

char InDroneModel[] = "models/chicken/festive_egg.mdl";
char droneModel[] = "models/weapons/w_eq_sensorgrenade_thrown.mdl";

ArrayList dronesList;
ArrayList dronesModelList;
ArrayList dronesOwnerList;
int activeDrone[MAXPLAYERS + 1][2];
int fakePlayersListDrones[MAXPLAYERS + 1];

int oldCollisionValueD[MAXPLAYERS + 1];

float droneHoverHeight = 10.0;
float droneSpeed = 150.0;
public void AddDrone(int drone, int model, int client_index)
{
	dronesList.Push(drone);
	dronesModelList.Push(model);
	dronesOwnerList.Push(client_index);
}

public void RemoveDroneFromList(int drone)
{
	int i = dronesList.FindValue(drone);
	if (i < 0)
		return;
	dronesList.Erase(i);
	dronesModelList.Erase(i);
	dronesOwnerList.Erase(i);
}

public void MoveDrone(int client_index, int drone)
{
	float groundDistance = DistanceToGround(drone)
	if (groundDistance > droneHoverHeight)
		return;
	float vel[3], ang[3], dronePos[3];
	GetEntPropVector(client_index, Prop_Send, "m_angRotation", ang);
	GetAngleVectors(ang, vel, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vel, droneSpeed);
	ang[1] -= 90;
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", dronePos);
	dronePos[2] += droneHoverHeight - groundDistance;
	TeleportEntity(drone, dronePos, ang, vel);
}


public void CreateDrone(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
{
	// Can be moved, must have a larger hitbox than the drone model (no stuck, easier pickup, easier target)
	int drone = CreateEntityByName("prop_physics_override"); 
	if (IsValidEntity(drone)) {
		SetEntityModel(drone, modelName);
		DispatchKeyValue(drone, "solid", "6");
		DispatchSpawn(drone);
		ActivateEntity(drone);
		TeleportEntity(drone, pos, rot, NULL_VECTOR);
		
		SDKHook(drone, SDKHook_OnTakeDamage, Hook_TakeDamageDrone);
		SetEntityRenderMode(drone, RENDER_NONE);
		SDKHook(client_index, SDKHook_PostThinkPost, Hook_PostThinkPostDrone);
		
		CreateDroneModel(client_index, drone);
	}
}

public void CreateDroneModel(int client_index, int drone)
{
	// This one can be animated
	int model = CreateEntityByName("prop_dynamic_override"); 
	if (IsValidEntity(model)) {
		SetEntityModel(model, droneModel);
		DispatchKeyValue(model, "solid", "0");
		DispatchSpawn(model);
		ActivateEntity(model);
		
		SetVariantString("!activator"); AcceptEntityInput(model, "SetParent", drone, model, 0);
		
		float pos[3], rot[3];
		TeleportEntity(model, pos, rot, NULL_VECTOR);
		SDKHook(model, SDKHook_SetTransmit, Hook_SetTransmitGear);
		
		AddDrone(drone, model, client_index);
	}
}

public void Hook_PostThinkPostDrone(int client_index)
{
	if (activeDrone[client_index][0] < 0)
		return
	
	int drone = dronesList.Get(dronesOwnerList.FindValue(client_index));
	float dronePos[3], absPos[3], eyePos[3], ang[3];
	GetEntPropVector(client_index, Prop_Send, "m_angRotation", ang);
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", dronePos);
	GetClientAbsOrigin(client_index, absPos)
	GetClientEyePosition(client_index, eyePos);
	
	dronePos[2] -= eyePos[2] - absPos[2] - 10.0;
	TeleportEntity(client_index, dronePos, NULL_VECTOR, NULL_VECTOR);
}

public float DistanceToGround(int entity_index)
{
	float flPos[3], flAng[3];
	GetEntPropVector(entity_index, Prop_Send, "m_vecOrigin", flPos);
	flAng[0] = 90.0; // points to the ground
	flAng[1] = 0.0;
	flAng[2] = 0.0;
	
	Handle hTrace = TR_TraceRayFilterEx(flPos, flAng, MASK_ALL, RayType_Infinite, TraceFilterIgnorePlayers, entity_index);
	if(hTrace != INVALID_HANDLE && TR_DidHit(hTrace))
	{
		float endPos[3];
		TR_GetEndPosition(endPos, hTrace);
		CloseHandle(hTrace);
		float distance = FloatAbs(endPos[2] - flPos[2])
		return  distance;
	}
	PrintToServer("No end point found!");
	return 999.0;
}

public bool TraceFilterIgnorePlayers(int entity_index, int mask, any data)
{
	if((entity_index >= 1 && entity_index <= MaxClients) || entity_index == data)
	{
		return false;
	}
	return true;
}

public void TpToDrone(int client_index, int drone)
{
	if (fakePlayersListDrones[client_index] < 1)
		CreateFakePlayer(client_index, false);
	
	activeDrone[client_index][0] = drone;
	activeDrone[client_index][1] = dronesModelList.Get(dronesList.FindValue(drone));
	SetEntityModel(client_index, InDroneModel); // Set to a small model to prevent collisions/shots
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	
	float pos[3], absPos[3], eyePos[3];
	GetClientAbsOrigin(client_index, absPos);
	GetClientEyePosition(client_index, eyePos);
	pos[2] -= eyePos[2] - absPos[2];
	TeleportEntity(client_index, pos, NULL_VECTOR, NULL_VECTOR);
	oldCollisionValueD[client_index] = GetEntData(client_index, GetCollOffset(), 1);
	SetEntData(client_index, GetCollOffset(), 2, 4, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 2);
}

public void ExitDrone(int client_index)
{
	char modelName[PLATFORM_MAX_PATH];
	GetEntPropString(fakePlayersListDrones[client_index], Prop_Data, "m_ModelName", modelName, sizeof(modelName));
	SetEntityModel(client_index, modelName); // Set back to original model
	
	SetViewModel(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_WALK);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKUnhook(client_index, SDKHook_PostThinkPost, Hook_PostThinkPostDrone);
	
	float pos[3], rot[3];
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	SetEntData(client_index, GetCollOffset(), oldCollisionValueD[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	
	RemoveEdict(fakePlayersListDrones[client_index]);
	fakePlayersListDrones[client_index] = -1;
}

public void DestroyDrone(int drone)
{
	if (IsValidEdict(drone))
		RemoveEdict(drone);
	if (IsValidEdict(dronesModelList.Get(dronesList.FindValue(drone))))
		RemoveEdict(dronesModelList.Get(dronesList.FindValue(drone)));
	
	RemoveDroneFromList(drone);
	
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeDrone[i][0] == drone)
		{
			CloseDrone(i);
		}
	}
}

public Action Hook_TakeDamageDrone(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	PrintToServer("Damage!");
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeDrone[i][0] == victim || activeDrone[i][1] == victim)
		{
			DestroyDrone(activeDrone[i][0]);
			return;
		}
	}
	DestroyDrone(victim);
}
