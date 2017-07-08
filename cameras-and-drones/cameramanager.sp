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


ArrayList camerasList;
bool isClientInCam[MAXPLAYERS + 1];
int fakePlayersList[MAXPLAYERS + 1];

public void CreateCamera(int client_index, float pos[3], float rot[3], char modelName[PLATFORM_MAX_PATH])
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


public void TpToCam(int client_index, int cam)
{
	isClientInCam[client_index] = true;
	if (fakePlayersList[client_index] < 1)
		CreateFakePlayer(client_index);
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
}

public void CreateFakePlayer(int client_index)
{
	fakePlayersList[client_index] = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(fakePlayersList[client_index])) {
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(client_index, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		SetEntityModel(fakePlayersList[client_index], modelName);
		SetEntPropEnt(fakePlayersList[client_index], Prop_Send, "m_hOwnerEntity", client_index);
		
		float pos[3], rot[3];
		GetEntPropVector(client_index, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(client_index, Prop_Send, "m_angRotation", rot);
		TeleportEntity(fakePlayersList[client_index], pos, rot, NULL_VECTOR);
		
		DispatchSpawn(fakePlayersList[client_index]);
		ActivateEntity(fakePlayersList[client_index]);
		
		// Set animation
		
	}
}

public void ExitCam(int client_index)
{
	isClientInCam[client_index] = false;
	SetViewModel(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_WALK);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmit);
	
	float pos[3], rot[3];
	GetEntPropVector(fakePlayersList[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersList[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	
	RemoveEdict(fakePlayersList[client_index]);
	fakePlayersList[client_index] = -1;
}