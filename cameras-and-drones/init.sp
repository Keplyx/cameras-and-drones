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

ConVar cvar_gearteam = null;
ConVar cvar_camprice = null;
ConVar cvar_droneprice = null;

ConVar cvar_totalmax_cam = null;
ConVar cvar_totalmax_drone = null;

ConVar cvar_pickuprange = null;
ConVar cvar_jumpcooldown = null;

public void CreateConVars(char[] version)
{
	CreateConVar("cd_version", version, "Cameras and Drones", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cvar_gearteam = CreateConVar("cd_gearteam", "3", "Set which team can use cameras. The oposite will have drones. 0 = All drones, 1 = All cameras, 2 = T cameras, 3 = CT cameras", FCVAR_NOTIFY);
	
	cvar_camprice = CreateConVar("cd_camprice", "800", "Set cameras price. min = 0, max = 30000", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	cvar_droneprice = CreateConVar("cd_droneprice", "800", "Set drones price. min = 0, max = 30000", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	
	cvar_totalmax_cam = CreateConVar("cd_totalmax_cam", "1", "Set the maximum cameras a player can setup. min = 1, max = 10", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	cvar_totalmax_drone = CreateConVar("cd_totalmax_drone", "1", "Set the maximum drones a player can setup. min = 1, max = 10", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	
	cvar_pickuprange = CreateConVar("cd_pickuprange", "150", "Set the max range at which a player can pickup its drone/cam. 0 = no pickup", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	cvar_jumpcooldown = CreateConVar("cd_jumpcooldown", "1", "Set the time players must wait before jmping again with the drone.", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
	AutoExecConfig(true, "cameras-and-drones");
}

public void RegisterCommands()
{
	RegConsoleCmd("cd_buy", BuyGear, "Buy team gear");
	RegConsoleCmd("cd_cam", OpenGear, "Open cameras");
}

public void IntiCvars()
{
	//Enable hiding of players
	SetConVarBool(FindConVar("sv_disable_immunity_alpha"), true);
}

public void ResetCvars()
{
	ResetConVar(FindConVar("sv_disable_immunity_alpha"));
}