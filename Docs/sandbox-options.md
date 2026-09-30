# Sandbox options

Every option is on the **PhunTaxi** page of the sandbox settings, in the
order below. The defaults are what a new server gets. A change is picked up
within ten minutes of game time.

Every constraint can be turned off. If one is taking the phun out of it on
your server, turn it off.

## Spawning and fast travel

| Option          | Default | Range | What it does                                                                                                                                                                                                                              |
| --------------- | ------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Spawn at Garage | on      |       | A new character wakes up in the Taxi Garage, a room off the map, and leaves by one free taxi ride to any place their player knows. Off, or with the garage full, they are put straight at the last place their player chose, or at a start point they know. |
| Fast Travel     | off     |       | A player can call a taxi from a pay phone they know to any other pay phone they know, for a fare. See [Fast travel](#fast-travel) below for the fare. The free ride out of the garage does not need this.                                     |

## Pay phones

| Option                    | Default | Range      | What it does                                                                                                                                                                                                                                                                                                                                  |
| ------------------------- | ------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pay Phone Chance          | 35      | 0 to 100   | Percent chance a pay phone the map puts down becomes a live one: a spawn point and a taxi stop. Each phone's roll is fixed for the world and checked against this on every boot, so a change reaches every phone not live yet. The shipped extra phone spots are not rolled on this: Pay Phone Spacing alone decides which of them are used. At 0, no map phone goes live. |
| Pay Phone Spacing         | 300     | 0 to 10000 | No pay phone becomes live within this many squares of one that already is. It decides which map phones and extra spots are used. Change it after a world has started and phones already standing stay, while ones nobody has reached yet are chosen again. 0 for no spacing.                                                                   |
| Pay Phone Discovery Range | 0       | 0 to 30    | How close you have to get to a live phone to remember it, and it rings once to say so. At 0 you have to pick up the receiver. Meant to be small: it stands in for walking up to the phone, not for walking down its street.                                                                                                                   |

With PhunZones installed, a zone can set its own **Pay Phone Chance** and
**Pay Phone Spacing** (in the zone editor, under Mods), so a city can have
more pay phones, closer together, than the countryside. Either left unset
uses the option above; 0 is a value, not unset. Both are read again on
every boot for phones nobody has reached yet, and a phone already standing
stays. The spacing is the zone of the phone being placed: a phone in a dense
zone may go up close to one just outside it.

## Finding places

| Option                   | Default | Range    | What it does                                                                                                                                                                                                                             |
| ------------------------ | ------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Place Discovery Range    | 12      | 1 to 300 | How close, in squares, you have to get to a place (not a pay phone) to remember it. Checked once a game minute, so you have to stay near for a moment: running past may not count.                                                       |
| Show Undiscovered Places | off     |          | On, places you have not found yet are listed greyed out, so the list is somewhere to head for. Pay phones are never listed until found. Off, the server does not send them to the client at all, so they cannot be read out of it either. |

## Ringing

| Option                       | Default | Range    | What it does                                                                                                                                                                                  |
| ---------------------------- | ------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Undiscovered Pay Phones Ring | on      |          | A live phone you have not found yet rings when you come near it. Each phone rings once each time you play, and picking it up stops it.                                                         |
| Pay Phone Ring Range         | 30      | 1 to 200 | How close, in squares, you have to be for a phone to ring for you. The ring carries about 30 squares, so above that a phone may ring where you cannot hear it, and it has still had its ring. |
| Pay Phone Ring Time          | 30      | 1 to 300 | How long a phone rings, in real seconds, before it gives up.                                                                                                                                  |

Each player sets the ring's volume, and the taxi's as it drives off, for
themselves in **Options, Mods, PhunTaxi**. 0 there mutes it for that player
only; it does not stop the phone ringing for anybody else.

## Fast travel

The first ride, out of the Taxi Garage, is always free and is not affected by
these. They are for **Fast Travel** between pay phones.

| Option                      | Default | Range       | What it does                                                                            |
| --------------------------- | ------- | ----------- | --------------------------------------------------------------------------------------- |
| Fast Travel Fare Per Square | 1       | 0 to 1000   | Cents per square, measured in a straight line.                                          |
| Fast Travel Minimum Fare    | 100     | 0 to 100000 | The least a ride costs, in cents. 100 is $1.00.                                         |
| No Fast Travel Near Zombies | 6       | 0 to 50     | No taxi comes while a zombie is within this many squares of you. 0 turns the check off. |

A fare is paid in **PhunMart** change. With both fare options at 0 the taxi
is free and PhunMart is not needed. With either above 0 and PhunMart not
installed, every ride is refused ("The taxis are not running") and the server
log says why.

The fare is only taken once the ride has been accepted, so a ride that is
refused for any reason costs nothing.

## Player built pay phones

| Option                  | Default | Range      | What it does                                                                                            |
| ----------------------- | ------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| Allow Player Pay Phones | on      |            | Players may craft a Pay Phone Kit and install it.                                                       |
| Player Pay Phone Limit  | 5       | 0 to 99    | How many pay phones one player may have standing at once. 0 for no limit.                               |
| Built Pay Phone Spacing | 50      | 0 to 10000 | A player cannot install a pay phone within this many squares of any other live phone. 0 for no spacing. |

## Other

| Option | Default | Range | What it does                                                                                    |
| ------ | ------- | ----- | ----------------------------------------------------------------------------------------------- |
| Debug  | off     |       | Verbose logging of point registration, discovery and spawning to the console. Last on the page. |
