class NexgenATBClient extends Info;

// References
var NexgenClient client;
var NexgenATB xControl;
var NexgenATBConfig xConf;
var NexgenATBClient nextATBClient;

// Identifier
var string playerID;

// Persistent config data
var int configIndex;
var int strength;
var int secondsPlayed;

// Persistent game data
var byte team;
var int   score;
var float beginPlayTime;
var float playTime;
var float disconnectedTime;

// Miscellaneous 
var bool  bTeamAssigned;       
var bool  bMidGameJoin;
var bool  bTeamSwitched; 

// Used for updating the strength
var float playerScore;
 
// Control variables
var bool bSortedByStrength;
var int strengthRating;
var bool bInitialized;
var bool locatingEntry;
var int nextToCheck;

const maxEntriesPerTick = 64;

/***************************************************************************************************
 *
 *  $DESCRIPTION  Init data.
 *
 **************************************************************************************************/
function preBeginPlay() {
  configIndex = -1;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Serverside tick.
 *  $OVERRIDE
 *
 **************************************************************************************************/
event tick(float deltaTime) {
  local int i;
  local string ID, strengthStr, remaining;
  
  if(locatingEntry) {
    for(i=nextToCheck; i<nextToCheck+maxEntriesPerTick && i < ArrayCount(xConf.playerData); i++) {
      if(xConf.playerData[i] == "") {
        // New Entry, write initial data to config entry (mark as used)
        configIndex = i;
        xConf.playerData[i] = client.playerID;
        
        // Load default values
        xConf.loadData(configIndex, strength, secondsPlayed);
        
        initialized();
        return;
      } else {
        // Found entry, load in data
        if(Left(xConf.playerData[i], 32) == client.playerID) {
          configIndex = i;
          xConf.loadData(configIndex, strength, secondsPlayed);
          initialized();
          return;
        }
      }
    }
  }
  
  nextToCheck = i;
  
  // Database full, overwrite last entry
  if(i == ArrayCount(xConf.playerData)) {
    configIndex = ArrayCount(xConf.playerData)-1;
    xConf.playerData[i] = Left(xConf.playerData[i], 32);
    xConf.loadData(configIndex, strength, secondsPlayed);
    initialized();
  }
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Initiates the database lookup.
 *
 **************************************************************************************************/
function locateDataEntry() {
  locatingEntry = true;
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Called when a database entry was found or created.
 *
 **************************************************************************************************/
function initialized() {
  bInitialized = true;
  locatingEntry = false;
  disable('Tick');
  xControl.ATBClientInit(self);
}

/***************************************************************************************************
 *
 *  $DESCRIPTION  Default properties block.
 *
 **************************************************************************************************/
defaultproperties
{
     RemoteRole=ROLE_None
}