class NexgenATB extends NexgenPlugin;

var NexgenATBConfig xConf;                     // Plugin configuration.

var NexgenATBClient ATBClientList;
var int nextFreeEntry;
var int currPlayers;

var float waitFinishTime;
var float initialTeamSortTime;

// Mid-game join vars
var int   midGameJoinRemaining;
var float longestMidGameJoinWaitTime;

// Sounds
var Sound startSound, teamSound[2];

// Colors
var Color colorWhite, colorOrange;
var Color TeamColor[4];

const maxInitWaitTime    = 10.0;
const gameStartDelay     = 2.5;
const maxMidGameJoinWait = 5.0;               // Max amount of seconds after ATBClient is initialized before a team is assigned

/***************************************************************************************************
 *
 *  $DESCRIPTION  Initializes the plugin. Note that if this function returns false the plugin will
 *                be destroyed and is not to be used anywhere.
 *  $RETURN       True if the initialization succeeded, false if it failed.
 *  $OVERRIDE
 *
 **************************************************************************************************/
function bool initialize() {

	// Load settings.
	if (control.bUseExternalConfig) {
		xConf = spawn(class'NexgenATBConfigExt', self);
	} else {
		xConf = spawn(class'NexgenATBConfigSys', self);
	}
  
  // Load sounds
  startSound   = Sound(dynamicLoadObject(xConf.startSound, class'Sound'));
  teamSound[0] = Sound(dynamicLoadObject(xConf.teamSound[0], class'Sound'));
  teamSound[1] = Sound(dynamicLoadObject(xConf.teamSound[1], class'Sound'));

  //control.teamBalancer = spawn(class'URSTBDisabler', self);
  
	return true;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when a new client has been created. Use this function to setup the new
 *                client with your own extensions (in order to support the plugin).
 *  $PARAM        client  The client that was just created.
 *  $REQUIRE      client != none
 *  $OVERRIDE
 *
 **************************************************************************************************/
function clientCreated(NexgenClient client) {
  local NexgenATBClient ATBClient;
  local int i;
  
  if(client.bSpectator) return;
  
  ATBClient = spawn(class'NexgenATBClient', self);
  ATBClient.client = client;
  ATBClient.xControl = self;
	ATBClient.xConf = xConf;
  
  // Add to list
  ATBClient.nextATBClient = ATBClientList;
  ATBClientList = ATBClient;
  currPlayers++;

  if(currPlayers == 1) waitFinishTime = Level.TimeSeconds;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called whenever a client has finished its initialisation process. During this
 *                process things such as the remote control window are created. So only after the
 *                client is fully initialized all functions can be safely called.
 *  $PARAM        client  The client that has finished initializing.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function clientInitialized(NexgenClient client) {
  local NexgenATBClient ATBClient;
  
  ATBClient = getATBClient(client);
  
  if(ATBClient != none) {
    ATBClient.locateDataEntry();
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Locates the NexgenATBClient instance for the given actor.
 *  $PARAM        a  The actor for which the extended client handler instance is to be found.
 *  $REQUIRE      a != none
 *  $RETURN       The client handler for the given actor.
 *  $ENSURE       (!a.isA('PlayerPawn') ? result == none : true) &&
 *                imply(result != none, result.client.owner == a)
 *
 **************************************************************************************************/
function NexgenATBClient getATBClient(NexgenClient client) {
  local NexgenATBClient ATBClient;
  
  if (client != none && !client.bSpectator) {
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.client == client) {
        return ATBClient;
      }
    }
  }
  return none;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called whenever a player has joined the game (after its login has been accepted).
 *  $PARAM        client  The player that has joined the game.
 *  $REQUIRE      client != none
 *  $OVERRIDE
 *
 **************************************************************************************************/
function playerJoined(NexgenClient client) {
  local NexgenATBClient ATBClient;

  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Playing) {
    ATBClient = getATBClient(client);
    

    if(ATBClient != none && !ATBClient.bInitialized) {
      // Player not yet initialized. Disallow play.
      Level.Game.DiscardInventory(client.player);	
      client.player.PlayerRestartState = 'PlayerWaiting';
      client.player.GotoState(client.player.PlayerRestartState);
      midGameJoinRemaining++;
    }
  }
  
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called if a player has left the server.
 *  $PARAM        client  The player that has left the game.
 *  $REQUIRE      client != none
 *  $OVERRIDE
 *
 **************************************************************************************************/
function playerLeft(NexgenClient client) {
  local NexgenATBClient ATBClient;
  
  ATBClient = getATBClient(client);
  
  if(ATBClient != none) {
    removeATBClient(ATBClient);
    ATBClient.destroy();
    currPlayers--;
  }
  
  if(currPlayers == 1) waitFinishTime = Level.TimeSeconds;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Removes the specified client from the client list.
 *  $PARAM        client  The client that is to be removed.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function removeATBClient(NexgenATBClient ATBClient) {
	local NexgenATBClient currClient;
	local bool bDone;
	
	// Remove the client from the linked client list.
	if (ATBClientList == ATBClient) {
		// First element in the list.
		ATBClientList = ATBClient.nextATBClient;
	} else {
		// Somewhere else in the list.
		currClient = ATBClientList;
		while (!bDone && currClient != none) {
			if (currClient.nextATBClient == ATBClient) {
				bDone = true;
				currClient.nextATBClient = ATBClient.nextATBClient;
			} else {
				currClient = currClient.nextATBClient;
			}
		}
	}
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when the game has started.
 *
 **************************************************************************************************/
function gameStarted() {

}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when a player (re)spawns and allows us to modify the player.
 *  $PARAM        client  The client of the player that was respawned.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function playerRespawned(NexgenClient client) {
  local int index;

}

function tick(float deltaTime) {
  local int i;
  local bool bStillIniting;
  local NexgenClient client;
  local NexgenATBClient ATBClient;
  
  // Handle game start
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Waiting) {
    // Supress manual game start messages
    if(control.gInf.countDown == 1)  {
      waitFinishTime = Level.TimeSeconds;
      control.gInf.countDown = -1;
    }
    
    if(initialTeamSortTime == 0.0) {
    
      // Override team message
      for (client = control.clientList; client != none; client = client.nextClient) {
        if(!client.bSpectator) {
          FlashMessageToPlayer(client, "Teams not yet assigned.", colorWhite);
        }
        if(client.bInitialized) FlashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);
        else                    FlashMessageToPlayer(client, "", colorWhite, 1);        
      }
      
      // Start?
      if(control.gInf.countDown == -1 && currPlayers > 0) {
      
        // Check if all clients are initialized 
        for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
          if(ATBClient.configIndex == -1) {
            bStillIniting = true;
            break;
          }
        }
        
        // Start.
        if(!bStillIniting || (Level.TimeSeconds - waitFinishTime) >= maxInitWaitTime) {
          // Sort the teams.
          initialTeamSorting();
          initialTeamSortTime = Level.TimeSeconds;
          
          // Announce team.
          for (client = control.clientList; client != none; client = client.nextClient) {
            if(startSound != none) client.player.PlaySound(startSound, SLOT_Interface, 255.0);
            if(client.team == 0 || client.team == 1) {
              if(teamSound[client.team] != none) client.player.clientPlaySound(teamSound[client.team], , true);
            }
          }
        }
      } 
    } else {
      for (client = control.clientList; client != none; client = client.nextClient) {
        if(!client.bSpectator) {
          FlashMessageToPlayer(client ,"You are on "$TeamGamePlus(Level.Game).Teams[client.team].TeamName$".", teamColor[client.team]);
        }
        if(client.bInitialized) FlashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
        else                    FlashMessageToPlayer(client, "", colorWhite, 1);        
        
      }
      if( (Level.TimeSeconds - initialTeamSortTime) >= gameStartDelay) {
        // Continue game start
        control.startGame(true);
      }
    }
  } 
  
  // Clear progress messages when starting
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Starting) { 
    for (client = control.clientList; client != none; client = client.nextClient) {
      if(!client.bSpectator) {
        for(i=0; i<7; i++) {
          client.player.SetProgressMessage("", i);
        }
      }
    }
  }
  
  // Handle mid-game joined players
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Playing) { 
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(!ATBClient.client.bSpectator && ATBClient.client.player.PlayerRestartState == 'PlayerWaiting') {
        FlashMessageToPlayer(ATBClient.client, "Team not yet assigned.", colorOrange);
        if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
        else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
      }
    }
  }

}


/***************************************************************************************************
 *
 *  $DESCRIPTION  Plugin timer driven by the Nexgen controller. Ticks at a frequency of 1 Hz and is
 *                independent of the game speed.
 *
 **************************************************************************************************/
function virtualTimer() {
  if( (Level.TimeSeconds - longestMidGameJoinWaitTime) > maxMidGameJoinWait) {
    midGameJoinTeamSorting();
  }
}

function initialTeamSorting() {

}

function midGameJoinTeamSorting() {

}

function ATBClientInit(NexgenATBClient ATBClient) {
  local bool bBetterWait;
  
  if(control.gInf == none || control.gInf.gameState != control.gInf.GS_Playing) return;
  
  midGameJoinRemaining--;
  if(midGameJoinRemaining == 0) {
    midGameJoinTeamSorting();
  } else if(longestMidGameJoinWaitTime == 0) {
    longestMidGameJoinWaitTime = Level.TimeSeconds;
  }
}

// Taken from ATB 1.5
function FlashMessageToPlayer(NexgenClient client, string Msg, Color msgColor, optional int offset) {
  local int targetLine;
  
  if(client == none) return;

  // We want to override the line which usually says which team you are "on".
  // But different game types use a different line.
  // So far I have only checked CTF and Assault.
  targetLine = 3;
  if (Level.Game.Class.IsA('CTFGame'))
   targetLine = 3;
  if (Level.Game.Class.IsA('Assault'))
   targetLine = 2;
  if (Level.NetMode==NM_Standalone)
   targetLine = 2; // At lease true for CTF

  client.player.SetProgressTime(5);
  client.player.SetProgressColor(msgColor,targetLine+offset);
  client.player.SetProgressMessage(Msg,targetLine+offset);  
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Default properties block.
 *
 **************************************************************************************************/

defaultproperties
{
     colorWhite=(R=255,G=255,B=255,A=32)
     colorOrange=(R=255,G=69,B=0,A=32)
     TeamColor(0)=(R=255,G=0,B=0,A=32)
     TeamColor(1)=(R=0,G=128,B=255,A=32)
     TeamColor(2)=(R=0,G=255,B=0,A=32)
     TeamColor(3)=(R=255,G=255,B=0,A=32)
     pluginName="Nexgen Auto Team Balancer"
     pluginAuthor="Sp0ngeb0b"
     pluginVersion="1"
}
