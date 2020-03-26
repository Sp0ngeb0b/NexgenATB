class NexgenATBClient extends Info;

// References
var NexgenClient client;
var NexgenATB xControl;
var NexgenATBConfig xConf;
var NexgenATBClient nextATBClient;

// Data
var int configIndex;
var int strength;

// Miscellaneous 
var bool  bTeamAssigned;       
var bool  bMidGameJoin;
var bool  bTeamSwitched;
var float playTime;
 
// Control variables
var bool bSortedByStrength;
var int strengthRating;
var bool bInitialized;
var bool locatingEntry;
var int lastChecked;

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
    for(i=lastChecked; i<maxEntriesPerTick && i < ArrayCount(xConf.playerData); i++) {
      if(xConf.playerData[i] == "") {
        // New Entry
        configIndex = i;
        strength = xConf.defaultStrength;
        initialized();
        
        // Write initial data to config entry
        xConf.playerData[i] = client.playerID;
        
        return;
      } else {
        class'NexgenUtil'.static.split(xConf.playerData[i], ID, remaining);
        if(ID == client.playerID) {
          configIndex = i;
          class'NexgenUtil'.static.split(remaining, strengthStr, remaining);
          strength = int(strengthStr);
          initialized();
          return;
        }
      }
    }
  }
  
  if(i == ArrayCount(xConf.playerData)) {
    configIndex = ArrayCount(xConf.playerData)-1;
    strength = xConf.defaultStrength;
    initialized();
  }
}

function locateDataEntry() {
  locatingEntry = true;
}

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