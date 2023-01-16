Original repository:

https://groups.google.com/g/kyros-lobby?pli=1

---
INSTALL

Download https://drive.google.com/open?id=0B5105cZiAiSkNWFUQUp4a3AtOW8

(Note: File was lobby.lua, which was uploaded under legacy_source)

Create the folders (if they don't already exist): "C:\ProgramData\FAForever\gamedata\2lua.nx2\lua\ui\lobby\"

Put the "lobby.lua" you just downloaded in that folder

If you have installed an older version of the lobby: delete the file "C:\ProgramData\FAForever\gamedata\lua.nx2"

Done

UNINSTALL

Open "C:\ProgramData\FAForever\gamedata\2lua.nx2\lua\ui\lobby"

Delete "lobby.lua"

WHAT IT DOES

When Auto-Teams is enabled, creates 2 columns, one for each team
Sorts the slots so each player faces to the player with the same slot in the other team
Shows the total rating of each team (sum of each player)
Because the slot numbers are sometimes randomly assigned on the map, you can sort the players based on their position (vertical, horizontal)
Adds commands to ban players, filter players who join (based on CPU score, rank and number of games played) and add comments related to players (blacklist or comments on their performance)
Adds a new auto-resized chat box with colored text

CHAT COMMANDS

/help : Lists all commands

/pm [playername] : Sends a private message (/pm KyrO Hello)

/stats : Displays the total rating and number of games of both teams to everyone

/myslot [slotnbr] : Saves your prefered slot on this map. You will be moved to this slot (if available) as soon as you join a lobby with this map (/myslot 12)

/ban [playername] [reason?] : Bans a player. This player will be auto-kicked if he tries to join the lobby (/ban KyrO I don't like you)

/ban : Lists all banned players

/unban [playername] : Unbans a player

/unban : Unbans all players

/cpulimit [max] : Auto-kicks all players who have a higher cpu score than the provided value (/cpulimit 250)

/cpulimit : Removes the cpu limit

/ranklimit [min] [max] : Auto-kicks all players who do not have a rating between the provided values (/ranklimit 800 1600)

/ranklimit : Removes the rank limit

/gameslimit [min] [max] : Auto-kicks all players who do not have a number of games between the provided values (/gameslimit 100 10000)

/gameslimit : Removes the number of games limit

/info [playername] [text] : Saves a comment about a player (/info KyrO Slow cpu)

/info [playername] : Displays the comment about a player

/info : Displays the comments of all connected players

/info all : Displays all saved comments

/reminfo [playername] : Removes the comment about a player
