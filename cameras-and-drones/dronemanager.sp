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

float droneEyePosOffset = 5.0;
float droneHoverHeight = 10.0;
float droneSpeed = 200.0;
float droneJumpForce = 300.0;

bool isDroneGrounded[MAXPLAYERS + 1];
bool isDroneMoving[MAXPLAYERS + 1];

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

public void CreateDrone(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
{
	// Can be moved, must have a larger hitbox than the drone model (no stuck, easier pickup, easier target)
	int drone = CreateEntityByName("prop_physics_override"); 
	if (IsValidEntity(drone)) {
		SetEntityModel(drone, modelName);
		DispatchKeyValue(drone, "solid", "6");
		//DispatchKeyValue(drone, "overridescript", "mass,100.0,inertia,1.0,damping,1.0,rotdamping ,1.0"); // overwrite params
		DispatchKeyValue(drone, "overridescript", "rotdamping,1000.0"); // Prevent drone rotation
		DispatchSpawn(drone);
		ActivateEntity(drone);
		TeleportEntity(drone, pos, rot, NULL_VECTOR);
		
		SDKHook(drone, SDKHook_OnTakeDamage, Hook_TakeDamageDrone);
		SetEntityRenderMode(drone, RENDER_NONE);
		CreateDroneModel(client_index, drone);
	}
}

public void CreateDroneModel(int client_index, int drone)
{
	// This one can be animated/move with player
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

public void MoveDrone(int client_index, int drone)
{
	if (isDroneGrounded[client_index])
	{
		float vel[3], rot[3];
		GetClientEyeAngles(client_index, rot);
		rot[0] = 0.0;
		GetAngleVectors(rot, vel, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vel, droneSpeed);
		TeleportEntity(drone, NULL_VECTOR, NULL_VECTOR, vel);
	}
}

public void JumpDrone(int client_index, int drone)
{
	if (isDroneGrounded[client_index])
	{
		float vel[3], rot[3];
		GetClientEyeAngles(client_index, rot);
		if (rot[0] > -45.0)
			rot[0] = -45.0;
		GetAngleVectors(rot, vel, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vel, droneJumpForce);
		TeleportEntity(drone, NULL_VECTOR, NULL_VECTOR, vel);
	}
}

public void Hook_PostThinkDrone(int client_index)
{
	if (activeDrone[client_index][0] < 0)
		return
	int drone = activeDrone[client_index][0];
	float groundDistance = DistanceToGround(drone);
	
	LowerDroneView(client_index);
	HideHudGuns(client_index);
	SetViewModel(client_index, false);
	
	if (groundDistance > (droneHoverHeight + 1.0))
	{
		isDroneGrounded[client_index] = false;
		return;
	}
	isDroneGrounded[client_index] = true;
	if (!isDroneMoving[client_index])
		return;
	
	
	float pos[3], nullRot[3];
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", pos);
	pos[2] += droneHoverHeight - groundDistance;
	TeleportEntity(drone, pos, nullRot, NULL_VECTOR);
}

public void LowerDroneView(int client_index)
{
	float viewPos[3];
	viewPos[2] = droneEyePosOffset;
	SetEntPropVector(client_index, Prop_Data, "m_vecViewOffset", viewPos);
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
	// Allow for drone to drone switch
	if (fakePlayersListDrones[client_index] < 1)
		CreateFakePlayer(client_index, false);
	if (activeDrone[client_index][1] > MAXPLAYERS)
	{
		SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", activeDrone[client_index][0], activeDrone[client_index][1], 0);
		float pos[3], rot[3];
		TeleportEntity(activeDrone[client_index][1], pos, rot, NULL_VECTOR);
	}
	// Set active
	activeDrone[client_index][0] = drone;
	activeDrone[client_index][1] = dronesModelList.Get(dronesList.FindValue(drone));
	// Set appearance
	SetEntityModel(client_index, InDroneModel); // Set to a small model to prevent collisions/shots
	SetGearScreen(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	// Hooks
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKHook(client_index, SDKHook_PostThink, Hook_PostThinkDrone);
	// Set pos
	SetVariantString("!activator"); AcceptEntityInput(client_index, "SetParent", drone, client_index, 0);
	SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", client_index, activeDrone[client_index][1], 0);
	float pos[3], rot[3];
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	rot[1] = 90.0;
	TeleportEntity(activeDrone[client_index][1] , pos, rot, NULL_VECTOR);
	// Set collisions
	oldCollisionValueD[client_index] = GetEntData(client_index, GetCollOffset(), 1);
	SetEntData(client_index, GetCollOffset(), 2, 4, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 2);
}

public void ExitDrone(int client_index)
{
	// Set appearance
	char modelName[PLATFORM_MAX_PATH];
	GetEntPropString(fakePlayersListDrones[client_index], Prop_Data, "m_ModelName", modelName, sizeof(modelName));
	SetEntityModel(client_index, modelName); // Set back to original model
	SetGearScreen(client_index, false);
	SetViewModel(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_WALK);
	// Hooks
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKUnhook(client_index, SDKHook_PostThink, Hook_PostThinkDrone);
	// Set pos
	AcceptEntityInput(client_index, "SetParent");
	SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", activeDrone[client_index][0], activeDrone[client_index][1], 0);
	float pos[3], rot[3];
	TeleportEntity(activeDrone[client_index][1], pos, rot, NULL_VECTOR);
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	// Set collisions
	SetEntData(client_index, GetCollOffset(), oldCollisionValueD[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	// Clear stuff
	RemoveEdict(fakePlayersListDrones[client_index]);
	fakePlayersListDrones[client_index] = -1;
	activeDrone[client_index][0] = -1;
	activeDrone[client_index][1] = -1;
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
