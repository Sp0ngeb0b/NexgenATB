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
class NexgenATB extends NexgenPlugin;

var int versionNum;                            // Plugin version number.

// References
var NexgenATBConfig xConf;                     // Plugin configuration.
var NexgenATBClient ATBClientList;             // First client of our own client list.
var NexgenATBClient ATBDisconnectedtList;      // First client of our own disconnected client list.

// Team specific vars
var float teamStrength[2];                     // Current accumulated strength of the teams (without flag strength). 
var float teamScore[2];                        // Last known team score, used to detect changes of accumulated flag strength.

// Time vars
var float waitFinishTime;                      // Time at which the initial waiting timer at gamestart ran out.
var float initialTeamSortTime;                 // Time at which the initial team sorting took place.
var float midGameJoinTeamSortingTime;          // Time at which the latest mid-game-join sorting took place. Will be reset to 0 once players left waiting mode.
var float longestMidGameJoinWaitTime;          // Time at which the earliest mid-game-joined client was ready to be sorted.
var float lastDisconnectTime;                  // Last time a player disconnected.
var float lastStrengthChangeTime;              // Last time the strength of the teams was modified.

// Other vars
var int numCurrPlayers;                        // Current amount of players (can be in waiting state). Used to detect when only a single player is connected.
var bool bStrengthsUpdated;                    // Strengths updated at end of game?

// Resources
var Sound startSound, playSound, teamSound[2];
var Color colorWhite, colorOrange, TeamColor[4];

// Constants
const minSinglePlayerWaitTime  = 10.0;         // Min amount of seconds a single player in the server has to wait before the game starts.
const maxInitWaitTime          = 5.0;          // Max amount of seconds the initial sorting can be delayed when waiting for a client to init.
const gameStartDelay           = 2.5;          // Amount of seconds to wait after a team is assigned before proceeding.
const minMidGameJoinWaitTime   = 3.0;          // Min amount of seconds a mid-game joined player waits for team assignment (starting at ATBClient initialization). 
const maxMidGameJoinWaitTime   = 5.0;          // Max amount of seconds until a team is assigned for mid-game joined players (starting at ATBClient initialization). 
const maxReconnectWaitTime     = 8.0;          // Max amount of seconds to wait for a player to reconnect. Teams will not be rebalanced until then, except new player join. 

const oddPlayerChangeThreshold = 10;           // Threshold in strength difference improvement after which the last player will switch teams in case off an odd player amount.
const prefToChangeNewPlayers   = 0.5;          // Factor how to weight playtime into mid-game rebalances [0,1]. 
const flagCarrierFactor        = 10.0;         // Rating punishment if client is a flag carrier (>=1).
                                               
const minPlayTimeForUpdate     = 90;           // Min time in seconds a player must have been on the server to update his strength.   
const minPlayTimeForWinBonus   = 180;          // Min time in seconds a player must have been on the server to get the winning team bonus.

const endUpdateDelay           = 3.0;          // Seconds to wait before updating the database on game end.
const minPlayerAmount          = 2;            // Min amount of participating players to update the strengths.
const normalisedStrength       = 50;           // Average strength we are aiming for when normalising.
const relNormalisationProp     = 0.5;          // Percentage to weight the total average strength of participating players when normalising [0,1].
const hoursBeforeRecyStrength  = 4.0;          // Amount of hours played to consider when weighting strength of current game against saved strength.
                
const teamAssignMsgsDuration   = 3.0;               
const specProgressMsgDuration  = 7.0;          //                               
                                        
const newLineToken = "\\n";                    // Token used to detect new lines in texts

/***************************************************************************************************
 *
 *  $DESCRIPTION  Initializes the plugin. Note that if this function returns false the plugin will
 *                be destroyed and is not to be used anywhere.
 *  $RETURN       True if the initialization succeeded, false if it failed.
 *  $OVERRIDE
 *
 **************************************************************************************************/
function bool initialize() {

  // Check if supported gametype
  if(TeamGamePlus(Level.Game) == none || TeamGamePlus(Level.Game).MaxTeams != 2) {
    control.nscLog("[NATB] Not a team game or more than 2 teams, not initialising ...");
    return false;
  }
  
  // Turned off?
  if(!control.sConf.enableNexgenStartControl) {
    TeamGamePlus(Level.Game).bPlayersBalanceTeams = true;
    control.nscLog("[NATB] enableNexgenStartControl is disabled, not initialising ...");
    return false;
  }
  
  // Disable for the current game?
  if(!control.sConf.enableNexgenStartControl || control.sConf.matchModeActivated || control.gInf.bTournamentMode) {
    TeamGamePlus(Level.Game).bPlayersBalanceTeams = true;
    control.nscLog("[NATB] Match mode or tournament active; deactivating for the current game ...");
    return false;
  }
  
  // We explicitly allow uneven team sizes
  TeamGamePlus(Level.Game).bPlayersBalanceTeams = false;

  // Load settings.
  if (control.bUseExternalConfig) {
    xConf = spawn(class'NexgenATBConfigExt', self);
  } else {
    xConf = spawn(class'NexgenATBConfigSys', self);
  }
  if(xConf == none) return false;
  xConf.xControl = self;
  xConf.install();
  
  // Load sounds
  startSound   = Sound(dynamicLoadObject(xConf.startSound, class'Sound'));
  playSound    = Sound(dynamicLoadObject(xConf.playSound, class'Sound'));
  teamSound[0] = Sound(dynamicLoadObject(xConf.teamSound[0], class'Sound'));
  teamSound[1] = Sound(dynamicLoadObject(xConf.teamSound[1], class'Sound'));

  // Spawn additional actors
  spawn(class'NexgenATBMessageMutator', self);
  control.teamBalancer = spawn(class'NexgenATBDisabler', self);
  
  return true;
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
  local NexgenClient clients[8];
  
  if(client.bSpectator) return;
  
  // Search for existing client
  ATBClient = findATBDisconnectedClient(client);
  
  // Reconnect?
  if(ATBClient != none) {
    // Restore client reference
    ATBClient.client = client;

    // Put back to old team?
    if(ATBClient.bTeamAssigned && ATBClient.disconnectedTime >= lastStrengthChangeTime) {
      ATBClient.beginPlayTime = control.timeSeconds;
      assignTeam(ATBClient, ATBClient.team);
      lastStrengthChangeTime = control.timeSeconds;
      
      if(control.timeSeconds - ATBClient.disconnectedTime > maxReconnectWaitTime) {
        // Announce again
        clients[0] = client;
        flashNewTeamAssignments(clients);
      }
    } else {
      ATBClient.bTeamAssigned = false;
      ATBClient.bMidGameJoin = true;
      ATBClient.initialized(); // Clients on the disconnected list are ensured to be initialized
    }
    
    // Move to active list
    removeATBDisconnectedClient(ATBClient);
  } else {
    // New client
    ATBClient = spawn(class'NexgenATBClient', self);
    ATBClient.playerID = client.playerID;
    ATBClient.client = client;
    ATBClient.xControl = self;
    ATBClient.xConf = xConf;
    
    // Add to list
    ATBClient.nextATBClient = ATBClientList;
    ATBClientList = ATBClient;
    
    // Locate data entry
    ATBClient.locateDataEntry();
  }
  numCurrPlayers++;

  // Player not yet initialized. Disallow play.
  if(control.gInf.gameState == control.gInf.GS_Playing && !ATBClient.bTeamAssigned) {
    Level.Game.DiscardInventory(client.player); 
    client.player.PlayerRestartState = 'PlayerWaiting';
    client.player.GotoState(client.player.PlayerRestartState);
  }
  
  // Mark mid-game joins
  if(control.gInf.gameState == control.gInf.GS_Playing ||
    (control.gInf.gameState == control.gInf.GS_Waiting && initialTeamSortTime != 0.0) ||
     control.gInf.gameState == control.gInf.GS_Starting) {
    ATBClient.bMidGameJoin = true;
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
    if(ATBClient.bInitialized) {
      // Move to disconnected list
      removeATBClient(ATBClient);
      
      if(ATBClient.bTeamAssigned) {
        // Save info for later
        teamStrength[client.team] -= ATBClient.strength;
        ATBClient.team = client.team;
        if(ATBClient.beginPlayTime > 0.0) {
          ATBClient.playTime += control.timeSeconds-ATBClient.beginPlayTime;
          ATBClient.score     = client.player.playerReplicationInfo.score;
        }
        ATBClient.disconnectedTime = control.timeSeconds;
        ATBClient.beginPlayTime = 0.0;
        
        // Update global vars
        lastDisconnectTime     = control.timeSeconds;
        lastStrengthChangeTime = control.timeSeconds;
      }
    } else {
      removeATBClient(ATBClient, true);
      ATBClient.destroy();
    }
    numCurrPlayers--;
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
      
      // Save begin time
      ATBClient.beginPlayTime = control.timeSeconds;
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
  
  if(control.gInf.gameState == control.gInf.GS_Playing && ATBClient != none && ATBClient.bMidGameJoin && !ATBClient.bTeamAssigned) {  
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
  local NexgenClient clients[8];
  
  ATBClient = getATBClient(client);
  
  if(ATBClient != none && ATBClient.bTeamAssigned) {
    if(ATBClient.bTeamSwitched) {
      ATBClient.bTeamSwitched = false;
    } else  {
      // Manual team change, adjust team strength
      teamStrength[client.team]             += ATBClient.strength;
      teamStrength[int(!bool(client.team))] -= ATBClient.strength;
      lastStrengthChangeTime = control.timeSeconds;
      
      clients[0] = client;
      flashNewTeamAssignments(clients);
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when the game executes its next 'game' tick.
 *
 **************************************************************************************************/
function tick(float deltaTime) {
  local int numPlayersInitialized;
  local bool bStillIniting;
  local float playerJoinTime;
  local NexgenClient client;
  local NexgenATBClient ATBClient;
  
  // Waiting state: Handle gamestart and trigger initial sorting
  if(control.gInf.gameState == control.gInf.GS_Waiting) {
  
    // Supress manual game start messages
    if(control.gInf.countDown == 1)  {
      waitFinishTime = control.timeSeconds;
      control.gInf.countDown = -1;
    }
    
    // Not yet sorted
    if(initialTeamSortTime == 0.0) {
      // Override team message
      for(client = control.clientList; client != none; client = client.nextClient) {
        if(!client.bSpectator) {
          flashMessageToPlayer(client, "Teams not yet assigned.", colorOrange);
        }
        if(client.bInitialized) flashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);
        else                    flashMessageToPlayer(client, "", colorWhite, 1);        
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
        if(!bStillIniting || (control.timeSeconds - waitFinishTime) >= maxInitWaitTime) {
          // Sort the teams.
          initialTeamSorting(numPlayersInitialized);
          initialTeamSortTime = control.timeSeconds;
          
          // Mark latecomers.
          if(numCurrPlayers-numPlayersInitialized > 0) {
            for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
              if(!ATBClient.bInitialized) ATBClient.bMidGameJoin = true;
            }
          }
        }
      } 
    } else {
      // Teams sorted. Flash progress messages.
      for(client = control.clientList; client != none; client = client.nextClient) {
        ATBClient = getATBClient(client);
        if(ATBClient != none) {
          if(!ATBClient.bMidGameJoin) {
            flashMessageToPlayer(client ,"You are on "$TeamGamePlus(Level.Game).Teams[client.player.playerReplicationInfo.team].TeamName$".", teamColor[client.player.playerReplicationInfo.team]);
            if(client.bInitialized) flashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
            else                    flashMessageToPlayer(client, "", colorWhite, 1); 
          } else {
            // Latecomer. Only show correct messages; mid-game-join sorting not in this state.
            flashMessageToPlayer(client, "You are not yet assigned to a team.", colorOrange);
            if(!ATBClient.bInitialized) flashMessageToPlayer(ATBClient.client, "Waiting for client initialization ...", colorWhite, 1);
            else                        flashMessageToPlayer(ATBClient.client, "Waiting for team assignment ...", colorWhite, 1);
          }
        } else {
          // Spectators
          if(client.bInitialized) flashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
          else                    flashMessageToPlayer(client, "", colorWhite, 1); 
        }        
      }
      if( (control.timeSeconds - initialTeamSortTime) >= gameStartDelay) {
        // Continue game start
        control.startGame(true);
      }
    }
  } 
  
  // Starting state: clear progress messages for sorted players and handle latecomers
  if(control.gInf.gameState == control.gInf.GS_Starting) { 
    for(client = control.clientList; client != none; client = client.nextClient) {
      ATBClient = getATBClient(client);
      if(ATBClient != none) {
        if(!ATBClient.bMidGameJoin) {
          client.player.ClearProgressMessages();
        } else {
          // Latecomer
          if(!ATBClient.bTeamAssigned) {
            flashMessageToPlayer(client, "You are not yet assigned to a team.", colorOrange);
            if(!ATBClient.bInitialized) flashMessageToPlayer(client, "Waiting for client initialization ...", colorWhite, 1);
            else                        flashMessageToPlayer(client, "Waiting for team assignment ...", colorWhite, 1);
          } else {
            if(midGameJoinTeamSortingTime != 0.0 && (control.timeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
              client.player.ClearProgressMessages();
            } else {
              flashMessageToPlayer(client, "You are on "$TeamGamePlus(Level.Game).Teams[client.player.playerReplicationInfo.team].TeamName$".", teamColor[client.player.playerReplicationInfo.team]);
              flashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
            }
          }
        }
      } else {
        // Spectators
        if(client.timeSeconds > specProgressMsgDuration) client.player.ClearProgressMessages();
      }
    }
    if(midGameJoinTeamSortingTime != 0.0 && (control.timeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
      midGameJoinTeamSortingTime = 0.0;
    }
  }
  
  // Playing state: mid-game joined players
  if(control.gInf.gameState == control.gInf.GS_Playing) { 
    for(client = control.clientList; client != none; client = client.nextClient) {
      ATBClient = getATBClient(client);
      if(ATBClient != none) {
        if(client.player.PlayerRestartState == 'PlayerWaiting') {
          if(!ATBClient.bTeamAssigned) {
            flashMessageToPlayer(client, "You are not yet assigned to a team.", colorOrange);
            if(!ATBClient.bInitialized) flashMessageToPlayer(client, "Waiting for client initialization ...", colorWhite, 1);
            else                        flashMessageToPlayer(client, "Waiting for team assignment ...", colorWhite, 1);
          } else {
            if(midGameJoinTeamSortingTime != 0.0 && (control.timeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
              client.player.ClearProgressMessages();
              
              // Play announcer
              if(playSound != none) client.player.clientPlaySound(playSound, , true);
              
              // Restart player
              client.player.PlayerRestartState = client.player.Default.PlayerRestartState;
              client.player.GotoState(client.player.PlayerRestartState);
              if(!Level.Game.RestartPlayer(client.player)) {
                client.player.GotoState('Dying'); //failed to restart player, so let him try to respawn again
              }
              ATBClient.beginPlayTime = control.timeSeconds;
            }
          }
        }
      } else {
        // Spectators
        if(client.timeSeconds < specProgressMsgDuration) { 
          if(client.bInitialized) flashMessageToPlayer(client, "Say !o to open the Nexgen control panel.", colorWhite, 1, 1.0);     
          else                    flashMessageToPlayer(client, "", colorWhite, 1.0); 
        } else if(client.timeSeconds < specProgressMsgDuration+0.1) client.player.ClearProgressMessages();
      }
    }
    if(midGameJoinTeamSortingTime != 0.0 && (control.timeSeconds - midGameJoinTeamSortingTime) > gameStartDelay) {
      midGameJoinTeamSortingTime = 0.0;
    }
    
    // Check for team score changes
    if(xConf.teamScoreBonus != 0) {
      if(teamScore[0] != TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[0].Score ||
         teamScore[1] != TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[1].Score) {
        teamScore[0] = TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[0].Score;
        teamScore[1] = TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[1].Score;
        lastStrengthChangeTime = control.timeSeconds;
      }
    }
  }
  
  // Game-ended state: Trigger strengths update.
  if(control.gInf.gameState == control.gInf.GS_Ended) {
    if(!bStrengthsUpdated && (control.timeSeconds - control.gameEndTime) > endUpdateDelay) {
      updateStrengths();
      bStrengthsUpdated = true;
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
  if(control.gInf.gameState != control.gInf.GS_Ended && midGameJoinTeamSortingTime == 0.0 && longestMidGameJoinWaitTime != 0.0 && (control.timeSeconds - longestMidGameJoinWaitTime) > minMidGameJoinWaitTime) {
    // Check for other waiting clients
    for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
      if(ATBClient.bMidGameJoin && !ATBClient.bTeamAssigned) {
        if(!ATBClient.bInitialized) bBetterWait = true;
        else                        midGameJoinToSort++;
      }
    }
   
    if(!bBetterWait || (control.timeSeconds - longestMidGameJoinWaitTime) > maxMidGameJoinWaitTime) {
      if(midGameJoinToSort > 0) midGameJoinTeamSorting(midGameJoinToSort);
      else longestMidGameJoinWaitTime = 0.0;
    }
  }
  
  // Check for unbalance
  if((control.gInf.gameState == control.gInf.GS_Starting || control.gInf.gameState == control.gInf.GS_Playing)) {
    getTeamSizes(teamSizes, true);
    
    if(abs(teamSizes[0] - teamSizes[1]) > 1) {
      // Check for waiting clients
      for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
        if(!ATBClient.bTeamAssigned) break;
      }
      // No waiting clients
      if(ATBClient == none) {
        // Wait for reconnect?
        if( (control.timeSeconds - lastDisconnectTime) > maxReconnectWaitTime) {
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
      if(ATBClient.bSortedByStrength || !ATBClient.bInitialized || ATBClient.bTeamAssigned) continue;
      
      if(ATBClient.strength > max) {
        maxATBClient = ATBClient;
        max = ATBClient.strength;
      }
    }

    if(max == -1) {
      control.nscLog("[NATB] max == -1!");
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
      if(ATBClient.bSortedByStrength || !ATBClient.bInitialized || ATBClient.client.player.playerReplicationInfo.team != team) continue;
      
      if(ATBClient.strength > max) {
        maxATBClient = ATBClient;
        max = ATBClient.strength;
      }
    }

    if(max == -1) {
      control.nscLog("[NATB] max == -1 at team sorting!");
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
function NexgenATBClient getBestSwitch(byte team, float difference) {
  local NexgenATBClient ATBClient, minATBClient; 
  local float newDifference;
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
    if(getTeamStrength(0) > getTeamStrength(1)) weakerTeam = 1;  
    
    assignTeam(sortedATBClients[numPlayersInitialized-1], weakerTeam);
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
  control.broadcastMsg("<C04>Red team strength is "$int(teamStrength[0])$", Blue team strength is "$int(teamStrength[1])$".");
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Sorts the mid-game joined players into the teams. Considers the currently weakest
 *                team (including flag captures).
 *
 **************************************************************************************************/
function midGameJoinTeamSorting(int midGameJoinToSort) {
  local NexgenATBClient sortedATBClients[32];
  local NexgenClient    clients[8];
  local int i, weakerTeam, strongerTeam;
  local int start, end;
  local int teamSizes[2];
  local string playerPluralString;
  
  // Sort waiting clients by strength
  sortNewClientsByStrength(midGameJoinToSort, sortedATBClients);
  
  // Work out weakest team
  if(getTeamStrength(0) > getTeamStrength(1)) weakerTeam = 1;  
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
    end = midGameJoinToSort-1;
  } else if(teamSizes[weakerTeam] < teamSizes[strongerTeam]) {
    // The weakest team has the number disadvantage
    // Put the strongest player into the weaker team
    assignTeam(sortedATBClients[0], weakerTeam);
    start = 1;
  } 
  
  // Update weaker/stronger team if required
  if(start != 0 || end != midGameJoinToSort) {
    weakerTeam   = 0;
    if(getTeamStrength(0) > getTeamStrength(1)) weakerTeam = 1;  
    strongerTeam = int(!bool(weakerTeam));
  }

  // Build teams
  // Scheme: weak-strong-weak-strong-...
  for(i=start; i<end; i++) {
    // Move player and update team strength
    assignTeam(sortedATBClients[i], weakerTeam);
    weakerTeam = strongerTeam;
  }  
  
  // Announce for new players 
  for(i=0; i<midGameJoinToSort; i++) {
    flashMessageToPlayer(sortedATBClients[i].client, "You are on "$TeamGamePlus(Level.Game).Teams[sortedATBClients[i].client.player.playerReplicationInfo.team].TeamName$".", teamColor[sortedATBClients[i].client.player.playerReplicationInfo.team]);
    flashMessageToPlayer(sortedATBClients[i].client, "Say !o to open the Nexgen control panel.", colorWhite, 1);     
    if(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team] != none) sortedATBClients[i].client.player.clientPlaySound(teamSound[sortedATBClients[i].client.player.playerReplicationInfo.team], , true);
  }
  
  // Announce for others
  for(i=0; i<midGameJoinToSort && i<ArrayCount(clients); i++) clients[i] = sortedATBClients[i].client;
  flashNewTeamAssignments(clients); 
  
  // Reset
  longestMidGameJoinWaitTime = 0;
  lastStrengthChangeTime = control.timeSeconds;
  
  // Save time
  midGameJoinTeamSortingTime = control.timeSeconds;
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
  local int largerTeam, smallerTeam, sizeDifference; 
  local float strengthDifference;
  local int nextPlayerToMove;
  local int movedPlayerAmount;
  local int i;
  local int movedClients;
  local NexgenClient clients[8];
  
  // Figure out what to do
  getTeamSizes(teamSizes);
  if(teamSizes[1] > teamSizes[0]) largerTeam = 1;
  smallerTeam = int(!bool(largerTeam));
  
  sizeDifference = abs(teamSizes[0] - teamSizes[1]);
  if(sizeDifference <= 1) return;

  // Oops, larger team is weaker than the smaller team! Move weakest players.
  if(getTeamStrength(largerTeam) < getTeamStrength(smallerTeam)) {
    // Get sorted strenghts
    sortTeamClientsByStrength(teamSizes[largerTeam], largerTeam, sortedATBClientsLargerTeam);
    nextPlayerToMove = teamSizes[largerTeam] - 1;
    do {
      if(sortedATBClientsLargerTeam[nextPlayerToMove].client.player.playerReplicationInfo.hasFlag != none) nextPlayerToMove--;
      
      assignTeam(sortedATBClientsLargerTeam[nextPlayerToMove], smallerTeam);
      if(movedClients < arrayCount(clients)) clients[movedClients++] = sortedATBClientsLargerTeam[nextPlayerToMove].client;
      teamStrength[largerTeam]  -= sortedATBClientsLargerTeam[nextPlayerToMove].strength;
      
      movedPlayerAmount++;
      nextPlayerToMove--;
      sizeDifference -= 2;
    } until(sizeDifference <= 1);
  
  } else {    
    do {
      strengthDifference = getTeamStrength(largerTeam) - getTeamStrength(smallerTeam);
      preferedATBClient  = getBestSwitch(largerTeam, strengthDifference);
      
      // Manual check when player amount is odd
      if(sizeDifference == 1 && strengthDifference < abs(strengthDifference-preferedATBClient.strength*2)+oddPlayerChangeThreshold) {
        break;
      }
     
      assignTeam(preferedATBClient, smallerTeam);
      if(movedClients < arrayCount(clients)) clients[movedClients++] = preferedATBClient.client;
      teamStrength[largerTeam]  -= preferedATBClient.strength;
      
      // Inform player 
      for(i=0; i<7; i++)   preferedATBClient.client.player.SetProgressMessage("", i);
      flashMessageToPlayer(preferedATBClient.client, "Assigned to "$TeamGamePlus(Level.Game).Teams[smallerTeam].TeamName$" due to unbalanced team sizes!", teamColor[smallerTeam]);

      movedPlayerAmount++;
      sizeDifference -= 2;
    } until(sizeDifference < 1);
    
  }
  
  // Announce strengths
  control.broadcastMsg("<C04>Nexgen Auto Team Balancer moved "$movedPlayerAmount$" "$getPlayerString(movedPlayerAmount)$" due to unbalanced team sizes!");
  control.broadcastMsg("<C04>Red team strength is "$  Left(getTeamStrength(0), InStr(getTeamStrength(0), ".")+3)$
                       ", Blue team strength is "$  Left(getTeamStrength(1), InStr(getTeamStrength(1), ".")+3)$".");
  
  // Announce to others
  flashNewTeamAssignments(clients);
  
  // Reset
  lastStrengthChangeTime = control.timeSeconds;
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
 *  $DESCRIPTION  Removes the specified client from the client list.
 *  $PARAM        client  The client that is to be removed.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function removeATBClient(NexgenATBClient ATBClient, optional bool bDontMove) {
  local NexgenATBClient currClient;
  local bool bDone;
  
  // Remove the client from the linked online client list.
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
  
  // Add to disconnected list
  if(!bDontMove) {
    ATBClient.nextATBClient = ATBDisconnectedtList;
    ATBDisconnectedtList = ATBClient;
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Removes the specified client from the client list.
 *  $PARAM        client  The client that is to be removed.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function NexgenATBClient findATBDisconnectedClient(NexgenClient client) {
	local NexgenATBClient ATBClient;
	local bool bFound;
	
	// Search for NexgenClient owning this actor.
	ATBClient = ATBDisconnectedtList;
	while (!bFound && ATBClient != none) {
		if (ATBClient.playerID == client.playerID) {
			bFound = true;
		} else {
			ATBClient = ATBClient.nextATBClient;
		}
	}
	
	// Return result.
	if (bFound) {
		return ATBClient;
	} else {
		return none;
	}
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Removes the specified client from the client list.
 *  $PARAM        client  The client that is to be removed.
 *  $REQUIRE      client != none
 *
 **************************************************************************************************/
function removeATBDisconnectedClient(NexgenATBClient ATBClient) {
  local NexgenATBClient currClient;
  local bool bDone;
  
  // Remove the client from the linked online client list.
  if (ATBDisconnectedtList == ATBClient) {
    // First element in the list.
    ATBDisconnectedtList = ATBClient.nextATBClient;
  } else {
    // Somewhere else in the list.
    currClient = ATBDisconnectedtList;
    while (!bDone && currClient != none) {
      if (currClient.nextATBClient == ATBClient) {
        bDone = true;
        currClient.nextATBClient = ATBClient.nextATBClient;
      } else {
        currClient = currClient.nextATBClient;
      }
    }
  }
  
  // Add to active list
  ATBClient.nextATBClient = ATBClientList;
  ATBClientList = ATBClient;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called by an ATBClient instance when it is ready to be sorted.
 *
 **************************************************************************************************/
function ATBClientInit(NexgenATBClient ATBClient) {

  if( (control.gInf.gameState == control.gInf.GS_Waiting && initialTeamSortTime != 0.0) ||
       control.gInf.gameState == control.gInf.GS_Starting ||
       control.gInf.gameState == control.gInf.GS_Playing) {

    // The sorting is triggered by the timer; only save longest waiting time here
    if(longestMidGameJoinWaitTime == 0) {
      longestMidGameJoinWaitTime = control.timeSeconds;
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Flashes messages to all players (as long as their initial messages are cleared).
 *                Used for showing colored team assignment messages.
 *
 **************************************************************************************************/
function flashNewTeamAssignments(NexgenClient clients[8]) {
  local NexgenClient client;
  local NexgenATBClient ATBClient;
  local string newProgressMsgs[8];
  local color  newProgressMsgsColors[8];
  local int i;
  
  // Skip initial sorting assignments.
  if(control.gInf.gameState == control.gInf.GS_Waiting) return;
  
  // Construct strings
  for(i=0; i<arrayCount(newProgressMsgs) && clients[i] != none; i++) {
    newProgressMsgs[i]       = clients[i].playerName$" is now on "$TeamGamePlus(Level.Game).Teams[clients[i].player.playerReplicationInfo.team].TeamName$".";
    newProgressMsgsColors[i] = teamColor[clients[i].player.playerReplicationInfo.team];
  }

  for(client = control.clientList; client != none; client = client.nextClient) {
    ATBClient = getATBClient(client);
    if(ATBClient != none) {
      if(!ATBClient.bMidGameJoin || ATBClient.beginPlayTime > 0.0) {
        for(i=0; i<ArrayCount(newProgressMsgs); i++) {
          client.player.SetProgressTime(teamAssignMsgsDuration);
          client.player.SetProgressColor(newProgressMsgsColors[i], i);
          client.player.SetProgressMessage(newProgressMsgs[i], i);
        }
      }
    } else {
      // Spectators.
      if(client.timeSeconds >= specProgressMsgDuration+0.1) {
        for(i=0; i<ArrayCount(newProgressMsgs); i++) {
          client.player.SetProgressTime(teamAssignMsgsDuration);
          client.player.SetProgressColor(newProgressMsgsColors[i], i);
          client.player.SetProgressMessage(newProgressMsgs[i], i);
        } 
      }
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Overrides the progress messages. Taken from ATB 1.5.
 *
 **************************************************************************************************/
function flashMessageToPlayer(NexgenClient client, string msg, Color msgColor, optional int offset, optional float duration) {
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
   
  if(duration == 0.0) duration = 5.0;

  client.player.SetProgressTime(5);
  client.player.SetProgressColor(msgColor,targetLine+offset);
  client.player.SetProgressMessage(msg,targetLine+offset);  
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Moves a client to a different team.
 *
 **************************************************************************************************/
function assignTeam(NexgenATBClient ATBClient, byte newTeam) {
  ATBClient.bTeamAssigned = true;
  teamStrength[newTeam] += ATBClient.strength;
  if(newTeam != ATBClient.client.player.playerReplicationInfo.team) {
    ATBClient.client.setTeam(newTeam);
    ATBClient.bTeamSwitched = true;
  }
  
  // Announce
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Team strengths including flag bonus
 *
 **************************************************************************************************/
function float getTeamStrength(byte teamNum) {
  return teamStrength[teamNum] + TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[teamNum].Score * xConf.teamScoreBonus;
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
  local NexgenClient client;
  
  client = control.getClient(sender);
  
  if(client == none) return false;

  cmd = class'NexgenUtil'.static.trim(msg);
  bIsCommand = true;
  switch (cmd) {
    case "!teams": case "!team": case "!t":
      if(initialTeamSortTime == 0) client.showMsg("<C00>Teams not yet assigned.");
      else { 
        client.showMsg("<C04>Red team strength is "$int(getTeamStrength(0))$" (+"$int(getTeamStrength(0)-teamStrength[0])$"), Blue team strength is "$int(getTeamStrength(1))$" (+"$int(getTeamStrength(1)-teamStrength[1])$"), difference -"$int(abs(getTeamStrength(0)-getTeamStrength(1)))$".");
        client.showMsg("<C04>Say '!str' for more details.");
      }
    break;
    
    // Display detailed strength info via Nexgen's PM function (proper formatting and accessible as server side only plugin)
    case "!strengths": case "!str": 
        NexgenClientCore(client.getController(class'NexgenClientCore'.default.ctrlID)).receivePM(client.playerID, client.player.playerReplicationInfo, getStrengthsString(0), false, true);
        NexgenClientCore(client.getController(class'NexgenClientCore'.default.ctrlID)).receivePM(client.playerID, client.player.playerReplicationInfo, getStrengthsString(1), false, true);
        client.showPanel(class'NexgenRCPPrivateMsg'.default.panelIdentifier);
    break;

    // Not a command.
    default: bIsCommand = false;
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
  local float hrsPlayed;
  
  // Sort by strength
  getTeamSizes(teamSizes, true);
  sortTeamClientsByStrength(teamSizes[team], team, sortedATBClients);
  
  seperatorToken = newLineToken;
  res = newLineToken$newLineToken;

  // Construct string
  res = res$"Nexgen Auto Team Balancer "$TeamGamePlus(Level.Game).Teams[team].TeamName$" Team Strengths:"$newLineToken$newLineToken;
  for(i=0; i<teamSizes[team]; i++) {
    hrsPlayed = sortedATBClients[i].secondsPlayed/3600.0;
    res = res$sortedATBClients[i].client.playerName$": "$Left(sortedATBClients[i].strength, InStr(sortedATBClients[i].strength, ".")+3)$" ("$Left(hrsPlayed, InStr(hrsPlayed, ".")+3)$"hrs)"$seperatorToken;
  }
  res = res$seperatorToken;
  
  return res;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Updates the database.
 *
 **************************************************************************************************/
function updateStrengths() {
	local NexgenATBClient ATBClient;
  local int winningTeam;
  local float accScore, accStrength;
  local float avgScore, avgStrength;
  local int playerAmount;
  
  // Announce
  control.broadcastMsg("<C04>Nexgen Auto Team Balancer is updating player strengths...");
  
  // Determine winning team
  if     (TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[1].Score ==
          TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[0].Score) winningTeam = -1;
  else if(TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[1].Score >
          TournamentGameReplicationInfo(Level.Game.GameReplicationInfo).Teams[0].Score) winningTeam = 1;

  // Accumulate score and strength for online players
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    if(ATBClient.beginPlayTime > 0.0) ATBClient.playTime += (control.gameEndTime-ATBClient.beginPlayTime);
    else control.nscLog("[NATB] ATBClient.beginPlayTime is 0.0 for "$ATBClient.playerID);
    ATBClient.score = ATBClient.client.player.PlayerReplicationInfo.Score;
    accumScoreStrength(ATBClient, winningTeam, accScore, accStrength, playerAmount);
  }

  // Accumulate score and strength for disconnected clients
  for(ATBClient=ATBDisconnectedtList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    accumScoreStrength(ATBClient, winningTeam, accScore, accStrength, playerAmount);
  }
  
  // Nothing to do?
  if(playerAmount < minPlayerAmount) {
    control.broadcastMsg("<C00>Client amount or play time not representive, not updating.");
    return;
  }
  
  // Compute average
  avgScore    = accScore/playerAmount;
  avgStrength = accStrength/playerAmount;
  
  // Set min for avg score
  if(avgScore < 2.0) avgScore = 2.0;
  
  // We can now normalise each player's score ...
  for(ATBClient=ATBClientList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    updatePlayerStrength(ATBClient, avgScore, avgStrength);
  }
  
  // ... and do the same for disconnected clients
  for(ATBClient=ATBDisconnectedtList; ATBClient != none; ATBClient=ATBClient.nextATBClient) {
    updatePlayerStrength(ATBClient, avgScore, avgStrength);
  }  

  // Finally, save config. We are done for this game.
  xConf.saveConfig();
}


/***************************************************************************************************
 *
 *  $DESCRIPTION  Accumulates the score and strength of all participating players of this match.
 *
 **************************************************************************************************/
function accumScoreStrength(NexgenATBClient ATBClient, int winningTeam, out float accScore, out float accStrength, out int playerAmount) {
  if(ATBClient.playTime > minPlayTimeForUpdate) {
    ATBClient.playerScore = ATBClient.score * (control.gameEndTime-control.gameStartTime)/ATBClient.playTime;
    
    // Winning team bonus for online players
    if(ATBClient.client != none && xConf.winningTeamBonus > 0 && ATBClient.playTime > minPlayTimeForWinBonus && ATBClient.client.player.playerReplicationInfo.team == winningTeam) {
      ATBClient.playerScore += xConf.winningTeamBonus;
    }
    
    // Disallow a score of 0
    if(ATBClient.playerScore == 0.0) ATBClient.playerScore = -0.1;

    accScore    += ATBClient.playerScore;
    accStrength += ATBClient.strength;
    playerAmount++;
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Computes normalised score and updates the strength of each participating player.
 *
 **************************************************************************************************/
function updatePlayerStrength(NexgenATBClient ATBClient, float avgScore, float avgStrength) {
  local float normalisedScore;
  local float oldTotalTimePlayed, newTotalTimePlayed;
  local float oldStrength, newStrength, strengthDifference;

  if(ATBClient.playerScore != 0.0) {
    // Other magic formular taken from ATB
    normalisedScore = ATBClient.playerScore * (avgStrength * relNormalisationProp + normalisedStrength * (1.0 - relNormalisationProp)) / avgScore;
    control.nscLog("[NATB] normalizedScore of "$ATBClient.playerID$"="$normalisedScore);
    control.nscLog("[NATB] ATBClient.playTime="$ATBClient.playTime);

    // Update time and strength
    oldTotalTimePlayed = ATBClient.secondsPlayed;
    if(oldTotalTimePlayed > hoursBeforeRecyStrength*3600) {
      oldTotalTimePlayed = hoursBeforeRecyStrength*3600;
    }
    newTotalTimePlayed = oldTotalTimePlayed + ATBClient.playTime;
    oldStrength = ATBClient.strength;
    newStrength = (oldStrength*oldTotalTimePlayed + normalisedScore*ATBClient.playTime) / newTotalTimePlayed;
    xConf.updateData(ATBClient.configIndex, newStrength, ATBClient.secondsPlayed + ATBClient.playTime);
    
    // Update local data in case somebody wants to see them
    ATBClient.strength       = newStrength;
    ATBClient.secondsPlayed += ATBClient.playTime;
    
    // Announce to player
    if(ATBClient.client != none) {
      strengthDifference = newStrength-oldStrength;
      if     (strengthDifference > 0) ATBClient.client.showMsg("<C02>Strength increased by "$Left(strengthDifference, InStr(strengthDifference, ".")+3)$  "! New strength is "$Left(newStrength, InStr(newStrength, ".")+3)$".");
      else if(strengthDifference < 0) ATBClient.client.showMsg("<C00>Strength decreased by "$Left(-strengthDifference, InStr(-strengthDifference, ".")+3)$"! New strength is "$Left(newStrength, InStr(newStrength, ".")+3)$".");
      else                            ATBClient.client.showMsg("<C02>Strength retained at "$newStrength$"!");
    }
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called to check if the given localized message should be send to the specified
 *                receiver.
 *  $PARAM        sender          The actor that has send the message.
 *  $PARAM        receiver        Pawn receiving the message.
 *  $PARAM        message         The class of the localized message that is to be send.
 *  $PARAM        switch          Optional message switch argument.
 *  $PARAM        relatedPRI_1    PlayerReplicationInfo of a player that is related to the message.
 *  $PARAM        relatedPRI_2    PlayerReplicationInfo of a player that is related to the message.
 *  $PARAM        optionalObject  Optional object used to construct the message string.
 *  $REQUIRE      message != none
 *  $RETURN       True if the message should be send, false if it should be suppressed.
 *
 **************************************************************************************************/
function bool mutatorBroadcastLocalizedMessage(Actor sender, Pawn receiver,
                                               out class<LocalMessage> message,
                                               out optional int switch,
                                               out optional PlayerReplicationInfo relatedPRI_1,
                                               out optional PlayerReplicationInfo relatedPRI_2,
                                               out optional Object optionalObject) {
                                               
  // Hide default team assignment messages                                             
	if(message == DeathMatchPlus(Level.Game).DMMessageClass && switch == 3) return false;
  
  return true;
}


function string getPlayerString(int amount) { if(amount > 1) return "players"; else return "player";}

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
     pluginVersion="0.31"
     versionNum=031
}
