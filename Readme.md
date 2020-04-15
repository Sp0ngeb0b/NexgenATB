**NexgenATB version 0.31 (Beta)**
-

![file](https://user-images.githubusercontent.com/12958319/79121922-bc8ac980-7d96-11ea-86d2-5fbe36adf820.jpg)


**Nexgen Auto Team Balancer** (*NexgenATB*) is a completely rewritten version of nogginBasher's [AutoTeamBalance](https://unrealadmin.org/forums/showthread.php?t=23777) for the Nexgen Server Controller.

---
**Beta Testing**
-

The mod is is still in beta testing; you can access the latest version from [here](https://github.com/Sp0ngeb0b/NexgenATB/releases). Please report any bugs, feedback or requests to me via GitHub or into the [official thread at ut99.org](https://ut99.org/viewtopic.php?f=7&t=13806).

**Known limitations:**

 - NexgenATB only supports teamgames with 2 teams
 - NexgenATB will not move players automatically when the team size is not uneven (3 vs 2 for example); in this case, players are encouraged to manually switch the teams (to either make it 2 vs 3 and balanced _or_ 4 vs 1 in order to trigger NexgenATB automatic rebalancing). This feature is open for discussion and some kind of player voting to rebalance even in case of even team sizes might be implemented. 

---
**Description**
-

NexgenATB will automatically manage the team assignment on your gameserver and aims to provide as even teams as possible for fair gameplay. This is done by ranking each player with a so-called *strength* value, which is put together by the player's score at the end of each game. The more often a player plays on your server, the more accurate will the strength rating for him become.

At the start of the game, NexgenATB will perform an initial team sorting. After that, new players joining will be put into the weaker team. In case of several players joining at the same time (e.g. spectators entering the match together), their strengths will be considered completely for the individual team assignment. In case of teams becoming uneven in size (3 vs 1 for example), NexgenATB will automatically rebalance the teams accordingly, considering the strengths and the current gametime of the players; i.e. players joining mid-game are more likely to get moved than players playing from the beginning on.

---

**Improvements regarding the original AutoTeamBalance mod**
-

- Players are **identified using their Nexgen ID** and no longer by nickname/IP adress. This prevents the system from accidently "forgetting" a players strength.
- **Graceful database access**. Locating a player inside the database is stretched over several game ticks which protects the gameserver's performance.
- Players joining mid-game are put into a **waiting state** before being assigned a team and being able to play. This way, several players joining can be considered together for fair team assignment.
- In case of uneven team sizes, NexgenATB waits a fair amount of time in case a player has lost connection / needs to **reconnect**.
- Players who **leave before the game ends** and the strengths are updated are also considered for the computation and their strength is updated as well.
- Only the **real play time** of player's are considered; i.e. when they go spectate for 5 minutes during a game, this time will not be considered in the final strength calculation. This also provides full compatibility with Nexgen's stats restoring functionality.
- The system fully utilizes **Nexgen's game states** and therefore the option `Let Nexgen handle the gamestart` can be enabled, including the corresponding countdown.

---

**Installation**
-

This is a **server-side only plugin**! Therefore, the package will always be named `NexgenATB.u` and there is no need for renaming anything. To install it, add the following line to your *UnrealTournament.ini* file:

```
ServerActors=NexgenATB.NexgenATB
```
This line must be placed after the `ServerActors=Nexgen112.NexgenActor` line.

**Do not add as a ServerPackage!**

---

**Configuration**
-

NexgenATB currently comes with way less configuration options than the original ATB mod; this is intentional to make it for admins easier to use the mod.

|**Variable**|**Type**|**Default Value**|**Description**|
|--|--|--|--|
|defaultStrength |int|30|The default strength new (unknown) players start with.  
|teamScoreBonus  |int|10|Additional strength bonus per team score point.
|winningTeamBonus|int|5 |Additional score rewarded to player strength calculation when finishing on winning team.

**Note**: For NexgenATB to be active, you to enable the `enableNexgenStartControl` option in Nexgen! Also, the plugin will automatically be disabled in case the Nexgen match mode or tournament mode is activated.

---

**Usage**
-

The plugin doesn't offer a lot of user interaction possibilities; however, the following commands are supported:

|**Command**| **Abbreviation** | **Description**|
|--|--|--|
|!teams    |!t  | Shows the current accumulated team strengths including teamscore bonus.
|!strengths|!str| Prints detailed strengths information for each player.


---

**Credits**
-

 - Defrost for developing [Nexgen](https://github.com/dscheerens/nexgen)
 - nogginBasher for developing [AutoTeamBalance](https://github.com/joeytwiddle/code/tree/master/code/unrealscript/AutoTeamBalance)
   - Note that NexgenATB partly uses code from ATB
   
---

**Contact**
-

**Author**: Patrick "Sp0ngeb0b" Peltzer  
**Website**: https://www.unrealriders.eu  
**Email**: spongebobut@yahoo.com
