class NexgenATB extends NexgenPlugin;

var NexgenATBConfig xConf;                     // Plugin configuration.

var NexgenATBClient ATBClientList;
var int numCurrPlayers;

var float waitFinishTime;
var float initialTeamSortTime;

var int teamStrength[2];

// Sorting
var NexgenATBClient sortedATBClients[32];

// Mid-game join vars
var float midGameJoinTeamSortingTime;
var float longestMidGameJoinWaitTime;

// Sounds
var Sound startSound, playSound, teamSound[2];

// Colors
var Color colorWhite, colorOrange;
var Color TeamColor[4];

const maxInitWaitTime    = 10.0;
const gameStartDelay     = 2.5;
const maxMidGameJoinWait = 5.0;               // Max amount of seconds until a team is assigned for mid-game joined players (starting at ATBClient initialization) 

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
  playSound    = Sound(dynamicLoadObject(xConf.playSound, class'Sound'));
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
  numCurrPlayers++;

  if(numCurrPlayers == 1) waitFinishTime = Level.TimeSeconds;
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

  if(control.gInf != none) {
    ATBClient = getATBClient(client);
    
    if(ATBClient != none && !ATBClient.bSorted) {
      // Player not yet initialized. Disallow play.
      if(control.gInf.gameState == control.gInf.GS_Playing) {
        Level.Game.DiscardInventory(client.player);	
        client.player.PlayerRestartState = 'PlayerWaiting';
        client.player.GotoState(client.player.PlayerRestartState);
      }
      if(control.gInf.gameState == control.gInf.GS_Playing ||
        (control.gInf.gameState == control.gInf.GS_Waiting && initialTeamSortTime != 0.0) ||
         control.gInf.gameState == control.gInf.GS_Starting) {
        ATBClient.bMidGameJoin = true;
      }
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
    
    if(ATBClient.bSorted) {
      teamStrength[client.player.playerReplicationInfo.team] -= ATBClient.strength;
    }
    
    ATBClient.destroy();
    numCurrPlayers--;
  }
  
  if(numCurrPlayers == 1) waitFinishTime = Level.TimeSeconds;
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
  local NexgenATBClient ATBClient;
  
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    if(!ATBClient.bMidGameJoin) {
      // Play announcer
      if(playSound != none) ATBClient.client.player.clientPlaySound(playSound, , true);
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when a player (re)spawns and allows us to modify the player.
 *  $PARAM        client  The client of the player that was respawned.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function playerRespawned(NexgenClient client) {
  local NexgenATBClient ATBClient;
  
  ATBClient = getATBClient(client);
  
  if(ATBClient != none && ATBClient.bMidGameJoin && !ATBClient.bSorted) {  
    Level.Game.DiscardInventory(client.player);	
    client.player.PlayerRestartState = 'PlayerWaiting';
    client.player.GotoState(client.player.PlayerRestartState);
  }

}

function tick(float deltaTime) {
  local int i;
  local int numPlayersInitialized;
  local bool bStillIniting;
  local NexgenClient client;
  local NexgenATBClient ATBClient;
  
  // Waiting state: Handle gamestart and trigger initial sorting
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Waiting) {
  
    // Supress manual game start messages
    if(control.gInf.countDown == 1)  {
      waitFinishTime = Level.TimeSeconds;
      control.gInf.countDown = -1;
    }
    
    // Not yet sorted
    if(initialTeamSortTime == 0.0) {
      // Override team message
      for (client = control.clientList; client != none; client = client.nextClient) {
        if(!client.bSpectator) {
          FlashMessageToPlayer(client, "Teams not yet assigned.", colorOrange);
        }
        if(client.bInitialized) FlashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);
        else                    FlashMessageToPlayer(client, "", colorWhite, 1);        
      }
      
      // Start?
      if(control.gInf.countDown == -1 && numCurrPlayers > 0) {
        // Check if all clients are initialized 
        numPlayersInitialized = numCurrPlayers;
        for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
          if(!ATBClient.bInitialized) {
            bStillIniting = true;
            numPlayersInitialized--;
          }
        }
        
        // Start.
        if(!bStillIniting || (Level.TimeSeconds - waitFinishTime) >= maxInitWaitTime) {
          // Sort the teams.
          initialTeamSorting(numPlayersInitialized);
          initialTeamSortTime = Level.TimeSeconds;
        }
      } 
    } else {
      // Teams sorted. Flash progress messages.
      for (client = control.clientList; client != none; client = client.nextClient) {
        if(!client.bSpectator) {
          ATBClient = getATBClient(client);
          if(ATBClient != none) {
            if(!ATBClient.bMidGameJoin) {
              FlashMessageToPlayer(client ,"You are on "$TeamGamePlus(Level.Game).Teams[client.player.playerReplicationInfo.team].TeamName$".", teamColor[client.player.playerReplicationInfo.team]);
              if(client.bInitialized) FlashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
              else                    FlashMessageToPlayer(client, "", colorWhite, 1); 
            } else {
              // Latecomer. Only show correct messages; mid-game-join sorting not in this state.
              FlashMessageToPlayer(client, "You are not yet assigned to a team.", colorOrange);
              if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
              else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
            }
          }
        } else {
          // Spectators
          if(client.bInitialized) FlashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
          else                    FlashMessageToPlayer(client, "", colorWhite, 1); 
        }        
      }
      if( (Level.TimeSeconds - initialTeamSortTime) >= gameStartDelay) {
        // Continue game start
        control.startGame(true);
      }
    }
  } 
  
  // Starting state: clear progress messages for sorted players and handle latecomers
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Starting) { 
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(!ATBClient.client.bSpectator) {
        // Clear progress messages
        if(!ATBClient.bMidGameJoin) {
          for(i=0; i<7; i++) {
            ATBClient.client.player.SetProgressMessage("", i);
          }
        } else {
          // Latecomer
          if(!ATBClient.bSorted) {
            FlashMessageToPlayer(ATBClient.client, "You are not yet assigned to a team.", colorOrange);
            if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
            else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
          } else {
            if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
              // Clear progress message
              for(i=0; i<7; i++) {
                ATBClient.client.player.SetProgressMessage("", i);
              }
              // Play announcer
              if(playSound != none) ATBClient.client.player.clientPlaySound(playSound, , true);
            }
          }
        }
      }
    }
    if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
      midGameJoinTeamSortingTime = 0.0;
    }
  }
  
  // Playing state: mid-game joined players
  if(control.gInf != none && control.gInf.gameState == control.gInf.GS_Playing) { 
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(!ATBClient.client.bSpectator && ATBClient.client.player.PlayerRestartState == 'PlayerWaiting') {
        if(!ATBClient.bSorted) {
          FlashMessageToPlayer(ATBClient.client, "You are not yet assigned to a team.", colorOrange);
          if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
          else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
        } else {
          if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
            // Clear progress message
            for(i=0; i<7; i++) {
              ATBClient.client.player.SetProgressMessage("", i);
            }
            // Play announcer
            if(playSound != none) ATBClient.client.player.clientPlaySound(playSound, , true);
            
            // Restart player
            ATBClient.client.player.PlayerRestartState = ATBClient.client.player.Default.PlayerRestartState;
            ATBClient.client.player.GotoState(ATBClient.client.player.PlayerRestartState);
            if(!Level.Game.RestartPlayer(ATBClient.client.player)) {
              ATBClient.client.player.GotoState('Dying'); //failed to restart player, so let him try to respawn again
            }
          }
        }
      }
    }
    if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
      midGameJoinTeamSortingTime = 0.0;
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
  local NexgenATBClient ATBClient;
  local int midGameJoinToSort;

  if( midGameJoinTeamSortingTime != 0.0 && longestMidGameJoinWaitTime != 0.0 && (Level.TimeSeconds - longestMidGameJoinWaitTime) > maxMidGameJoinWait) {
    // Check for other waiting clients
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bMidGameJoin && ATBClient.bInitialized && !ATBClient.bSorted) {
        midGameJoinToSort++;
      }
    }
    if(midGameJoinToSort > 0) midGameJoinTeamSorting(midGameJoinToSort);
    else longestMidGameJoinWaitTime = 0.0;
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts the initialized but yet unsorted clients by their strength in the 
 *                sortedATBClients array.
 *
 **************************************************************************************************/
function sortClientsByStrength(int amount) {
  local int i, max;
  local NexgenATBClient ATBClient, maxATBClient; 

  // Clear temp array  
  for(i=0; i<ArrayCount(sortedATBClients); i++) sortedATBClients[i] = none;

  for(i=0; i<amount; i++) {
    max = -1;
    
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(!ATBClient.bInitialized || ATBClient.bSorted) continue;
      
      if(ATBClient.strength > max) {
        maxATBClient = ATBClient;
        max = ATBClient.strength;
      }
    }

    if(max == -1) {
      log("[NATB]: max == -1!");
      break;
    }
    
    sortedATBClients[i] = maxATBClient;   
    maxATBClient.bSorted = true;    
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Performs a full team sorting at gamestart.
 *
 **************************************************************************************************/
function initialTeamSorting(int numPlayersInitialized) {
  local NexgenClient client;
  local int i, currTeam, actualCurrTeam, direction, weakestTeam;
  local bool bFlip;
  
  // Sort clients by strength
  sortClientsByStrength(numPlayersInitialized);

  // Build teams
  // Scheme: red-blue-blue-red-red-... or vice versa
  if(FRand() < 0.5) bFlip = true;
  direction = 1;
  for(i=0; i<(numPlayersInitialized&254); i++) {
    if (bFlip) actualCurrTeam = TeamGamePlus(Level.Game).MaxTeams - 1 - currTeam;
    else       actualCurrTeam = currTeam; 
   
    // Move player and update team strength
    sortedATBClients[i].client.setTeam(actualCurrTeam);
    teamStrength[actualCurrTeam] += sortedATBClients[i].strength;
    
    // Work out next team
    currTeam = currTeam + direction;
    if(currTeam == TeamGamePlus(Level.Game).MaxTeams) {
      currTeam--; 
      direction = -1;
    } else if(currTeam == -1) {
      currTeam++; 
      direction = 1;
    }
  }
  
  // If there is an odd number of players put the last player in the weakest team
  if((numPlayersInitialized&1) == 1) {
    if(getTeamStrengthWithFlagStrength(0) < getTeamStrengthWithFlagStrength(1)) weakestTeam = 0;  
    else weakestTeam = 1;
    
    sortedATBClients[numPlayersInitialized-1].client.setTeam(weakestTeam);
    teamStrength[weakestTeam] += sortedATBClients[numPlayersInitialized-1].strength;
  }
  
  // Announce team
  for (i=0; i<numPlayersInitialized; i++) {
    if(startSound != none) sortedATBClients[i].client.player.PlaySound(startSound, SLOT_Interface, 255.0);
    if(sortedATBClients[i].client.player.playerReplicationInfo.team == 0 || sortedATBClients[i].client.player.playerReplicationInfo.team == 1) {
      if(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team] != none) sortedATBClients[i].client.player.clientPlaySound(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team], , true);
    }
  }
  
  // Announce strengths
  for (client = control.clientList; client != none; client = client.nextClient) {
    client.showMsg("<C04>Red team strength is "$teamStrength[0]$", Blue team strength is "$teamStrength[1]$".");
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts the mid-game joined players into the teams. Considers the currently weakest
 *                team (including flag captures).
 *
 **************************************************************************************************/
function midGameJoinTeamSorting(int midGameJoinToSort) {
  local int i, weakestTeam;
  local int start, end;
  local int teamSizes[2];
  
  // Sort waiting clients by strength
  sortClientsByStrength(midGameJoinToSort);
  
  // Work out weakest team
  if(getTeamStrengthWithFlagStrength(0) < getTeamStrengthWithFlagStrength(1)) weakestTeam = 0;  
  else weakestTeam = 1;
  
  // Get current team sizes
  getTeamSizes(teamSizes);
  
  // Case differentiation depending on team sizes
  // Ensures that the team amount is even from here
  start = 0;
  end = midGameJoinToSort;
  if(teamSizes[weakestTeam] > teamSizes[int(!bool(weakestTeam))]) {
    // The weakest team already has the number advantage
    // Put the weakest player into the stronger team
    sortedATBClients[midGameJoinToSort-1].client.setTeam(int(!bool(weakestTeam)));
    teamStrength[int(!bool(weakestTeam))] += sortedATBClients[midGameJoinToSort-1].strength;
    end = midGameJoinToSort-1;
  } else if(teamSizes[weakestTeam] < teamSizes[int(!bool(weakestTeam))]) {
    // The weakest team has the number disadvantage
    // Put the strongest player into the weaker team
    sortedATBClients[0].client.setTeam(weakestTeam);
    teamStrength[weakestTeam] += sortedATBClients[0].strength;
    start = 1;
  } 

  // Build teams
  // Scheme: weak-strong-weak-strong-...
  for(i=start; i<end; i++) {
    // Move player and update team strength
    sortedATBClients[i].client.setTeam(weakestTeam);
    teamStrength[weakestTeam] += sortedATBClients[i].strength;

    weakestTeam = int(!bool(weakestTeam));
  }  
  // Announce
  for(i=0; i<midGameJoinToSort; i++) {
    FlashMessageToPlayer(sortedATBClients[i].client, "You are on "$TeamGamePlus(Level.Game).Teams[sortedATBClients[i].client.player.playerReplicationInfo.team].TeamName$".", teamColor[sortedATBClients[i].client.player.playerReplicationInfo.team]);
    FlashMessageToPlayer(sortedATBClients[i].client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
    if(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team] != none) sortedATBClients[i].client.player.clientPlaySound(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team],  ,true);
  }
  
  // Reset counters
  longestMidGameJoinWaitTime = 0;
  
  // Save time
  midGameJoinTeamSortingTime = Level.TimeSeconds;
}

function ATBClientInit(NexgenATBClient ATBClient) {
  local int midGameJoinToSort;
  local bool bBetterWait;
  
  if(control.gInf == none) return;

  if( (control.gInf.gameState == control.gInf.GS_Waiting && initialTeamSortTime != 0.0) ||
       control.gInf.gameState == control.gInf.GS_Starting) {
    // Player did not get considered for initial team sorting
    // TODO
  } else if(control.gInf.gameState == control.gInf.GS_Playing) {
    // Player initialized mid-game
    
    // Check for other waiting clients
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bMidGameJoin && !ATBClient.bSorted) {
        if(!ATBClient.bInitialized) bBetterWait = true;
        else                        midGameJoinToSort++;
      }
    }
    
    if(!bBetterWait && midGameJoinTeamSortingTime == 0.0) {
      midGameJoinTeamSorting(midGameJoinToSort);
    } else if(longestMidGameJoinWaitTime == 0) {
      longestMidGameJoinWaitTime = Level.TimeSeconds;
    }
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

function int getTeamStrengthWithFlagStrength(byte teamNum) {
  return teamStrength[teamNum] + TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[teamNum].Score * xConf.flagStrength;
}

// Without players waiting for team assignment
function int getTeamSizes(out int teamSizes[2]) {
  local NexgenATBClient ATBClient;

	// Get current team sizes.
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
		if (!ATBClient.client.bSpectator && !ATBClient.bSorted && 0 <= ATBClient.client.player.playerReplicationInfo.team && ATBClient.client.player.playerReplicationInfo.team < 2) {
			teamSizes[ATBClient.client.player.playerReplicationInfo.team]++;
		}
	}
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
