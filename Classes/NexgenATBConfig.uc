/*##################################################################################################
##
##  Nexgen Auto Team Balancer BETA
##  Copyright (C) 2020 Patrick "Sp0ngeb0b" Peltzer
##
##  This program is free software; you can redistribute and/or modify
##  it under the terms of the Open Unreal Mod License version 1.1.
##
##  Contact: spongebobut@yahoo.com | www.unrealriders.eu
##
##  Based on AutoTeamBalance by nogginBasher.
##
##################################################################################################*/
class NexgenATBConfig extends Info;

// Version controlling
var NexgenATB xControl;                
var config int lastInstalledVersion;

// Config variables
var config int defaultStrength;     // The default strength new (unknown) players start with.  
var config int teamScoreBonus;      // Additional strength bonus per team score point.
var config int winningTeamBonus;    // Additional score rewarded to player strength calculation when finishing on winning team.

// Special sounds
var config string startSound;
var config string playSound;
var config string teamSound[2];

// Database
var config string playerData[2048]; // ID,Strength,SecondsPlayed

const separator = ",";

/***************************************************************************************************
 *
 *  $DESCRIPTION  Automatically installs the plugin.
 *  $ENSURE       lastInstalledVersion >= xControl.versionNum
 *
 **************************************************************************************************/
function install() {
	if (lastInstalledVersion < 001) installVersion001();

	if (lastInstalledVersion < xControl.versionNum) {
		lastInstalledVersion = xControl.versionNum;
		saveConfig();
	}
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Automatically installs version 001 of the plugin.
 *
 **************************************************************************************************/
function installVersion001() {
	defaultStrength = 40;
	teamScoreBonus = 10;
  winningTeamBonus = 5;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Unloads the data stored in the database for a certain index.
 *
 **************************************************************************************************/
function loadData(int index, out float strength, out int secondsPlayed) {
  local string remaining, strengthStr, secondsPlayedStr;
  
  // Default values
  if(Len(playerData[index]) == 32) {
    strength      = defaultStrength;
    secondsPlayed = 0;
  } else {
    class'NexgenUtil'.static.split(playerData[index], strengthStr, remaining);
    class'NexgenUtil'.static.split(remaining, strengthStr, remaining);
    strength = float(strengthStr);
    class'NexgenUtil'.static.split(remaining, secondsPlayedStr, remaining);
    secondsPlayed = int(secondsPlayedStr);
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Updates a certain database entry.
 *
 **************************************************************************************************/
function updateData(int index, float strength, int secondsPlayed) {
  playerData[index] = Left(playerData[index], 32) $ separator $ strength $ separator $ secondsPlayed $ separator $ getDate();
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Returns the current Date in a specifc form so it can be saved.
 *
 **************************************************************************************************/
function string getDate() {

  return class'NexgenUtil'.static.serializeDate(level.year, level.month, level.day, level.hour, level.minute);
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Default properties block.
 *
 **************************************************************************************************/
defaultproperties 
{
}