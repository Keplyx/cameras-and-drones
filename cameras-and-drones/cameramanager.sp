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

#include <sdktools>
#include <sdkhooks>

char InCamModel[] = "models/chicken/festive_egg.mdl";

ArrayList camerasList;
ArrayList camOwnersList;
int activeCam[MAXPLAYERS + 1][2];
int fakePlayersListCamera[MAXPLAYERS + 1];

int oldCollisionValue[MAXPLAYERS + 1];

public void AddCamera(int cam, int client_index)
{
	camerasList.Push(cam);
	camOwnersList.Push(client_index);
}

public void RemoveCameraFromList(int cam)
{
	int i = camerasList.FindValue(cam);
	if (i < 0)
		return;
	camerasList.Erase(i);
	camOwnersList.Erase(i);
}

public void CreateCamera(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
{
	int cam = CreateEntityByName("prop_dynamic_override"); // replace by tagrenade_projectile when using it (makes a flash)
	if (IsValidEntity(cam)) {
		SetEntityModel(cam, modelName);
		DispatchKeyValue(cam, "solid", "6");
		DispatchSpawn(cam);
		TeleportEntity(cam, pos, rot, NULL_VECTOR);
		
		SDKHook(cam, SDKHook_OnTakeDamage, Hook_TakeDamageCam);
		SDKHook(cam, SDKHook_SetTransmit, Hook_SetTransmitGear);
		AddCamera(cam, client_index);
	}
}

public void CreateFlash(int client_index, int cam)
{
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][0] == cam && i != client_index)
		{
			activeCam[client_index][1] = activeCam[i][1];
			return; // Prevent from creating multiple red flashes
		}
	}
	int flash = CreateEntityByName("tagrenade_projectile");
	if (IsValidEntity(flash)) {
		activeCam[client_index][1] = flash;
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(cam, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		SetEntityModel(flash, modelName);
		DispatchKeyValue(flash, "solid", "0");
		
		DispatchSpawn(flash);
		ActivateEntity(flash);
		
		SetEntityMoveType(flash, MOVETYPE_NONE);
		
		float pos[3], rot[3];
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(cam, Prop_Send, "m_angRotation", rot);
		
		TeleportEntity(flash, pos, rot, NULL_VECTOR);
		
		SDKHook(flash, SDKHook_OnTakeDamage, Hook_TakeDamageCam);
		SDKHook(flash, SDKHook_SetTransmit, Hook_SetTransmitGear);
	}
}

public void DestroyFlash(int client_index)
{
	if (IsValidEntity(activeCam[client_index][1]))
	{
		RemoveEdict(activeCam[client_index][1])
		activeCam[client_index][1] = -1;
	}
}


public void TpToCam(int client_index, int cam)
{
	if (fakePlayersListCamera[client_index] < 1)
		CreateFakePlayer(client_index, true);
	
	SetEntityModel(client_index, InCamModel); // Set to a small model to prevent collisions/shots
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	//SetEntityRenderMode(client_index, RENDER_NONE);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 0.0);
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	
	float pos[3], absPos[3], eyePos[3];
	GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
	GetClientAbsOrigin(client_index, absPos);
	GetClientEyePosition(client_index, eyePos);
	pos[2] -= eyePos[2] - absPos[2];
	TeleportEntity(client_index, pos, NULL_VECTOR, NULL_VECTOR);
	oldCollisionValue[client_index] = GetEntData(client_index, GetCollOffset(), 1);
	SetEntData(client_index, GetCollOffset(), 2, 4, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 2);
	
	DestroyFlash(client_index);
	CreateFlash(client_index, cam);
}

public void ExitCam(int client_index)
{
	char modelName[PLATFORM_MAX_PATH];
	GetEntPropString(fakePlayersListCamera[client_index], Prop_Data, "m_ModelName", modelName, sizeof(modelName));
	SetEntityModel(client_index, modelName); // Set back to original model
	
	SetViewModel(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_WALK);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	
	float pos[3], rot[3];
	GetEntPropVector(fakePlayersListCamera[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersListCamera[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	SetEntData(client_index, GetCollOffset(), oldCollisionValue[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	
	RemoveEdict(fakePlayersListCamera[client_index]);
	fakePlayersListCamera[client_index] = -1;
	DestroyFlash(client_index);
}

public void DestroyCamera(int cam)
{
	if (IsValidEdict(cam))
		RemoveEdict(cam);
	RemoveCameraFromList(cam);
	
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][0] == cam)
		{
			CloseCamera(i);
		}
	}
}

public Action Hook_TakeDamageCam(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][0] == victim || activeCam[i][1] == victim)
		{
			DestroyCamera(activeCam[i][0]);
			return;
		}
	}
	DestroyCamera(victim);
}
