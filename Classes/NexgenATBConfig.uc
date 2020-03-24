class NexgenATBConfig extends NexgenPluginConfig;

var config string startSound;
var config string playSound;
var config string teamSound[2];

var config int defaultStrength;
var config int flagStrength;
var config string playerData[2048]; // ID#Strength#Date


defaultproperties {
 startSound="UrSGrappleSounds.Start",
 playSound="UrSGrappleSounds.Play",
 teamSound(0)="UrSGrappleSounds.OnRed",
 teamSound(1)="UrSGrappleSounds.OnBlue",
 defaultStrength=40
 flagStrength=5
}