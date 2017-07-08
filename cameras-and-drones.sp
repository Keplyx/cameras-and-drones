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

#include <sourcemod>

#pragma newdecls required;

#include "cameras-and-drones/init.sp"


/*  New in this version
*	First release!
*
*/

#define VERSION "0.1.0"
#define PLUGIN_NAME "Cameras and Drones",

bool lateload;

public Plugin myinfo =
{
	name = PLUGIN_NAME
	author = "Keplyx",
	description = "CSGO plugin adding cameras and drones to the game.",
	version = VERSION,
	url = "https://github.com/Keplyx/cameras-and-drones"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateload = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVars(VERSION);
	RegisterCommands();
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
			OnClientPostAdminCheck(i);
	}
	
	if (lateload)
		ServerCommand("mp_restartgame 1");
}

public void OnConfigsExecuted()
{
	IntiCvars();
}

public void OnClientPostAdminCheck(int client_index)
{
	
}