/*
 *
 * Since it is impossible in Nexgen to get rid of the build-in team balancer message, we at least want it to stop interfering with our message commands.
 * We hook this mutator into the message mutator chain right before Nexgen and simply skip the call to it.
 * While at it, also skip the call to NexgenPlus since it adds the !stats command for toggling the SmartCTF scoreboard.
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
  
  // Get next message mutator beside Nexgen and NexgenPlus
  otherNextMessageMutator = nextMessageMutator;
  while(otherNextMessageMutator != none && (InStr(otherNextMessageMutator.class.name, "NexgenController") != -1 || InStr(otherNextMessageMutator.class.name, "NXPMain") != -1)) {
    otherNextMessageMutator = otherNextMessageMutator.nextMessageMutator;
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