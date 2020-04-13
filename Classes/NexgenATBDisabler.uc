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
// Overwrite Nexgen's buildin team balaner
class NexgenATBDisabler extends NexgenTeamBalancer;

/***************************************************************************************************
 *
 *  $DESCRIPTION  Attempts to balance the current teams.
 *  $RETURN       True if the teams have been balanced, false if they are already balanced.
 *
 **************************************************************************************************/
function bool balanceTeams() {

	return false;
}

defaultproperties
{
}
