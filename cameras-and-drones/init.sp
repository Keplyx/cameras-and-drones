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

ConVar cvar_camteam = null;
ConVar cvar_camprice = null;

public void CreateConVars(char[] version)
{
	CreateConVar("cd_version", version, "Cameras and Drones", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cvar_camteam = CreateConVar("cd_camteam", "3", "Set which team can use cameras. The oposite will have drones. 2 = T, 3 = CT", FCVAR_NOTIFY);
	cvar_camprice = CreateConVar("cd_camprice", "800", "Set cameras price.", FCVAR_NOTIFY, true, 0.0, true, 30000.0);
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