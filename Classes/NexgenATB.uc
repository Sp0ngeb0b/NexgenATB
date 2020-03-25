class NexgenATB extends NexgenPlugin;

var NexgenATBConfig xConf;                     // Plugin configuration.

var NexgenATBClient ATBClientList;
var int numCurrPlayers;

var float waitFinishTime;
var float initialTeamSortTime;

var int teamStrength[2];

// Mid-game join vars
var float midGameJoinTeamSortingTime;
var float longestMidGameJoinWaitTime;

// Reconnect vars
var float  lastDisconnectTime;
var string lastDisconnectID;
var byte   lastDisconnectTeam;

// Sounds
var Sound startSound, playSound, teamSound[2];

// Colors
var Color colorWhite, colorOrange, TeamColor[4];

const PA_ConfIndex = "natb_configIndex";
const PA_Strength  = "natb_strength";
const PA_PlayTime  = "natb_playTime";

const minSinglePlayerWaitTime  = 8.0;          // Min amount of seconds a single player in the server has to wait before the game starts
const maxInitWaitTime          = 5.0;          // Max amount of seconds the initial sorting can be delayed when waiting for a client to init
const gameStartDelay           = 2.5;          // Amount of seconds to wait after a team is assigned before proceeding
const minMidGameJoinWaitTime   = 3.0;          // Min amount of seconds a mid-game joined player waits for team assignment (starting at ATBClient initialization) 
const maxMidGameJoinWaitTime   = 5.0;          // Max amount of seconds until a team is assigned for mid-game joined players (starting at ATBClient initialization) 
const maxReconnectWaitTime     = 8.0;          // Max amount of seconds to wait for a player to reconnect. Teams will not be rebalanced until then, except new player join. 

const oddPlayerChangeThreshold = 10;           // Threshold in strength difference improvement after which the last player will switch teams in case off an odd player amount
const prefToChangeNewPlayers   = 0.5;          // Factor how to weight playtime into mid-game rebalances [0,1]. 
const flagCarrierFactor        = 10.0;         // Rating punishment if client is a flag carrier (>=1).

const newLineToken = "\\n";                    // Token used to detect new lines in texts

const bWindowedStrengthMsgs = false;

/***************************************************************************************************
 *
 *  $DESCRIPTION  Initializes the plugin. Note that if this function returns false the plugin will
 *                be destroyed and is not to be used anywhere.
 *  $RETURN       True if the initialization succeeded, false if it failed.
 *  $OVERRIDE
 *
 **************************************************************************************************/
function bool initialize() {

  if(TeamGamePlus(Level.Game) == none || TeamGamePlus(Level.Game).MaxTeams != 2) return false;

  if(!control.sConf.enableNexgenStartControl) {
    TeamGamePlus(Level.Game).bBalanceTeams = true;
    return false;
  } else {
    TeamGamePlus(Level.Game).bBalanceTeams = false;
  }

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

  spawn(class'NexgenATBMessageMutator', self);
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
    
    if(ATBClient != none) {
      // Reconnect?
      if(client.playerID == lastDisconnectID && (Level.TimeSeconds - lastDisconnectTime) <= maxReconnectWaitTime) {
        ATBClient.configIndex = client.pDat.getInt(PA_ConfIndex, -1);
        ATBClient.strength    = client.pDat.getInt(PA_Strength,  xConf.defaultStrength);
        ATBClient.playTime   += client.pDat.getInt(PA_PlayTime,  0);

        lastDisconnectID = "";
        
        if(ATBClient.configIndex != -1) {
          ATBClient.bInitialized = true;
          ATBClient.bMidGameJoin = true;
          assignTeam(ATBClient, lastDisconnectTeam);
          teamStrength[lastDisconnectTeam] += ATBClient.strength;
          return;
        }
      }
      
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
      
      ATBClient.locateDataEntry();
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
    
    if(ATBClient.bTeamAssigned) {
      teamStrength[client.player.playerReplicationInfo.team] -= ATBClient.strength;
      lastDisconnectTime = Level.TimeSeconds;
      lastDisconnectID   = client.playerID;
      lastDisconnectTeam = client.player.playerReplicationInfo.team;
      client.pDat.set(PA_ConfIndex,  ATBClient.configIndex);
      client.pDat.set(PA_Strength,   ATBClient.strength);
      client.pDat.set(PA_PlayTime,   ATBClient.playTime+client.timeSeconds);
    }
    
    ATBClient.destroy();
    numCurrPlayers--;
  }
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
    if(ATBClient.bTeamAssigned) {
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
  
  if(ATBClient != none && ATBClient.bMidGameJoin && !ATBClient.bTeamAssigned) {  
    Level.Game.DiscardInventory(client.player);	
    client.player.PlayerRestartState = 'PlayerWaiting';
    client.player.GotoState(client.player.PlayerRestartState);
  }

}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Deals with a client that has switched to another team.
 *  $PARAM        client  The client that has changed team.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function playerTeamChanged(NexgenClient client) {
	local NexgenATBClient ATBClient;
  
  ATBClient = getATBClient(client);
  
  if(ATBClient != none && ATBClient.bTeamAssigned) {
    if(ATBClient.bTeamSwitched) {
      ATBClient.bTeamSwitched = false;
    } else  {
      // Manual team change, adjust team strength
      teamStrength[client.team]             += ATBClient.strength;
      teamStrength[int(!bool(client.team))] -= ATBClient.strength;
      lastDisconnectID = "";
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when the game executes its next 'game' tick.
 *
 **************************************************************************************************/
function tick(float deltaTime) {
  local int i;
  local int numPlayersInitialized;
  local bool bStillIniting;
  local float playerJoinTime;
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
      
      // Single player?
      if(numCurrPlayers == 1) {
        for(client = control.clientList; client != none; client = client.nextClient) {
          if(!client.bSpectator) {
             playerJoinTime = client.timeSeconds; 
             break;
          }
        }
      } else playerJoinTime = -1;
      
      // Start?
      if(control.gInf.countDown == -1 && numCurrPlayers > 0 && (playerJoinTime == -1 || playerJoinTime > minSinglePlayerWaitTime)) {
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
        if(!ATBClient.bMidGameJoin) {
          // Clear progress messages
          for(i=0; i<7; i++) ATBClient.client.player.SetProgressMessage("", i);
        } else {
          // Latecomer
          if(!ATBClient.bTeamAssigned) {
            FlashMessageToPlayer(ATBClient.client, "You are not yet assigned to a team.", colorOrange);
            if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
            else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
          } else {
            if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
              // Clear progress message
              for(i=0; i<7; i++) ATBClient.client.player.SetProgressMessage("", i);
            } else {
              FlashMessageToPlayer(ATBClient.client, "You are on "$TeamGamePlus(Level.Game).Teams[ATBClient.client.player.playerReplicationInfo.team].TeamName$".", teamColor[ATBClient.client.player.playerReplicationInfo.team]);
              FlashMessageToPlayer(ATBClient.client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
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
        if(!ATBClient.bTeamAssigned) {
          FlashMessageToPlayer(ATBClient.client, "You are not yet assigned to a team.", colorOrange);
          if(!ATBClient.bInitialized) FlashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
          else                        FlashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
        } else {
          if(midGameJoinTeamSortingTime != 0.0 && (Level.TimeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
            // Clear progress message
            for(i=0; i<7; i++) ATBClient.client.player.SetProgressMessage("", i);
            
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
  local bool bBetterWait;
  local int midGameJoinToSort;
  local int teamSizes[2];

  // Mid-game-joins
  if( midGameJoinTeamSortingTime == 0.0 && longestMidGameJoinWaitTime != 0.0 && (Level.TimeSeconds - longestMidGameJoinWaitTime) > minMidGameJoinWaitTime) {
    // Check for other waiting clients
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bMidGameJoin && !ATBClient.bTeamAssigned) {
        if(!ATBClient.bInitialized) bBetterWait = true;
        else                        midGameJoinToSort++;
      }
    }
   
    if(!bBetterWait || (Level.TimeSeconds - longestMidGameJoinWaitTime) > maxMidGameJoinWaitTime) {
      if(midGameJoinToSort > 0) midGameJoinTeamSorting(midGameJoinToSort);
      else longestMidGameJoinWaitTime = 0.0;
    }
  }
  
  // Check for unbalance
  if(control.gInf != none && (control.gInf.gameState == control.gInf.GS_Starting || control.gInf.gameState == control.gInf.GS_Playing)) {
    getTeamSizes(teamSizes, true);
    
    if(abs(teamSizes[0] - teamSizes[1]) > 1) {
      // Check for waiting clients
      for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
        if(!ATBClient.bTeamAssigned) break;
      }
      // No waiting clients
      if(ATBClient == none) {
        // Wait for reconnect?
        if(lastDisconnectID == "" || (Level.TimeSeconds - lastDisconnectTime) > maxReconnectWaitTime) {
          // No, rebalance now!
          midGameRebalanceTeamSize();
        }
      }
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts the initialized but yet unsorted clients by their strength in the 
 *                sortedATBClients array.
 *
 **************************************************************************************************/
function sortNewClientsByStrength(int amount, out NexgenATBClient sortedATBClients[32]) {
  local NexgenATBClient ATBClient, maxATBClient; 
  local int i, max;
  
  // Reset sorted flag
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    ATBClient.bSortedByStrength = false;
  }
  
  // Sort
  for(i=0; i<amount; i++) {
    max = -1;
    
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(!ATBClient.bInitialized || ATBClient.bSortedByStrength) continue;
      
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
    maxATBClient.bSortedByStrength = true;    
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts clients of one team by strength
 *
 **************************************************************************************************/
function sortTeamClientsByStrength(int amount, byte team, out NexgenATBClient sortedATBClients[32]) {
  local NexgenATBClient ATBClient, maxATBClient; 
  local int i, max;

  // Reset sorted flag
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    ATBClient.bSortedByStrength = false;
  }
  
  // Sort
  for(i=0; i<amount; i++) {
    max = -1;
    
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bSortedByStrength || ATBClient.client.player.playerReplicationInfo.team != team) continue;
      
      if(ATBClient.strength > max) {
        maxATBClient = ATBClient;
        max = ATBClient.strength;
      }
    }

    if(max == -1) {
      log("[NATB]: max == -1 at team sorting!");
      break;
    }
    
    sortedATBClients[i] = maxATBClient;   
    maxATBClient.bSortedByStrength = true;    
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Returns the best possible switch by rating each client.
 *                This rating considers the goal strength difference to fulfill, as well as the
 *                playtime of the clients and whether they carry the flag.
 *                A low rating is desired.
 *
 **************************************************************************************************/
function NexgenATBClient getBestSwitch(byte team, int difference) {
  local NexgenATBClient ATBClient, minATBClient; 
  local int newDifference;
  local float playTime;

  // Compute strength rating and find min
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    if(ATBClient.client.player.playerReplicationInfo.team == team) {
      newDifference = abs(difference - ATBClient.strength*2);
      playTime = ATBClient.playTime+ATBClient.client.timeSeconds;
      ATBClient.strengthRating = 200*(5+newDifference) * (1.0-prefToChangeNewPlayers) + 2.0*playTime * prefToChangeNewPlayers; // Magic formular taken from ATB
      
      if(ATBClient.client.player.playerReplicationInfo.hasFlag != none) ATBClient.strengthRating *= flagCarrierFactor;
      
      if(minATBClient == none || minATBClient.strengthRating > ATBClient.strengthRating) minATBClient = ATBClient;
    }
  } 
  return minATBClient;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Performs a full team sorting at gamestart.
 *
 **************************************************************************************************/
function initialTeamSorting(int numPlayersInitialized) {
  local NexgenATBClient sortedATBClients[32];
  local NexgenClient client;
  local int i, currTeam, actualCurrTeam, direction, weakerTeam;
  local bool bFlip;
  
  // Sort clients by strength
  sortNewClientsByStrength(numPlayersInitialized, sortedATBClients);

  // Build teams
  // Scheme: red-blue-blue-red-red-... or vice versa
  if(FRand() < 0.5) bFlip = true;
  direction = 1;
  for(i=0; i<(numPlayersInitialized&254); i++) {
    if (bFlip) actualCurrTeam = TeamGamePlus(Level.Game).MaxTeams - 1 - currTeam;
    else       actualCurrTeam = currTeam; 
   
    // Move player and update team strength
    assignTeam(sortedATBClients[i], actualCurrTeam);
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
    if(getTeamStrengthWithFlagStrength(0) > getTeamStrengthWithFlagStrength(1)) weakerTeam = 1;  
    
    assignTeam(sortedATBClients[numPlayersInitialized-1], weakerTeam);
    teamStrength[weakerTeam] += sortedATBClients[numPlayersInitialized-1].strength;
  }
  
  // Announce team
  for (i=0; i<numPlayersInitialized; i++) {
    if(startSound != none) sortedATBClients[i].client.player.PlaySound(startSound, SLOT_Interface, 255.0);
    if(sortedATBClients[i].client.player.playerReplicationInfo.team == 0 || sortedATBClients[i].client.player.playerReplicationInfo.team == 1) {
      if(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team] != none) sortedATBClients[i].client.player.clientPlaySound(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team], , true);
    }
  }
  
  // Announce strengths
  control.broadcastMsg("<C04>Nexgen Auto Team Balancer is assigning teams...");
  control.broadcastMsg("<C04>Red team strength is "$teamStrength[0]$", Blue team strength is "$teamStrength[1]$".");
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts the mid-game joined players into the teams. Considers the currently weakest
 *                team (including flag captures).
 *
 **************************************************************************************************/
function midGameJoinTeamSorting(int midGameJoinToSort) {
  local NexgenATBClient sortedATBClients[32];
  local int i, weakerTeam, strongerTeam;
  local int start, end;
  local int teamSizes[2];
  
  // Sort waiting clients by strength
  sortNewClientsByStrength(midGameJoinToSort, sortedATBClients);
  
  // Work out weakest team
  if(getTeamStrengthWithFlagStrength(0) > getTeamStrengthWithFlagStrength(1)) weakerTeam = 1;  
  strongerTeam = int(!bool(weakerTeam));
  
  // Get current team sizes (excluding joined players)
  getTeamSizes(teamSizes, true);
    
  // Case differentiation depending on team sizes
  // Ensures that the team amount is even from here
  start = 0;
  end = midGameJoinToSort;
  if(teamSizes[weakerTeam] > teamSizes[strongerTeam]) {
    // The weakest team already has the number advantage
    // Put the weakest player into the stronger team
    assignTeam(sortedATBClients[midGameJoinToSort-1], strongerTeam);
    teamStrength[strongerTeam] += sortedATBClients[midGameJoinToSort-1].strength;
    end = midGameJoinToSort-1;
  } else if(teamSizes[weakerTeam] < teamSizes[strongerTeam]) {
    // The weakest team has the number disadvantage
    // Put the strongest player into the weaker team
    assignTeam(sortedATBClients[0], weakerTeam);
    teamStrength[weakerTeam] += sortedATBClients[0].strength;
    start = 1;
  } 

  // Build teams
  // Scheme: weak-strong-weak-strong-...
  for(i=start; i<end; i++) {
    // Move player and update team strength
    assignTeam(sortedATBClients[i], weakerTeam);
    teamStrength[weakerTeam] += sortedATBClients[i].strength;

    weakerTeam = strongerTeam;
  }  
  // Announce
  for(i=0; i<midGameJoinToSort; i++) {
    FlashMessageToPlayer(sortedATBClients[i].client, "You are on "$TeamGamePlus(Level.Game).Teams[sortedATBClients[i].client.player.playerReplicationInfo.team].TeamName$".", teamColor[sortedATBClients[i].client.player.playerReplicationInfo.team]);
    FlashMessageToPlayer(sortedATBClients[i].client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
    if(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team] != none) sortedATBClients[i].client.player.clientPlaySound(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team], , true);
  }
  
  // Reset
  longestMidGameJoinWaitTime = 0;
  lastDisconnectID = "";
  
  // Save time
  midGameJoinTeamSortingTime = Level.TimeSeconds;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Rebalances in case the teams become unbalance in size.
 *                No waiting clients must be ensured.
 *
 **************************************************************************************************/
function midGameRebalanceTeamSize() {
  local NexgenATBClient sortedATBClientsLargerTeam[32];
  local NexgenATBClient preferedATBClient;
  local int teamSizes[2];
  local int largerTeam, smallerTeam, sizeDifference, strengthDifference;
  local int nextPlayerToMove;
  local int movedPlayerAmount;
  local int i;
  
  // Figure out what to do
  getTeamSizes(teamSizes);
  if(teamSizes[1] > teamSizes[0]) largerTeam = 1;
  smallerTeam = int(!bool(largerTeam));
  
  sizeDifference = abs(teamSizes[0] - teamSizes[1]);
  if(sizeDifference <= 1) return;

  // Oops, larger team is weaker than the smaller team! Move weakest players.
  if(getTeamStrengthWithFlagStrength(largerTeam) < getTeamStrengthWithFlagStrength(smallerTeam)) {
    // Get sorted strenghts
    sortTeamClientsByStrength(teamSizes[largerTeam], largerTeam, sortedATBClientsLargerTeam);
    nextPlayerToMove = teamSizes[largerTeam] - 1;
    do {
      if(sortedATBClientsLargerTeam[nextPlayerToMove].client.player.playerReplicationInfo.hasFlag != none) nextPlayerToMove--;
      
      assignTeam(sortedATBClientsLargerTeam[nextPlayerToMove], smallerTeam);
      teamStrength[largerTeam]  -= sortedATBClientsLargerTeam[nextPlayerToMove].strength;
      teamStrength[smallerTeam] += sortedATBClientsLargerTeam[nextPlayerToMove].strength;
      
      // Inform player
      for(i=0; i<7; i++)   sortedATBClientsLargerTeam[nextPlayerToMove].client.player.SetProgressMessage("", i);
      FlashMessageToPlayer(sortedATBClientsLargerTeam[nextPlayerToMove].client, "Assigned to "$TeamGamePlus(Level.Game).Teams[smallerTeam].TeamName$" due to unbalanced team sizes!", teamColor[smallerTeam]);
      
      movedPlayerAmount++;
      nextPlayerToMove--;
      sizeDifference -= 2;
    } until(sizeDifference <= 1);
  
  } else {    
    do {
      strengthDifference = getTeamStrengthWithFlagStrength(largerTeam) - getTeamStrengthWithFlagStrength(smallerTeam);
      preferedATBClient = getBestSwitch(largerTeam, strengthDifference);
      
      // Manual check when player amount is odd
      if(sizeDifference == 1 && strengthDifference < abs(strengthDifference-preferedATBClient.strength*2)+oddPlayerChangeThreshold) {
        break;
      }
     
      assignTeam(preferedATBClient, smallerTeam);
      teamStrength[largerTeam]  -= preferedATBClient.strength;
      teamStrength[smallerTeam] += preferedATBClient.strength;
      
      // Inform player 
      for(i=0; i<7; i++)   preferedATBClient.client.player.SetProgressMessage("", i);
      FlashMessageToPlayer(preferedATBClient.client, "Assigned to "$TeamGamePlus(Level.Game).Teams[smallerTeam].TeamName$" due to unbalanced team sizes!", teamColor[smallerTeam]);

      movedPlayerAmount++;
      sizeDifference -= 2;
    } until(sizeDifference < 1);
    
  }
  
  // Announce strengths
  control.broadcastMsg("<C04>Nexgen Auto Team Balancer moved "$movedPlayerAmount$" player(s) due to unbalanced team sizes!");
  control.broadcastMsg("<C04>Red team strength is "$getTeamStrengthWithFlagStrength(0)$", Blue team strength is "$getTeamStrengthWithFlagStrength(1)$".");
  
  // Reset
  lastDisconnectID = "";
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called by an ATBClient instance when it is ready to be sorted.
 *
 **************************************************************************************************/
function ATBClientInit(NexgenATBClient ATBClient) {
  local int midGameJoinToSort;
  local bool bBetterWait;
  
  if(control.gInf == none) return;

  if( (control.gInf.gameState == control.gInf.GS_Waiting && initialTeamSortTime != 0.0) ||
       control.gInf.gameState == control.gInf.GS_Starting ||
       control.gInf.gameState == control.gInf.GS_Playing) {
    
    // Check for other waiting clients
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bMidGameJoin && !ATBClient.bTeamAssigned) {
        if(!ATBClient.bInitialized) bBetterWait = true;
        else                        midGameJoinToSort++;
      }
    }
    
    // Sort now?
    if(!bBetterWait && midGameJoinTeamSortingTime == 0.0 && longestMidGameJoinWaitTime != 0.0 && (Level.TimeSeconds - longestMidGameJoinWaitTime) > minMidGameJoinWaitTime) {
      midGameJoinTeamSorting(midGameJoinToSort);
    } else if(longestMidGameJoinWaitTime == 0) {
      // First client waiting, sort later
      longestMidGameJoinWaitTime = Level.TimeSeconds;
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Overrides the progress messages. Taken from ATB 1.5.
 *
 **************************************************************************************************/
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
   targetLine = 2; // At least true for CTF

  client.player.SetProgressTime(5);
  client.player.SetProgressColor(msgColor,targetLine+offset);
  client.player.SetProgressMessage(Msg,targetLine+offset);  
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Moves a client to a different team.
 *
 **************************************************************************************************/
function assignTeam(NexgenATBClient ATBClient, byte newTeam) {
  ATBClient.bTeamAssigned = true;
  if(newTeam != ATBClient.client.player.playerReplicationInfo.team) {
    ATBClient.client.setTeam(newTeam);
    ATBClient.bTeamSwitched = true;
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Team strengths including flag bonus
 *
 **************************************************************************************************/
function int getTeamStrengthWithFlagStrength(byte teamNum) {
  return teamStrength[teamNum] + TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[teamNum].Score * xConf.flagStrength;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Retrieves team sizes excluding players waiting for team assignment
 *
 **************************************************************************************************/
function getTeamSizes(out int teamSizes[2], optional bool bExcludeWaitingPlayers) {
  local NexgenATBClient ATBClient;

	// Get current team sizes.
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
		if (!ATBClient.client.bSpectator && (!bExcludeWaitingPlayers || ATBClient.bTeamAssigned) && 0 <= ATBClient.client.player.playerReplicationInfo.team && ATBClient.client.player.playerReplicationInfo.team < 2) {
			teamSizes[ATBClient.client.player.playerReplicationInfo.team]++;
		}
	}
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Handles a potential command message.
 *  $PARAM        sender  PlayerPawn that has send the message in question.
 *  $PARAM        msg     Message send by the player, which could be a command.
 *  $REQUIRE      sender != none
 *  $RETURN       True if the specified message is a command, false if not.
 *  $OVERRIDE
 *
 **************************************************************************************************/
function bool handleOurMsgCommands(PlayerPawn sender, string msg) {
	local string cmd;
	local bool bIsCommand;
  local int teamStrenthToShow;
  local NexgenClient client;
  
  client = control.getClient(sender);
  
  if(client == none) return false;

	cmd = class'NexgenUtil'.static.trim(msg);
	bIsCommand = true;
  teamStrenthToShow = -1;
	switch (cmd) {
		case "!teams": case "!team": case "!t": case "!stats":
      if(initialTeamSortTime == 0) client.showMsg("<C00>Teams not yet assigned.");
      else { 
        client.showMsg("<C04>Red team strength is "$getTeamStrengthWithFlagStrength(0)$", Blue team strength is "$getTeamStrengthWithFlagStrength(1)$" (difference -"$int(abs(getTeamStrengthWithFlagStrength(0)-getTeamStrengthWithFlagStrength(1)))$").");
        client.showMsg("<C04>Say '!strength' for more details.");
      }
    break;
    
    // Detailed strength info requested?
    case "!strength": client.showMsg("<C04>Usage: '!strength <red/blue>'"); break;
    case "!strength red": case "!strength 0":  teamStrenthToShow = 0; break;
    case "!strength blue": case "!strength 1": teamStrenthToShow = 1; break;

    // Not a command.
		default: bIsCommand = false;
	}
  
  // Display detailed strength info via Nexgen's PM function (proper formatting and accessible as server side only plugin)
  if(teamStrenthToShow != -1) {
    NexgenClientCore(client.getController(class'NexgenClientCore'.default.ctrlID)).receivePM(client.playerID, client.player.playerReplicationInfo, getStrengthsString(teamStrenthToShow), bWindowedStrengthMsgs, true);
    if(!bWindowedStrengthMsgs) client.showPanel(class'NexgenRCPPrivateMsg'.default.panelIdentifier);
  }

	return bIsCommand;  
}
   
/***************************************************************************************************
 *
 *  $DESCRIPTION  Constructs a string containing the (sorted) strength of each member of a team.
 *
 **************************************************************************************************/
function string getStrengthsString(byte team) {
  local string res, seperatorToken;
  local int teamSizes[2];
  local NexgenATBClient sortedATBClients[32];
  local int i;
  
  // Sort by strength
  getTeamSizes(teamSizes, true);
  sortTeamClientsByStrength(teamSizes[team], team, sortedATBClients);
  
  // Which mode?
  if(bWindowedStrengthMsgs) seperatorToken = "  |  ";
  else {
    seperatorToken = newLineToken;
    res = newLineToken$newLineToken;
  }
  
  // Construct string
  res = res$"Nexgen Auto Team Balance "$TeamGamePlus(Level.Game).Teams[team].TeamName$" Team Strengths:"$newLineToken;
  if(!bWindowedStrengthMsgs) res = res $newLineToken;
  for(i=0; i<teamSizes[team]; i++) {
    res = res$sortedATBClients[i].client.playerName$": "$string(sortedATBClients[i].strength);
    if(i != teamSizes[team]-1) res = res$seperatorToken;
  }
  
  return res;
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
