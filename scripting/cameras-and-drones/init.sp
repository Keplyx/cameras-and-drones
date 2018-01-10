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

#include <convars>

ConVar cvar_welcome_message = null;

ConVar cvar_gear_team = null;
ConVar cvar_price_cam = null;
ConVar cvar_price_drone = null;

ConVar cvar_totalmax_cam = null;
ConVar cvar_totalmax_drone = null;

ConVar cvar_pickup_range = null;
ConVar cvar_jump_cooldown = null;

ConVar cvar_tkprotect = null;

ConVar cvar_drone_speed = null;
ConVar cvar_drone_jump = null;
ConVar cvar_drone_hoverheight = null;

ConVar cvar_use_cam_angles = null;
ConVar cvar_custom_model_drone = null;
ConVar cvar_custom_model_cam = null;

ConVar cvar_cam_box_size = null;

ConVar cvar_buytime = null;
ConVar cvar_buytime_start = null;
ConVar cvar_keep_between_rounds = null;

 /**
 * Creates plugin cvars.
 *
 * @param version			version name.
 */
public void CreateConVars(char[] version)
{
	CreateConVar("cameras-and-drones_version", version, "Cameras and Drones Version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cvar_welcome_message = CreateConVar("cd_welcomemessage", "1", "Displays a welcome message to new players. 0 = no message, 1 = display message", FCVAR_NOTIFY, true, 0.0, true, 1.0); 
	
	cvar_gear_team = CreateConVar("cd_gear_team", "3", "Set which team can use cameras. The oposite will have drones. 0 = All drones, 1 = All cameras, 2 = T cameras, 3 = CT cameras", FCVAR_NOTIFY);
	
	cvar_price_cam = CreateConVar("cd_price_cam", "800", "Set cameras price. min = 0, max = 30000", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	cvar_price_drone = CreateConVar("cd_price_drone", "800", "Set drones price. min = 0, max = 30000", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	
	cvar_totalmax_cam = CreateConVar("cd_totalmax_cam", "1", "Set the maximum cameras a player can setup. Change 'ammo_grenade_limit_default' to change the number of gear a player can carry. min = 1, max = 10", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	cvar_totalmax_drone = CreateConVar("cd_totalmax_drone", "1", "Set the maximum drones a player can setup. Change 'ammo_grenade_limit_default' to change the number of gear a player can carry. min = 1, max = 10", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	
	cvar_pickup_range = CreateConVar("cd_pickup_range", "150", "Set the max range at which a player can pickup its drone/cam. 0 = no pickup", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	cvar_jump_cooldown = CreateConVar("cd_jump_cooldown", "1", "Set the time players must wait before jmping again with the drone.", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	
	cvar_tkprotect = CreateConVar("cd_tkprotect", "1", "Set whether teammates can break gear. 0 = no protection, 1 = protected", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	cvar_drone_speed = CreateConVar("cd_drone_speed", "150", "Set the drone speed. 130 = human walk, 250 = human run", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	cvar_drone_jump = CreateConVar("cd_drone_jump", "300", "Set drone jump force", FCVAR_NOTIFY, true, 0.0, true, 500.0);
	cvar_drone_hoverheight = CreateConVar("cd_drone_hoverheight", "5", "The hover height of your drone. Setting it too hight or too low will break the drone. It should match the phys model size.", FCVAR_NOTIFY, true, 1.0, true, 150.0);
	cvar_drone_speed.AddChangeHook(OnCvarChange);
	cvar_drone_jump.AddChangeHook(OnCvarChange);
	cvar_drone_hoverheight.AddChangeHook(OnCvarChange);
	
	cvar_buytime = CreateConVar("cd_buytime", "-2", "Set how much time (in seconds) players have to buy their gear. -2 to use 'mp_buytime' value, -1 = forever", FCVAR_NOTIFY, true, -2.0, true, 3600.0);
	cvar_buytime_start = CreateConVar("cd_buytime_start", "0", "Set when to start buy time counter. 0 = on round start, 1 = on spawn", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_buytime.AddChangeHook(OnCvarChange);
	
	cvar_use_cam_angles = CreateConVar("cd_use_cam_angles", "1", "Set whether to use camera angles when using it.", FCVAR_NOTIFY, true, 0.0, true, 1.0); 
	cvar_use_cam_angles.AddChangeHook(OnCvarChange);
	
	cvar_custom_model_drone = CreateConVar("cd_custom_model_drone", "0", "Set whether to use a model specified in sourcemod/gamedata/custom_models.txt.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_custom_model_drone.AddChangeHook(OnCvarChange);
	cvar_custom_model_cam = CreateConVar("cd_custom_model_cam", "0", "Set whether to use a model specified in sourcemod/gamedata/custom_models.txt.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_custom_model_cam.AddChangeHook(OnCvarChange);
	
	cvar_keep_between_rounds = CreateConVar("cd_keep_between_rounds", "1", "Set whether to keep gear between rounds when staying alive with one. This will also keep override state.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	cvar_cam_box_size = CreateConVar("cd_cam_box_size", "15", "Size of the edge of the box surrounding the cam, used to detect if it touches something. Camera will freeze when something enters this box. Set to 0 if you don't want sticky cameras.", FCVAR_NOTIFY, true, 0.0, true, 500.0);
	
	AutoExecConfig(true, "cameras-and-drones");
}

 /**
 * Creates plugin commands.
 */
public void RegisterCommands()
{
	RegAdminCmd("cd_override", OverrideGear, ADMFLAG_GENERIC, "Override gear for a player");
	RegAdminCmd("cd_reloadmodels", ReloadModelsList, ADMFLAG_GENERIC, "Reload custom models file");
	RegConsoleCmd("cd_buy", BuyGear, "Buy team gear");
	RegConsoleCmd("cd_toggle", ToggleGear, "Toggle gear");
	RegConsoleCmd("cd_deploy", DeployGear, "Deploy gear");
	RegConsoleCmd("cd_help", ShowHelp, "Show plugin help");
	RegConsoleCmd("say !cd_help", ShowHelp, "Show plugin help");
}
