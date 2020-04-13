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
/*
 *
 * Since it is impossible in Nexgen to get rid of the build-in team balancer message, we at least want it to stop interfering with our message commands.
 * We hook this mutator into the message mutator chain right before Nexgen and simply skip the call to it.
 * This will work as long as no other NexgenPlugin spawns its own message mutator. In case it does, we warn the admin about the ServerActor line order.
 *
 */
class NexgenATBMessageMutator extends Mutator;

var NexgenATB ATBControl;
var Mutator otherNextMessageMutator;

/***************************************************************************************************
 *
 *  $DESCRIPTION  Register self as message mutator and find alternative next message mutator.
 *
 **************************************************************************************************/
function preBeginPlay() {
  ATBControl = NexgenATB(Owner);

  // This is called after Nexgen's preBeginPlay so we will be in front of it in the chain
  level.game.registerMessageMutator(self);
  
  // Get next message mutator beside Nexgen
  otherNextMessageMutator = nextMessageMutator;
  if(otherNextMessageMutator != none && (InStr(otherNextMessageMutator.class.name, "NexgenController") != -1)) {
    otherNextMessageMutator = otherNextMessageMutator.nextMessageMutator;
  } else {
    ATBControl.control.nscLog("[NATB] Next message mutator is not the NexgenController!");
    ATBControl.control.nscLog("[NATB] You are advised to add the NexgenATB.NexgenATB ServerActor directly after the NexgenActor line!");
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Catches player messages except spectator say.
 *
 **************************************************************************************************/
function bool mutatorTeamMessage(Actor sender, Pawn receiver, PlayerReplicationInfo pri,
                                 coerce string s, name type, optional bool bBeep) {
  local bool bATBCommand;
  
  // Check for commands.
  if (sender != none && sender.isA('PlayerPawn') && sender == receiver &&
      (type == 'Say' || type == 'TeamSay')) {
    if(ATBControl.handleOurMsgCommands(PlayerPawn(sender), s)) bATBCommand = true;
  }
  
  // Allow other message mutators to do their job.
  if(bATBCommand) {
    if (otherNextMessageMutator != none) {
      return otherNextMessageMutator.mutatorTeamMessage(sender, receiver, pri, s, type, bBeep);
    } else {
      return true;
    } 
  } else {
    if (nextMessageMutator != none) {
      return nextMessageMutator.mutatorTeamMessage(sender, receiver, pri, s, type, bBeep);
    } else {
      return true;
    }
  }  
}    

/***************************************************************************************************
 *
 *  $DESCRIPTION  Catches spectator say.
 *
 **************************************************************************************************/
function bool mutatorBroadcastMessage(Actor sender, Pawn receiver, out coerce string msg,
                                      optional bool bBeep, out optional name type) {
  local PlayerReplicationInfo senderPRI;
  local bool bIsSpecMessage, bATBCommand;

  // Get sender player replication info.
  if (sender != none && sender.isA('Pawn')) {
    senderPRI = Pawn(sender).playerReplicationInfo;
  }

  // Check if we're dealing with a spectator chat message.
  bIsSpecMessage = senderPRI != none && sender.isA('Spectator') &&
                   left(msg, len(senderPRI.playerName) + 1) ~= (senderPRI.playerName $ ":");

  // Check for commands.
  if (bIsSpecMessage && sender == receiver) {
    if(ATBControl.handleOurMsgCommands(PlayerPawn(sender), mid(msg, len(senderPRI.playerName) + 1))) bATBCommand = true;
  }
  
  // Allow other message mutators to do their job.
  if(bATBCommand) {
    if (otherNextMessageMutator != none) {
      return otherNextMessageMutator.mutatorBroadcastMessage(sender, receiver, msg, bBeep, type);
    } else {
      return true;
    } 
  } else {
    if (nextMessageMutator != none) {
      return nextMessageMutator.mutatorBroadcastMessage(sender, receiver, msg, bBeep, type);
    } else {
      return true;
    }
  } 
}