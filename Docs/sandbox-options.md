# Sandbox options

Every option is on the **PhunTaxi** page of the sandbox settings. The
defaults are what a new server gets. A change is picked up within ten minutes
of game time.

Every constraint can be turned off. If one is taking the phun out of it on
your server, turn it off.

## Waking up

| Option                  | Default | Range | What it does                                                                                                                                                                                                                       |
| ----------------------- | ------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wake Up Indoors         | on      |       | A new character wakes up in the Taxi Garage, an off grid room, and leaves by taxi to a place they know. Off, or with no room to be had, they are put straight at the last place their player chose, or at a start point they know. |
| Respawn Costs Something | off     |       | **Not used yet.** Reserved for a cost on choosing where to wake up. It changes nothing in this version.                                                                                                                            |

## Finding places

| Option                   | Default | Range    | What it does                                                                                                                                                                                                                             |
| ------------------------ | ------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Place Discovery Range    | 12      | 1 to 300 | How close, in squares, you have to get to a place (not a pay phone) to remember it. Checked once a game minute, so you have to stay near for a moment: running past may not count.                                                       |
| Show Undiscovered Points | off     |          | On, places you have not found yet are listed greyed out, so the list is somewhere to head for. Pay phones are never listed until used. Off, the server does not send them to the client at all, so they cannot be read out of it either. |

## Pay phones

| Option                       | Default | Range      | What it does                                                                                                                                                                                                                                                                                             |
| ---------------------------- | ------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pay Phone Chance             | 35      | 0 to 100   | Percent chance a vanilla pay phone becomes a live one that is a spawn point. Rolled once per phone, the first time its square loads. 0 turns the swap off. The shipped extra phone spots are not rolled on this: Pay Phone Spacing alone decides which of them are used.                                 |
| Pay Phone Spacing            | 300     | 0 to 10000 | No pay phone becomes live within this many squares of one that already has. It also decides which of the shipped extra phone spots are used, drawn once per world: change it after a world has started and the spots already drawn stay as they are. 0 for no spacing, which puts a phone on every spot. |
| Pay Phone Discovery Range    | 0       | 0 to 30    | How close you have to get to a live phone to remember it, and it rings once to say so. At 0 you have to pick up the receiver. Meant to be small: it stands in for walking up to the phone, not for walking down its street.                                                                              |
| Undiscovered Pay Phones Ring | on      |            | A live phone you have not found yet rings now and then while you are near it.                                                                                                                                                                                                                            |
| Pay Phone Ring Range         | 30      | 1 to 200   | How close, in squares, you have to be to hear it.                                                                                                                                                                                                                                                        |

With PhunZones installed, a zone can set its own **Pay Phone Chance** and
**Pay Phone Spacing** (in the zone editor, under Mods), so a city can have
more pay phones, closer together, than the countryside. Either left unset
uses the option above; 0 is a value, not unset. The chance is rolled once
per phone, so raising it reaches only phones not rolled yet, except that a
zone at 0 leaves its phones unrolled, as the option at 0 does. The spacing
is the zone of the phone being placed: a phone in a dense zone may go up
close to one just outside it.

## Player built pay phones

| Option                  | Default | Range      | What it does                                                                                            |
| ----------------------- | ------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| Allow Player Pay Phones | on      |            | Players may craft a Pay Phone Kit and install it.                                                       |
| Player Pay Phone Limit  | 5       | 0 to 99    | How many pay phones one player may have standing at once. 0 for no limit.                               |
| Built Pay Phone Spacing | 50      | 0 to 10000 | A player cannot install a pay phone within this many squares of any other live phone. 0 for no spacing. |

## The taxi

The first ride, out of the Taxi Garage, is always free and is not affected by
these. They are for fast travel between pay phones.

| Option                  | Default | Range       | What it does                                                                                      |
| ----------------------- | ------- | ----------- | ------------------------------------------------------------------------------------------------- |
| Taxi Between Pay Phones | off     |             | A player can call a taxi from a pay phone they know to any other pay phone they know, for a fare. |
| Taxi Fare Per Square    | 1       | 0 to 1000   | Cents per square, measured in a straight line.                                                    |
| Taxi Minimum Fare       | 100     | 0 to 100000 | The least a ride costs, in cents. 100 is $1.00.                                                   |
| No Taxi Near Zombies    | 6       | 0 to 50     | No taxi comes while a zombie is within this many squares of you. 0 turns the check off.           |

A fare is paid in **PhunMart** change. With both fare options at 0 the taxi
is free and PhunMart is not needed. With either above 0 and PhunMart not
installed, every ride is refused ("The taxis are not running") and the server
log says why.

The fare is only taken once the ride has been accepted, so a ride that is
refused for any reason costs nothing.

## Other

| Option | Default | Range | What it does                                                                         |
| ------ | ------- | ----- | ------------------------------------------------------------------------------------ |
| Debug  | off     |       | Verbose logging of point registration, discovery and spawning to the server console. |
