#version 2
-- Day & Night: a day / night cycle on any map (a global mod). The host's clock drives the sky, the sun and the moon,
-- the fog and the lamps for everyone (sky.lua: the look by the hour; daynight.lua: the clock and the registry API).
-- For maps and mods: API.md.

#include "sky.lua"
#include "weather.lua"
#include "daynight.lua"

-- (test builds add their modules here)

function server.init()
	DayNight.serverInit()
	if DAYNIGHT_TEST then DAYNIGHT_TEST.serverInit() end
end

function server.tick(dt)
	DayNight.serverTick(dt)
	if DAYNIGHT_TEST then DAYNIGHT_TEST.serverTick(dt) end
end

function server.destroy()
	DayNight.serverDestroy()
end

function client.init()
	DayNight.clientInit()
end

function client.tick(dt)
	DayNight.clientTick(dt)
	if DAYNIGHT_TEST then DAYNIGHT_TEST.clientTick(dt) end
end
