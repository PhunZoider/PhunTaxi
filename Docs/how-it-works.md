# How it works

For anybody curious why PhunTaxi behaves the way it does. Nothing here is
needed to play or to run a server.

## Unlocks belong to the player, not the character

The only moment an unlock is worth anything is choosing where to wake up, and
that moment belongs to the **next** character: dying makes a new character
with nothing on it. A list kept on the character would die with the one who
earned it.

So there is one record per player in the world's global ModData, keyed by
username on a server and by the local player slot in single player. It holds
what they have found and the last place they chose. A character from an older
version that still carries a list of its own has it folded into the record
once, and cleared, so there is one list and not two that disagree.

The cost is that `global_mod_data.bin` in the save now carries everybody's
exploring, and a wipe takes it.

## One free ride, once

The Go button works while a character is in the Taxi Garage, and the garage
has no way out but the taxi, so it works exactly once. After that the window
is a map.
A button that took you anywhere you had been, whenever you liked, would be
fast travel, and finding a place would be worth nothing once you had. The
paid taxi between pay phones is the fast travel (the **Fast Travel**
option), and it is off unless the server turns it on.

On a server, "new" is simply where the character is. Every vanilla spawn
region is collapsed to one square in the garage's cell, whatever Spawn at
Garage says, so a new character always lands there; one who reconnects is
wherever they logged out, and only one still in the garage has a ride to
take. Nothing is stored for it, so there is nothing to lose. A character
who respawns in their safehouse through vanilla's own option was never in
the garage and gets no free ride.

Single player's spawn selector runs before any mod code, so there "new" is
decided once, by the character's age the first time the game looks, and
stamped on the character: one who survived for weeks before the mod was
installed is not handed a free teleport by the install.

## Arriving

The server, not the vanilla spawn selector, puts a new character in the
Taxi Garage. The garage is a PhunInteriors room, shared when full: a server
may only have one, and two new characters in one room beats one turned away.
It has no "Step outside", because the taxi is the way out. Every ride goes
through PhunInteriors' own exit, so the room is left properly and zombies are
cleared off the square you land on.

On a server the vanilla spawn regions are collapsed to one square, so the
vanilla selector has one choice and skips itself.

## Pay phones are decided for the whole map at once

Every square a live phone could go on is known before anybody gets there:
the pay phones the maps themselves put down (read out of the map files and
shipped as a list) and the extra spots PhunTaxi ships for the empty parts
of the map. Each new world gives every one of them a random rank, once, and
takes them in rank order, skipping any too close to one already taken. So
which phone on a street goes live is chance, and not the direction the first
player came from. A taken phone counts for the spacing straight away, even
though it only goes up when somebody gets there.

Only a phone nobody has seen yet can move. If one goes missing, or the map
has no pay phone where the list says (a map update moved it), the next in
rank nearby takes its place. And since the server knows every square that
matters, a square that loads with nothing on the list costs it nothing.

## Nobody rides into your safehouse

Every ride, the first one and the taxi, is checked against the safehouse
claims **before** anybody moves, not by bouncing them back afterwards. That
check is what makes player built pay phones safe to allow indoors: nobody but
a safehouse's members can ride to a phone inside it.

## Found on a timer, not on every step

Discovery is checked once a game minute, not every time somebody moves. A
spawn point is a place you walk to and stay near for a moment, not a tripwire
you can sprint through, and checking every online player sixty times a second
for something that happens once a session is how a mod ends up being the
reason a server is slow.

## Hidden means not sent

With Show Undiscovered Places off, the server does not send the places a
player has not found. A client that was sent the coordinates could draw them
whatever the option said, so an option enforced only in the window would not
be enforced at all.

## An admin's setup survives a wipe

What an admin sets up lives in `PhunTaxi.json` in the game's Lua folder, not
in the save, so the next world starts with it. That includes deleting a point the
code ships: the code registers it again on every boot, so a deletion is a
tombstone in the file that keeps it out, not an edit of the registry, and
taking the tombstone away brings it back as the code has it now. Every change is written at
once, and undone if the write fails. A file that did not parse is never
written over.

Kept pay phones another mod ships work the same way round, as PhunZones'
shipped zones do: they are merged under the file at boot, and the file holds
only the difference. A shipped phone left alone is never written, so the next
version's list reaches every server; releasing one writes a `kept: false`
entry, because taking a line out of a file it was never in cannot undo it.
PhunTaxi's own named phones are not kept: they are spots, drawn once per
world and spaced, so each town gets one of them.

## One code path

Single player and multiplayer run the same code. In single player a request
that would go to the server is handled directly instead. Two implementations
drift apart, and the one nobody tests is the one that breaks.
