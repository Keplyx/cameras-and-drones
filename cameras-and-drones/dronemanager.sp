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

float boxMax[3] = {10.0, 10.0, 5.0};
float boxMin[3] = {-10.0, -10.0, -5.0};

float droneBoxMax = 16.0;
float droneGroundMax = 1.0;

float droneEyePosOffset = 10.0;
float droneSpeed = 200.0;
float droneJumpForce = 150.0;
float droneFallSpeed = 300.0;

bool isDroneGrounded[MAXPLAYERS + 1];
bool isDroneMoving[MAXPLAYERS + 1];

float lastVelInput[MAXPLAYERS + 1][3];

float airTime = -1.0;
Handle airTimeTimer = INVALID_HANDLE;

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
	int drone = CreateEntityByName("prop_dynamic_override"); 
	if (IsValidEntity(drone)) {
		SetEntityModel(drone, droneModel);
		DispatchKeyValue(drone, "solid", "6");
		DispatchSpawn(drone);
		ActivateEntity(drone);
		
		TeleportEntity(drone, pos, rot, NULL_VECTOR);
		SDKHook(drone, SDKHook_OnTakeDamage, Hook_TakeDamageDrone);
		//SDKHook(drone, SDKHook_SetTransmit, Hook_SetTransmitGear);
		
		AddDrone(drone, drone, client_index);
	}
}

public void MoveDrone(int client_index)
{
	if (isDroneGrounded[client_index])
	{
		float vel[3], rot[3];
		GetClientEyeAngles(client_index, rot);
		rot[0] = 0.0;
		GetAngleVectors(rot, vel, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vel, droneSpeed);
		TeleportEntity(client_index, NULL_VECTOR, NULL_VECTOR, vel);
		lastVelInput[client_index] = vel;
	}
}

public void JumpDrone(int client_index)
{
	if (isDroneGrounded[client_index])
	{
		float vel[3], rot[3];
		GetClientEyeAngles(client_index, rot);
		PrintToChatAll("%f", rot[0])
//		if (rot[0] > -45.0)
//			rot[0] = -45.0;
		GetAngleVectors(rot, vel, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vel, droneJumpForce);
		TeleportEntity(client_index, NULL_VECTOR, NULL_VECTOR, vel);
		lastVelInput[client_index] = vel;
	}
}

public void Hook_PostThinkDrone(int client_index)
{
	if (activeDrone[client_index][0] < 0)
		return
	
	LowerDroneView(client_index);
	HideHudGuns(client_index);
	SetViewModel(client_index, false);
	
	float pos[3], ang[3];
	GetEntPropVector(client_index, Prop_Send, "m_vecOrigin", pos);
	ang[0] = 90.0; ang[1] = 0.0; ang[2] = 0.0;  // points to the ground
	//ang[0] == 90.0 && ang[1] == 0.0 && ang[2] == 0.0 >>>>>>>> checkGround
	CheckDirection(client_index, pos, ang, true);
	pos[2] += droneEyePosOffset; // Box around eyes: prevent from stopping in slopes
	//CheckBox(client_index, pos);
	PerformFall(client_index);
}

public void PerformFall(int client_index)
{
	if (isDroneGrounded[client_index])
	{
		airTime = -1.0;
		if (airTimeTimer != INVALID_HANDLE)
		{
			KillTimer(airTimeTimer, false);
			airTimeTimer = INVALID_HANDLE;
		}
		return;
	}
	if (airTime < 0.0)
	{
		airTime = 0.0;
		int ref = EntIndexToEntRef(client_index);
		airTimeTimer = CreateTimer(0.1, Timer_IncrementAirTime, ref, TIMER_REPEAT);
		return;
	}
	float vel[3];
	vel = lastVelInput[client_index];
	float step = (droneFallSpeed/5) * airTime;
	vel[2] -= step;
	if (vel[2] < droneFallSpeed)
		vel[2] = -droneFallSpeed;
	
	PrintToServer("---------------------------");
	PrintToServer("airTime: %f", airTime);
	PrintToServer("step: %f", step);
	PrintToServer("vel[2]: %f", vel[2]);
	TeleportEntity(client_index, NULL_VECTOR, NULL_VECTOR, vel);
}

public Action Timer_IncrementAirTime(Handle timer, any ref)
{
	airTime += 0.1;
}

public void CheckBox(int client_index, float pos[3])
{
	Handle traceHull = TR_TraceHullFilterEx(pos, pos, boxMin, boxMax, MASK_ALL, TraceFilterIgnorePlayers, client_index)
	if (traceHull != INVALID_HANDLE && TR_DidHit(traceHull))
	{
		float vel[3];
		//GetEntPropVector(client_index, Prop_Data, "m_vecVelocity", vel);
		for (int i = 0; i < sizeof(vel); i++)
		{
			vel[i] = -3* lastVelInput[client_index][i];
		}
		TeleportEntity(client_index, NULL_VECTOR, NULL_VECTOR, vel);
	}
	CloseHandle(traceHull)
}

public void CheckDirection(int client_index, float pos[3], float ang[3], bool checkGround)
{
	Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_ALL, RayType_Infinite, TraceFilterIgnorePlayers, client_index);
	if (trace != INVALID_HANDLE && TR_DidHit(trace))
	{
		float endPos[3], dir[3];
		float dist, offset;
		TR_GetEndPosition(endPos, trace);
		GetAngleVectors(ang, dir, NULL_VECTOR, NULL_VECTOR)
		for (int i = 0; i < sizeof(dir); i++)
		{
			if (dir[i] > 0.1 || dir[i] < -0.1)
			{
				dist = FloatAbs(FloatAbs(endPos[i]) - FloatAbs(pos[i]));
				if (checkGround && dist < droneGroundMax)
					offset = FloatAbs(droneGroundMax - dist);
				else if (!checkGround && dist < droneBoxMax)
					offset = FloatAbs(droneBoxMax - dist);
				pos[i] -= offset * dir[i];
				break;
			}
		}
		
		if (checkGround && dist <= (droneGroundMax + 5.0))
			isDroneGrounded[client_index] = true;
		else if (checkGround && dist > (droneGroundMax + 5.0))
			isDroneGrounded[client_index] = false;
		
//		PrintToServer("----------------------------------------------------");
//		PrintToServer("pos: %f %f %f", pos[0], pos[1], pos[2]);
//		PrintToServer("endPos: %f %f %f", endPos[0], endPos[1], endPos[2]);
//		PrintToServer("dir: %f %f %f", dir[0], dir[1], dir[2]);
//		PrintToServer("dist: %f", dist);
//		PrintToServer("offset: %f", offset);
//		PrintToServer("grounded: %b", isDroneGrounded[client_index]);
		
		TeleportEntity(client_index, pos, NULL_VECTOR, NULL_VECTOR);
	}
	CloseHandle(trace)
}

public void LowerDroneView(int client_index)
{
	float viewPos[3];
	viewPos[2] = droneEyePosOffset;
	SetEntPropVector(client_index, Prop_Data, "m_vecViewOffset", viewPos);
}

public bool TraceFilterIgnorePlayers(int entity_index, int mask, any data)
{
	if((entity_index >= 1 && entity_index <= MaxClients) || entity_index == data || entity_index == fakePlayersListDrones[data] || entity_index == activeDrone[data][0] || entity_index == activeDrone[data][1])
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
	SDKHook(client_index, SDKHook_PostThink, Hook_PostThinkDrone);
	
	float pos[3], rot[3];
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", pos);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	rot[1] = 90.0;
	TeleportEntity(activeDrone[client_index][1] , NULL_VECTOR, rot, NULL_VECTOR);
	
	SetVariantString("!activator"); AcceptEntityInput(drone, "SetParent", client_index, drone, 0);
	//SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", client_index, activeDrone[client_index][1], 0);
	
	
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
	SDKUnhook(client_index, SDKHook_PostThink, Hook_PostThinkDrone);
	
	AcceptEntityInput(activeDrone[client_index][0], "SetParent");
	//SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", activeDrone[client_index][0], activeDrone[client_index][1], 0);
	float pos[3], rot[3];
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	SetEntData(client_index, GetCollOffset(), oldCollisionValueD[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	
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
