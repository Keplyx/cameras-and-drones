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


public void CreateConVars(char[] version)
{
	CreateConVar("cd_version", version, "Cameras and Drones", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	AutoExecConfig(true, "cameras-and-drones");
}

public void RegisterCommands()
{
	//RegAdminCmd("cd_buy", SetOP, ADMFLAG_GENERIC, "Set a specified player to the Chicken OP");
}

public void IntiCvars()
{

}

public void ResetCvars()
{

}