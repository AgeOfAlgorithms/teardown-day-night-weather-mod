# Day & Night: API for maps and mods

Day & Night is a global mod: a day / night cycle (and, later, weather) on any map. The host's clock drives the sky,
the sun and the moon, the fog and the lamps for every player. A map or another mod works with it through registry
keys on the host; nothing has to be included or bundled.

Hours run 0-24: 0 midnight, 6 sunrise, 12 noon, 18 sunset. By default the daylight (5:15 to 18:45) takes 9 minutes
and the night 6, so an hour of the night passes faster than an hour of the day; the host sets both in the options. The sun rises at +x and sets at -x.

## Reading (published by Day & Night, synced to every machine)

| key | type | what |
|---|---|---|
| `daynight.present` | bool | Day & Night runs in this session |
| `daynight.time` | float | the hour, 0-24 (updated once a second) |
| `daynight.rate` | float | hours per second right now (0 while frozen; the night's hours pass at their own pace): run your own clock on between the once-a-second updates |
| `daynight.day` | int | 1 on the first day, +1 at every midnight |
| `daynight.night` | bool | true from dusk (18:45) to dawn (5:15); flips at once |
| `daynight.light` | float | daylight, 0 (night) to 1 (noon); 1 while stood down |
| `daynight.active` | bool | false while stood down (`daynight.off`) |

```lua
if GetBool("daynight.present") and GetBool("daynight.night") then ... end      -- e.g. a monster that only hunts at night
```

## Writing (set on the host, by a map's script or a mod's server script)

| key | type | what |
|---|---|---|
| `daynight.off` | bool | Day & Night stands down: the map's own environment is put back and nothing is set while it is true. The clock keeps running. |
| `daynight.off.<name>` | bool | the same, one key per mod (`daynight.off.mymod`), so two mods don't clear each other's hold |
| `daynight.freeze` | bool | the clock stands still |
| `daynight.set.time` | float | jump to this hour; taken once and cleared |
| `daynight.cycle` | float | seconds for a day and a night together, for this session (at least 20; daylight and night keep the proportion of the host's options); 0 or unset = the host's options |

```lua
-- a map that should open at dusk
function server.init() SetFloat("daynight.set.time", 17.5) end

-- a mod that needs its own sky for a while
SetBool("daynight.off.mymod", true)   ...   SetBool("daynight.off.mymod", false)
```

Clear your `off` / `freeze` keys in `server.destroy`: plain registry keys can outlive a level.

## Weather

Four layers that can overlap, each a level from 0 to 1 that drifts slowly: cloud, rain, fog and storm (lightning and
thunder, only in hard rain). Clear skies are the rule; now and then a front comes up by a roll of the dice.

Reading (synced to every machine, updated once a second):

| key | type | what |
|---|---|---|
| `daynight.weather` | string | the strongest thing going on: `clear`, `cloudy`, `rain`, `storm` or `fog` |
| `daynight.weather.all` | string | everything going on, joined with `+` in this order: `cloudy+rain+storm+fog` (a storm lists its rain and clouds too); `clear` when nothing is |
| `daynight.cloud` | float | 0 clear sky to 1 overcast |
| `daynight.rain` | float | 0 to 1 |
| `daynight.fog` | float | 0 to 1 |
| `daynight.storm` | float | 0 to 1; above 0.5 there is lightning |
| `daynight.wet` | float | how wet the ground is, 0 to 1 (stays up for minutes after the rain) |
| `daynight.thunder` | int | goes up by one at every flash of lightning |

Writing (on the host):

| key | type | what |
|---|---|---|
| `daynight.set.weather` | string | start this now: `clear`, `cloudy`, `rain`, `storm`, `fog`, or several joined with `+` (`"rain+fog"`); taken once and cleared. It builds up at the usual pace and lasts a few minutes |
| `daynight.weather.hold` | bool | the weather stays as it is: no front ends, none starts |
| `daynight.weather.off` | bool | clear skies, no fronts (an indoor or underwater map) |

```lua
if GetFloat("daynight.rain") > 0.3 then ... end              -- e.g. a creature that stays in when it rains
if GetString("daynight.weather.all"):find("fog") then ... end -- foggy, whatever else is going on
SetString("daynight.set.weather", "storm+fog")               -- a map's scripted storm
```
