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

// SOUNDS
char openCamSound[] = "weapons/movement3.wav";
char destroyCamSound[] = "physics/metal/metal_box_impact_bullet1.wav";
// MODELS
char inCamModel[] = "models/chicken/festive_egg.mdl"; // must have hitbox or it will use the default player one
char defaultCamModel[] = "models/weapons/w_eq_sensorgrenade_thrown.mdl";
char defaultCamPhysModel[] = "models/props/de_inferno/hr_i/ground_stone/ground_stone.mdl"; // Must surround cam
char customCamModel[PLATFORM_MAX_PATH];
char customCamPhysModel[PLATFORM_MAX_PATH];
// LISTS
ArrayList camerasList;
ArrayList camerasModelList;
ArrayList camOwnersList;
int activeCam[MAXPLAYERS + 1][3]; // 0: phys, 1: model, 2: flash
int fakePlayersListCamera[MAXPLAYERS + 1];

int oldCollisionValue[MAXPLAYERS + 1];
float customCamModelRot[3];

bool useCustomCamModel = false;
bool useCamAngles = true;

bool cTacticalShield;

 /**
 * Add a new camera to the list.
 *
 * @param cam					camera index.
 * @param model					camera model index.
 * @param client_index			owner client index.
 */
public void AddCamera(int cam, int model, int client_index)
{
	camerasList.Push(cam);
	camerasModelList.Push(model);
	camOwnersList.Push(client_index);
}

 /**
 * Removes the given camera from the list.
 *
 * @param cam			camera index.
 */
public void RemoveCameraFromList(int cam)
{
	int i = camerasList.FindValue(cam);
	if (i < 0)
		return;
	camerasList.Erase(i);
	camerasModelList.Erase(i);
	camOwnersList.Erase(i);
}

 /**
 * Creates the camera physics prop.
 *
 * @param client_index			index of the client.
 * @param pos					position of the camera to create.
 * @param rot					rotation of the camera to create.
 */
public void CreateCamera(int client_index, float pos[3], float rot[3])
{
	int cam = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(cam)) {
		SetCameraPhysicsModel(cam);
		DispatchKeyValue(cam, "solid", "6");
		DispatchSpawn(cam);
		ActivateEntity(cam);
		
		TeleportEntity(cam, pos, rot, NULL_VECTOR);
		
		SDKHook(cam, SDKHook_OnTakeDamage, Hook_TakeDamageGear);
		SetEntityRenderMode(cam, RENDER_NONE);
		CreateCameraModel(client_index, cam);
	}
}

 /**
 * Sets the camera physics model.
 * Uses a custom model if cvar set and custom model valid.
 *
 * @param cam			index of the camera.
 */
public void SetCameraPhysicsModel(int cam)
{
	if (useCustomCamModel && !StrEqual(customCamPhysModel, "", false))
		SetEntityModel(cam, customCamPhysModel);
	else
		SetEntityModel(cam, defaultCamPhysModel);
}

 /**
 * Creates the camera model prop.
 * This prop isn't solid and is parented to the physics model.
 * Uses a custom model if cvar set and custom model valid.
 *
 * @param client_index			index of the client.
 * @param cam					index of the camera.
 */
public void CreateCameraModel(int client_index, int cam)
{
	int model = CreateEntityByName("prop_dynamic_override");
	if (IsValidEntity(model)) {
		if (useCustomCamModel && !StrEqual(customCamModel, "", false))
			SetEntityModel(model, customCamModel);
		else
			SetEntityModel(model, defaultCamModel);
		
		DispatchKeyValue(model, "solid", "0");
		DispatchSpawn(model);
		ActivateEntity(model);
		
		SetVariantString("!activator"); AcceptEntityInput(model, "SetParent", cam, model, 0);
		float pos[3], rot[3];
		if (useCustomCamModel)
			TeleportEntity(model, pos, customCamModelRot, NULL_VECTOR);
		else
			TeleportEntity(model, pos, rot, NULL_VECTOR);
		
		SDKHook(model, SDKHook_SetTransmit, Hook_SetTransmitGear);
		AddCamera(cam, model, client_index);
	}
}

 /**
 * Creates the flashing light sprite if none already exists for the selected camera.
 *
 * @param client_index			index of the client.
 * @param cam					index of the camera.
 */
public void CreateFlash(int client_index, int cam)
{
	DestroyFlash(client_index);
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][0] == cam && i != client_index)
		{
			activeCam[client_index][2] = activeCam[i][2];
			return; // Prevent from creating multiple red flashes
		}
	}
	int flash = CreateEntityByName("env_sprite");
	if (IsValidEntity(flash))
	{
		activeCam[client_index][2] = flash;
		DispatchKeyValue(flash, "spawnflags", "1");
		DispatchKeyValue(flash, "scale", "0.3");
		DispatchKeyValue(flash, "rendercolor", "255 0 0");
		DispatchKeyValue(flash, "rendermode", "5"); // Additive
		DispatchKeyValue(flash, "renderfx", "13"); // Fast Flicker
		DispatchKeyValue(flash, "model", "sprites/glow01.vmt");
		
		float pos[3], rot[3];
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
		TeleportEntity(flash, pos, rot, NULL_VECTOR);
		
		DispatchSpawn(flash);
		ActivateEntity(flash);
		
		SDKHook(flash, SDKHook_SetTransmit, Hook_SetTransmitGear);
	}
}

 /**
 * Destroys the flashing light sprite if no other players are viewing this camera.
 *
 * @param client_index			index of the client.
 */
public void DestroyFlash(int client_index)
{
	if (!IsValidEntity(activeCam[client_index][2]))
		return;
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (i != client_index && activeCam[i][2] == activeCam[client_index][2])
		{
			activeCam[client_index][2] = -1;
			return; // Prevent from deleting other player flash
		}
	}
	RemoveEdict(activeCam[client_index][2])
	activeCam[client_index][2] = -1;
}

 /**
 * If the player is in a camera, hide the viewmodel and the guns from the hud, and lower the view.
 *
 * @param client_index			index of the client.
 */
public void Hook_PostThinkCam(int client_index)
{
	if (activeCam[client_index][0] < 0)
		return;
	
	HideHudGuns(client_index);
	SetViewModel(client_index, false);
	LowerCameraView(client_index);
}

 /**
 * Lower the player view to match the camera position.
 *
 * @param client_index			index of the client.
 */
public void LowerCameraView(int client_index)
{
	float viewPos[3];
	SetEntPropVector(client_index, Prop_Data, "m_vecViewOffset", viewPos);
}

 /**
 * Teleports the player to the selected camera.
 * It creates a fake player at his old position.
 * The teleported player is frozen, not solid, and invicible.
 *
 * @param client_index			index of the client.
 * @param cam					index of the camera.
 */
public void TpToCam(int client_index, int cam)
{
	if (cTacticalShield)
		SetHidePlayerShield(client_index, true);
	
	if (!IsClientInCam(client_index))
	{
		CreateFakePlayer(client_index, true);
		EmitSoundToClient(client_index, openCamSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
	// Set active
	activeCam[client_index][0] = cam;
	activeCam[client_index][1] = camerasModelList.Get(camerasList.FindValue(cam));
	
	SetEntityModel(client_index, inCamModel); // Set to a small model to prevent collisions/shots
	SetGearScreen(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_NOCLIP);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 0.0);
	// Set pos
	float pos[3], rot[3];
	if (useCamAngles)
	{
		SetVariantString("!activator"); AcceptEntityInput(client_index, "SetParent", cam, client_index, 0);
		TeleportEntity(client_index, pos, rot, NULL_VECTOR);
	}
	else
	{
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
		TeleportEntity(client_index, pos, NULL_VECTOR, NULL_VECTOR);
	}
	
	// Set collisiosn
	oldCollisionValue[client_index] = GetEntData(client_index, GetCollOffset(), 1);
	SetEntData(client_index, GetCollOffset(), 2, 4, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 2);
	
	// Hooks
	SDKHook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKHook(client_index, SDKHook_PostThink, Hook_PostThinkCam);
	SDKHook(client_index, SDKHook_OnTakeDamage, Hook_TakeDamagePlayer);
	
	CreateFlash(client_index, cam);
}

 /**
 * Teleports the player from the camera to his old postion (fake player position).
 * It deletes the fake player.
 * The teleported player gets normal properties (collisions, movement).
 *
 * @param client_index			index of the client.
 */
public void ExitCam(int client_index)
{
	SetGearScreen(client_index, false);
	SetViewModel(client_index, true);
	SetEntityMoveType(client_index, MOVETYPE_WALK);
	SetEntPropFloat(client_index, Prop_Data, "m_flLaggedMovementValue", 1.0);
	
	SDKUnhook(client_index, SDKHook_SetTransmit, Hook_SetTransmitPlayer);
	SDKUnhook(client_index, SDKHook_PostThink, Hook_PostThinkCam);
	SDKUnhook(client_index, SDKHook_OnTakeDamage, Hook_TakeDamagePlayer);
	// Set collisions
	SetEntData(client_index, GetCollOffset(), oldCollisionValue[client_index], 1, true);
	SetEntProp(client_index, Prop_Send, "m_nHitboxSet", 0);
	if (IsClientInCam(client_index) && IsValidEdict(fakePlayersListCamera[client_index]))
	{
		// Set appearance
		char modelName[PLATFORM_MAX_PATH];
		GetEntPropString(fakePlayersListCamera[client_index], Prop_Data, "m_ModelName", modelName, sizeof(modelName));
		SetEntityModel(client_index, modelName);
		// Set pos
		AcceptEntityInput(client_index, "SetParent");
		float pos[3], rot[3];
		GetEntPropVector(fakePlayersListCamera[client_index], Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(fakePlayersListCamera[client_index], Prop_Send, "m_angRotation", rot);
		TeleportEntity(client_index, pos, rot, NULL_VECTOR);
		RemoveEdict(fakePlayersListCamera[client_index]);
		DestroyFlash(client_index);
		EmitSoundToClient(client_index, openCamSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
	activeCam[client_index][0] = -1;
	activeCam[client_index][1] = -1;
	fakePlayersListCamera[client_index] = -1;
	
	if (cTacticalShield)
		SetHidePlayerShield(client_index, false);
}

 /**
 * Destroys the selected camera.
 * If a player is using it, closes the camera first.
 *
 * @param cam					index of the camera.
 * @param isSilent				whether to play a destroy sound.
 */
public void DestroyCamera(int cam, bool isSilent)
{
	if (!isSilent)
	{
		float pos[3];
		GetEntPropVector(cam, Prop_Send, "m_vecOrigin", pos);
		EmitSoundToAll(destroyCamSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS,  SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);
	}
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (activeCam[i][0] == cam && IsValidClient(i))
			CloseCamera(i);
	}
	
	if (IsValidEdict(cam))
		RemoveEdict(cam);
	if (IsValidEdict(camerasModelList.Get(camerasList.FindValue(cam))))
		RemoveEdict(camerasModelList.Get(camerasList.FindValue(cam)));
	RemoveCameraFromList(cam);
}

 /**
 * Checks whether the given player is using his camera or not.
 *
 * @param client_index		index of the client.
 * @return					true if the player is using his camera, false otherwise.
 */
public bool IsClientInCam(int client_index)
{
	return activeCam[client_index][0] > MAXPLAYERS;
}