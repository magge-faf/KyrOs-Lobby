Lobby Notes and Installation Instructions

---

- Kyros lobby updated by macdeffy

---

9-11-22 update -	moved magnify glass down so it won't block slot

added languages to some areas

9-6-22 update - 	FIXED Survival maps not being able to load.

Also saves AutoTeams State for individual maps.

It should load preference for previously played maps.

5-8-22 update -	patchnotes from faf code added in and other GUI changes

4-2-22 UPDATE - 	added new autobalance and all current applicable lobby changes

---

1. ) Installation

Browse to folder: C:\ProgramData\FAForever\gamedata\

Copy kyros.nxt into this folder

So it look like:

C:\ProgramData\FAForever\gamedata\kyros.nxt


1. ) Uninstall

Just delete kyros.nxt


Overview

---

Using Kyro's Lobby, depending on the Autoteams setting, and TeamsSorting setting will split the teams into two separate columns.

This allows easier visual view of how each Team stacks up, with coresponding Team Values, and Games Played.

The Teams sorting drop down menu allows to reorder the slots so correct players mirror each other.

This can be very map dependent. There are 4 options but not every map will line up the slots perfectly.

So some adjustments are necessary to get players lined up. Maps that tend to not work as well are those with teams in corners.

In cases such as Setons where you want Rock vs Rock this isn't an issue, but maps like Wonder, the wings won't be lined up without air players being misasligned.

Still its easier to manage balance at a glance.

For Maps that are top vs bottom, you use Horizontal Position. And Left to Right, you use Vertical Position from menu.

The lobby will remember your selections for individual maps.

The lobby will also remember Left vs Right, Odd vs Even, etc.

You can swap the players by simply selecting the swap button between the two columns.

Or by using the new FAF method of clicking the slot number of each player.

For Manual Teams, it will just use the default view, or you can select Disable from the TeamsSorting menu.

It will do this automatically on maps with survival in the name.


New Features and Fixes

---

1. ) Updates Kyro's to support UI Scaling
1. ) Add Two New Buttons. One for Unit Sharing to switch between Full Share and Default Share, etc

Penguins AutoBalance Button also added

1. ) Chat, Observer resizes to match how many slots are displayed.

So we get most possible area for Chat Window.

1. ) Fixes Bug where Kyro's would crash on maps with uneven Team Sorting. It is possible to have uneven Team Columns, which makes it obvious when wrong AutoTeams is selected. Since it now saves AutoTeams, this is less an issue.
1. ) The Drop Down Color Menu now updates to only show available colors.

This sometimes doesn't update your own color in offline lobby without refreshing, but works fine Online.

1. ) Fixed not being able to reclick Ready in certain cases ( ongoing, bug may still be present)

Not entirely sure if this was unique to Kyro's Lobby, or if issue still crops up. I had same issue in orig Lobby from time to time.

In the cases I was able to reproduce, we simply unready the player first to try and avoid this.

This was a more frequent occurence as host then client, but I haven't been able to reproduce since making changes.

1. ) As a result you can switch to an open slot by clicking on the map positions without unReadying first, whether you are host or client.
1. ) Misc changes to closer match how stock FAF lobby behaves.


It would also be nice to have option to move Slots Manually to account for maps that don't line up, but this is probably not feasible at the moment.

Maybe in future will just make it Sort by highest to lowest to simply things.


Other Kyro's Commands -- have not personally tested all these but /stats and /info are helpful

---

/help : Displays this")

/pm [playername] : Sends a private message (/pm KyrO Hello)")

/stats : Displays the total rating and number of games of both teams to everyone")

/myslot [slotnbr] : Saves your prefered slot on this map. You will be moved to this slot (if available) as soon as you join a lobby with this map (/myslot 12)")

/ban [playername] [reason?] : Bans a player. This player will be auto-kicked if he tries to join the lobby (/ban KyrO I don't like you)")

/ban : Lists all banned players")

/unban [playername] : Unbans a player")

/unban : Unbans all players")

/cpulimit [max] : Auto-kicks all players who have a higher cpu score than the provided value (/cpulimit 250)")

/cpulimit : Removes the cpu limit")

/ranklimit [min] [max] : Auto-kicks all players who do not have a rating between the provided values (/ranklimit 800 1600)")

/ranklimit : Removes the rank limit")

/gameslimit [min] [max] : Auto-kicks all players who do not have a number of games between the provided values (/gameslimit 100 10000)")

/gameslimit : Removes the number of games limit")

/info [playername] [text] : Saves a comment about a player (/info KyrO Slow cpu)")

/info [playername] : Displays the comment about a player")

/info : Displays the comments of all connected players")

/info all : Displays all saved comments")

/reminfo [playername] : Removes the comment about a player")
