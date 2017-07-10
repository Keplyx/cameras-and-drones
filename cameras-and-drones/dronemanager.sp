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

ArrayList dronesList;
ArrayList dronesOwnerList;
int activeDrone[MAXPLAYERS + 1][2];
int fakePlayersListDrones[MAXPLAYERS + 1];

int oldCollisionValueD[MAXPLAYERS + 1];

public void AddDrone(int drone, int client_index)
{
	dronesList.Push(drone);
	dronesOwnerList.Push(client_index);
}

public void RemoveDroneFromList(int drone)
{
	int i = dronesList.FindValue(drone);
	if (i < 0)
		return;
	dronesList.Erase(i);
	dronesOwnerList.Erase(i);
}

public void CreateDrone(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
{
	int drone = CreateEntityByName("prop_physics_override"); // replace by tagrenade_projectile when using it (makes a flash)
	if (IsValidEntity(drone)) {
		SetEntityModel(drone, modelName);
		DispatchKeyValue(drone, "solid", "6");
		DispatchSpawn(drone);
		TeleportEntity(drone, pos, rot, NULL_VECTOR);
		
		SDKHook(drone, SDKHook_OnTakeDamage, Hook_TakeDamageDrone);
		SDKHook(drone, SDKHook_SetTransmit, Hook_SetTransmitGear);
		AddDrone(drone, client_index);
	}
}


public void TpToDrone(int client_index, int drone)
{
	if (fakePlayersListDrones[client_index] < 1)
		CreateFakePlayer(client_index, false);
	
	activeDrone[client_index][0] = drone;
	SetEntityModel(client_index, InDroneModel); // Set to a small model to prevent collisions/shots
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 0.0);
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	
	float pos[3], absPos[3], eyePos[3];
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", pos);
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
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	
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
