class NexgenATBConfig extends NexgenPluginConfig;

var config string startSound;
var config string playSound;
var config string teamSound[2];

var config int defaultStrength;
var config int flagStrength;
var config int winningTeamBonus;
var config string playerData[2048]; // ID#Strength#SecondsPlayed

const separator = ",";

function loadData(int index, out int strength, out int secondsPlayed) {
  local string remaining, strengthStr, secondsPlayedStr;
  
  // Default values
  if(Len(playerData[index]) == 32) {
    strength      = defaultStrength;
    secondsPlayed = 0;
  } else {
    class'NexgenUtil'.static.split(playerData[index], strengthStr, remaining);
    class'NexgenUtil'.static.split(remaining, strengthStr, remaining);
    strength = int(strengthStr);
    class'NexgenUtil'.static.split(remaining, secondsPlayedStr, remaining);
    secondsPlayed = int(secondsPlayedStr);
  }
}

function updateData(int index, int strength, int secondsPlayed) {
  playerData[index] = Left(playerData[index], 32) $ separator $ strength $ separator $ secondsPlayed;
}

defaultproperties {
 startSound="UrSGrappleSounds.Start",
 playSound="UrSGrappleSounds.Play",
 teamSound(0)="UrSGrappleSounds.OnRed",
 teamSound(1)="UrSGrappleSounds.OnBlue",
 defaultStrength=40
 flagStrength=5
}