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

char droneSound[] = "ambient/tones/fan2_loop.wav";
char droneJumpSound[] = "items/nvg_off.wav";
char openDroneSound[] = "weapons/movement3.wav";
char destroyDroneSound[] = "physics/metal/metal_box_impact_bullet1.wav";

char inDroneModel[] = "models/chicken/festive_egg.mdl"; // must have hitbox or it will use the default player one
char defaultDroneModel[] = "models/weapons/w_eq_sensorgrenade_thrown.mdl";
char defaultDronePhysModel[] = "models/props/de_inferno/hr_i/ground_stone/ground_stone.mdl";

ArrayList dronesList;
ArrayList dronesModelList;
ArrayList dronesOwnerList;
int activeDrone[MAXPLAYERS + 1][2];
int fakePlayersListDrones[MAXPLAYERS + 1];

int oldCollisionValueD[MAXPLAYERS + 1];

float droneEyePosOffset = 5.0;

// Change with cvars
float droneHoverHeight = 5.0;
float droneSpeed = 200.0;
float droneJumpForce = 300.0;
bool useCustomDroneModel = false;
float customDroneModelRot[3];
char customDroneModel[PLATFORM_MAX_PATH];
char customDronePhysModel[PLATFORM_MAX_PATH];

bool isDroneGrounded[MAXPLAYERS + 1];
bool isDroneMoving[MAXPLAYERS + 1];

 /**
 * Add a new drone to the list.
 *
 * @param drone					drone index.
 * @param model					drone model index.
 * @param client_index			owner client index.
 */
public void AddDrone(int drone, int model, int client_index)
{
	dronesList.Push(drone);
	dronesModelList.Push(model);
	dronesOwnerList.Push(client_index);
}

 /**
 * Removes the given drone from the list.
 *
 * @param drone				drone index.
 */
public void RemoveDroneFromList(int drone)
{
	int i = dronesList.FindValue(drone);
	if (i < 0)
		return;
	dronesList.Erase(i);
	dronesModelList.Erase(i);
	dronesOwnerList.Erase(i);
}

 /**
 * Creates the drone physics model.
 *
 * @param client_index			index of the client.
 * @param pos					position of the drone to create.
 * @param rot					rotation of the drone to create.
 */
public void CreateDrone(int client_index, float pos[3], float rot[3])
{
	// Can be moved, must have a larger hitbox than the drone model (no stuck, easier pickup, easier target)
	int drone = CreateEntityByName("prop_physics_override"); 
	if (IsValidEntity(drone)) {
		SetDronePhysicsModel(drone);
		DispatchKeyValue(drone, "solid", "6");
		//DispatchKeyValue(drone, "overridescript", "mass,100.0,inertia,1.0,damping,1.0,rotdamping ,1.0"); // overwrite params
		DispatchKeyValue(drone, "overridescript", "rotdamping,1000.0"); // Prevent drone rotation
		DispatchSpawn(drone);
		ActivateEntity(drone);
		TeleportEntity(drone, pos, rot, NULL_VECTOR);
		
		SDKHook(drone, SDKHook_OnTakeDamage, Hook_TakeDamageGear);
		SetEntityRenderMode(drone, RENDER_NONE);
		CreateDroneModel(client_index, drone);
	}
}

 /**
 * Sets the drone physics model.
 * Uses a custom model if cvar set and custom model valid.
 *
 * @param drone			index of the drone.
 */
public void SetDronePhysicsModel(int drone)
{
	if (useCustomDroneModel && !StrEqual(customDronePhysModel, "", false))
		SetEntityModel(drone, customDronePhysModel);
	else
		SetEntityModel(drone, defaultDronePhysModel);
}

 /**
 * Creates the drone model prop.
 * This prop isn't solid and is parented to the physics model.
 * Uses a custom model if cvar set and custom model valid.
 *
 * @param client_index			index of the client.
 * @param drone					index of the drone.
 */
public void CreateDroneModel(int client_index, int drone)
{
	// This one can be animated/move with player
	int model = CreateEntityByName("prop_dynamic_override"); 
	if (IsValidEntity(model)) {
		if (useCustomDroneModel && !StrEqual(customDroneModel, "", false))
			SetEntityModel(model, customDroneModel);
		else
			SetEntityModel(model, defaultDroneModel);
		
		DispatchKeyValue(model, "solid", "0");
		DispatchSpawn(model);
		ActivateEntity(model);
		
		SetVariantString("!activator"); AcceptEntityInput(model, "SetParent", drone, model, 0);
		
		float pos[3], rot[3];
		if (useCustomDroneModel)
			TeleportEntity(model, pos, customDroneModelRot, NULL_VECTOR);
		else
			TeleportEntity(model, pos, rot, NULL_VECTOR);
		
		SDKHook(model, SDKHook_SetTransmit, Hook_SetTransmitGear);
		
		AddDrone(drone, model, client_index);
	}
}

 /**
 * If the drone is grounded, move it in the player's view direction.
 *
 * @param client_index				index of the client.
 * @param drone						index of the drone.
 */
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

 /**
 * If the drone is grounded, jump in the player's view direction and emit a jump sound.
 *
 * @param client_index				index of the client.
 * @param drone						index of the drone.
 */
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
		EmitSoundToAll(droneJumpSound, drone, SNDCHAN_AUTO, SNDLEVEL_CAR, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
}

 /**
 * If the player is in a drone, hide the viewmodel and the guns from the hud, and lower the view.
 * Also sets the position of the drone in order for it to fly over the ground.
 *
 * @param client_index			index of the client.
 */
public void Hook_PostThinkDrone(int client_index)
{
	if (activeDrone[client_index][0] < 0)
		return
	int drone = activeDrone[client_index][0];
	float groundDistance = DistanceToGround(drone);
	
	LowerDroneView(client_index);
	HideHudGuns(client_index);
	SetViewModel(client_index, false);
	float rot[3];
	GetClientEyeAngles(client_index, rot);
	if (useCustomDroneModel)
	{
		for (int i = 0; i < sizeof(rot); i++)
		{
			rot[i] += customDroneModelRot[i];
		}
	}
	TeleportEntity(activeDrone[client_index][1], NULL_VECTOR, rot, NULL_VECTOR); // Model follows player rotation (with custom rotation offset)
	
	isDroneGrounded[client_index] = !(groundDistance > (droneHoverHeight + 1.0));
	if (!isDroneMoving[client_index] || !isDroneGrounded[client_index])
		return;
	
	float pos[3], nullRot[3], vel[3];
	GetEntPropVector(drone, Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(drone, Prop_Data, "m_vecVelocity", vel);
	pos[2] += droneHoverHeight - groundDistance;
	if (vel[2] >= 0.0)
		TeleportEntity(drone, pos, nullRot, NULL_VECTOR);
}

 /**
 * Lower the player view to match the drone position.
 *
 * @param client_index			index of the client.
 */
public void LowerDroneView(int client_index)
{
	float viewPos[3];
	viewPos[2] = droneEyePosOffset;
	SetEntPropVector(client_index, Prop_Data, "m_vecViewOffset", viewPos);
}

 /**
 * Calculates the distance to the ground from the center of the entity.
 *
 * @param client_index				index of the client.
 * @return 							distance from the entity to the ground. 999.0 if no end point is found.
 */
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

 /**
 * Filter for trace ray ignoring players and the given data.
 */
public bool TraceFilterIgnorePlayers(int entity_index, int mask, any data)
{
	if((entity_index >= 1 && entity_index <= MaxClients) || entity_index == data)
	{
		return false;
	}
	return true;
} 

 /**
 * Teleports the player to the selected drone.
 * It creates a fake player at his old position.
 * The teleported player is frozen, not solid, and invicible.
 *
 * @param client_index			index of the client.
 * @param drone					index of the drone.
 */
public void TpToDrone(int client_index, int drone)
{
	// Allow for drone to drone switch
	if (fakePlayersListDrones[client_index] < 1)
	{
		CreateFakePlayer(client_index, false);
		EmitSoundToClient(client_index, openDroneSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
	if (activeDrone[client_index][1] > MAXPLAYERS)
	{
		SetVariantString("!activator"); AcceptEntityInput(activeDrone[client_index][1], "SetParent", activeDrone[client_index][0], activeDrone[client_index][1], 0);
		float pos[3], rot[3];
		TeleportEntity(activeDrone[client_index][1], pos, rot, NULL_VECTOR);
		StopSound(activeDrone[client_index][0], SNDCHAN_AUTO, droneSound)
	}
	// Set active
	activeDrone[client_index][0] = drone;
	activeDrone[client_index][1] = dronesModelList.Get(dronesList.FindValue(drone));
	// Set appearance
	SetEntityModel(client_index, inDroneModel); // Set to a small model to prevent collisions/shots
	SetGearScreen(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	// Hooks
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKHook(client_index, SDKHook_PostThink, Hook_PostThinkDrone);
	SDKHook(client_index, SDKHook_OnTakeDamage, Hook_TakeDamagePlayer);
	// Set pos
	SetVariantString("!activator"); AcceptEntityInput(client_index, "SetParent", drone, client_index, 0);
	float pos[3], rot[3];
	GetEntPropVector(activeDrone[client_index][1], Prop_Send, "m_angRotation", rot);
	if (useCustomDroneModel)
	{
		for (int i = 0; i < sizeof(rot); i++)
		{
			rot[i] -= customDroneModelRot[i];
		}
	}
	TeleportEntity(client_index, pos, rot, NULL_VECTOR); // Get old rotation back (with custom rotation offset)
	// Set collisions
	oldCollisionValueD[client_index] = GetEntData(client_index, GetCollOffset(), 1);
	SetEntData(client_index, GetCollOffset(), 2, 4, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 2);
	
	// Sound
	EmitSoundToAll(droneSound, drone, SNDCHAN_AUTO, SNDLEVEL_CAR, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
}

 /**
 * Teleports the player from the drone to his old postion (fake player position).
 * It deletes the fake player.
 * The teleported player gets normal properties (collisions, movement).
 *
 * @param client_index			index of the client.
 */
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
	SDKUnhook(client_index, SDKHook_OnTakeDamage, Hook_TakeDamagePlayer);
	// Set pos
	AcceptEntityInput(client_index, "SetParent");
	float pos[3], rot[3];
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(fakePlayersListDrones[client_index], Prop_Send, "m_angRotation", rot);
	TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	// Set collisions
	SetEntData(client_index, GetCollOffset(), oldCollisionValueD[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	// Sound
	StopSound(activeDrone[client_index][0], SNDCHAN_AUTO, droneSound)
	EmitSoundToClient(client_index, openDroneSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	// Clear stuff
	RemoveEdict(fakePlayersListDrones[client_index]);
	fakePlayersListDrones[client_index] = -1;
	activeDrone[client_index][0] = -1;
	activeDrone[client_index][1] = -1;
}

 /**
 * Destroys the selected drone.
 * If a player is using it, closes the drone first.
 *
 * @param drone					index of the drone.
 * @param isSilent				whether to play a destroy sound.
 */
public void DestroyDrone(int drone, bool isSilent)
{
	if (!isSilent)
	{
		float pos[3];
		GetEntPropVector(drone, Prop_Send, "m_vecOrigin", pos);
		EmitSoundToAll(destroyDroneSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS,  SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);
	}
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeDrone[i][0] == drone && IsValidClient(i))
		{
			CloseDrone(i);
		}
	}
	
	if (IsValidEdict(drone))
		RemoveEdict(drone);
	if (IsValidEdict(dronesModelList.Get(dronesList.FindValue(drone))))
		RemoveEdict(dronesModelList.Get(dronesList.FindValue(drone)));
	
	RemoveDroneFromList(drone);
}
