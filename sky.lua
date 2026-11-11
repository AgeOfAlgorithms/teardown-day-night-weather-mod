-- The look of the sky by the hour (no engine calls here: pure tables and maths, tested offline).
-- Hours run 0-24: 0 midnight, 6 sunrise, 12 noon, 18 sunset.
--
-- One "sun" light does both jobs: the sun by day, the moon by night. Its brightness passes through 0 at the two
-- twilight keys (DN_DAWN, DN_DUSK): there the light jumps from one arc to the other and the sky picture is swapped,
-- both unseen in the dark.

DN_DAWN = 5.25           -- night sky -> day sky, moon -> sun
DN_DUSK = 18.75          -- day sky -> night sky, sun -> moon
DN_DAY_SKY = "MOD/images/sky_day.dds"   -- (our own picture, tools/make_sky.py: the game's day.dds has a sun painted in, a second one that stood still)
DN_NIGHT_SKY = "cloudy.dds"      -- (the game's own night preset: its cloud picture, very dark)
DN_NIGHT_SKY_SCALE = 1           -- (the night picture's brightness against the keys' `sky`)
DN_NIGHT_SOUND = "outdoor/night.ogg"
DN_MOON = 0.003          -- the moon's light at full night (the night keys' `sun`)
DN_TILT = 30             -- degrees the arc leans off the zenith (the noon sun stands 60 degrees up)
DN_MIN_EL = 0.14         -- the light never comes from lower than this (sine of the elevation: long shadows, not endless)

-- sky = skyboxbrightness, tint = skyboxtint, sun = sunBrightness, suntint = sunColorTint, fog = fogColor,
-- fp = fogParams (start, end, amount, exponent), sfs = sunFogScale, glare = sunGlare
-- const = the share of the map's own `constant` light that is left (a flat light on everything, also indoors).
-- What makes a night dark (dark.lua, verified in-game): the map's constant light off and the sky / moon / fog colour
-- near zero. NOT a cap on the auto-exposure: that dims every lamp with the night (exposure 1 2.5 more than halved them).
DN_KEYS = {
	{h = 0.00, const = 0, sky = 0.0003, tint = {0.60, 0.75, 1.00}, sun = 0.003, suntint = {0.55, 0.70, 1.00}, fog = {0.0001, 0.0001, 0.00013}, fp = {20, 120, 0.90, 2}, sfs = 0.00, glare = 0.05},
	{h = 4.50, const = 0, sky = 0.0003, tint = {0.60, 0.75, 1.00}, sun = 0.003, suntint = {0.55, 0.70, 1.00}, fog = {0.0001, 0.0001, 0.00013}, fp = {20, 120, 0.90, 2}, sfs = 0.00, glare = 0.05},
	{h = 5.25, const = 0.3, sky = 0.02, tint = {0.55, 0.65, 1.00}, sun = 0.00, suntint = {0.80, 0.65, 0.70}, fog = {0.010, 0.010, 0.015}, fp = {20, 130, 0.90, 2}, sfs = 0.00, glare = 0.05},
	{h = 6.00, const = 1, sky = 0.50, tint = {1.00, 0.55, 0.35}, sun = 0.80, suntint = {1.00, 0.55, 0.30}, fog = {0.550, 0.300, 0.180}, fp = {30, 160, 0.95, 6}, sfs = 0.80, glare = 0.80},
	{h = 7.50, const = 1, sky = 0.90, tint = {1.00, 0.95, 0.90}, sun = 3.50, suntint = {1.00, 0.80, 0.60}, fog = {0.850, 0.850, 0.850}, fp = {50, 200, 0.90, 8}, sfs = 0.20, glare = 0.50},
	{h = 12.0, const = 1, sky = 1.00, tint = {1.00, 1.00, 1.00}, sun = 4.00, suntint = {1.00, 0.80, 0.60}, fog = {0.900, 0.900, 0.900}, fp = {50, 200, 0.90, 8}, sfs = 0.15, glare = 0.50},
	{h = 16.5, const = 1, sky = 0.90, tint = {1.00, 0.95, 0.90}, sun = 3.50, suntint = {1.00, 0.80, 0.60}, fog = {0.850, 0.850, 0.850}, fp = {50, 200, 0.90, 8}, sfs = 0.20, glare = 0.50},
	{h = 18.0, const = 1, sky = 0.60, tint = {1.00, 0.50, 0.20}, sun = 1.00, suntint = {1.00, 0.50, 0.25}, fog = {0.300, 0.200, 0.080}, fp = {80, 200, 1.00, 6}, sfs = 1.00, glare = 0.80},
	{h = 18.75, const = 0.3, sky = 0.02, tint = {0.55, 0.65, 1.00}, sun = 0.00, suntint = {0.80, 0.65, 0.70}, fog = {0.010, 0.010, 0.015}, fp = {20, 130, 0.90, 2}, sfs = 0.00, glare = 0.05},
	{h = 19.5, const = 0, sky = 0.0003, tint = {0.60, 0.75, 1.00}, sun = 0.003, suntint = {0.55, 0.70, 1.00}, fog = {0.0001, 0.0001, 0.00013}, fp = {20, 120, 0.90, 2}, sfs = 0.00, glare = 0.05},
	{h = 24.0, const = 0, sky = 0.0003, tint = {0.60, 0.75, 1.00}, sun = 0.003, suntint = {0.55, 0.70, 1.00}, fog = {0.0001, 0.0001, 0.00013}, fp = {20, 120, 0.90, 2}, sfs = 0.00, glare = 0.05},
}

function dnWrapHour(h)
	h = h % 24
	if h < 0 then h = h + 24 end
	return h
end

local function mix(a, b, k)
	if type(a) == "table" then
		local out = {}
		for i = 1, #a do out[i] = a[i] + (b[i] - a[i]) * k end
		return out
	end
	return a + (b - a) * k
end

-- the blended key at an hour: {sky, tint, sun, suntint, fog, fp, sfs, glare}
function dnSkyAt(h)
	h = dnWrapHour(h)
	local a, b = DN_KEYS[1], DN_KEYS[2]
	for i = 1, #DN_KEYS - 1 do
		if h >= DN_KEYS[i].h and h <= DN_KEYS[i + 1].h then a, b = DN_KEYS[i], DN_KEYS[i + 1]; break end
	end
	local k = (b.h > a.h) and (h - a.h) / (b.h - a.h) or 0
	local out = {}
	for name, v in pairs(a) do
		if name ~= "h" then out[name] = mix(v, b[name], k) end
	end
	return out
end

function dnIsDaySky(h)
	h = dnWrapHour(h)
	return h >= DN_DAWN and h < DN_DUSK
end

-- lamps and lit windows: on from a little before sunset to a little after sunrise
function dnLampsOn(h)
	h = dnWrapHour(h)
	return h < 6.25 or h >= 17.75
end

-- Where the sun (by day) or the moon (by night) stands: a unit vector toward it, and whether it is the moon. The
-- real arc: below the horizon (y < 0) before rising and after setting.
-- The sun rises at +x (6:00), stands highest at noon leaning toward +z, sets at -x (18:00); the moon takes the same
-- arc twelve hours later.
function dnArcDir(h)
	h = dnWrapHour(h)
	local day = dnIsDaySky(h)
	local a
	if day then a = (h - 6) / 12 * math.pi else a = (dnWrapHour(h - 18)) / 12 * math.pi end
	local tilt = math.rad(DN_TILT)
	return {math.cos(a), math.sin(a) * math.cos(tilt), math.sin(a) * math.sin(tilt)}, not day
end

-- Where the light comes from: the arc, but never from lower than DN_MIN_EL.
function dnLightDir(h)
	local d, moon = dnArcDir(h)
	local x, y, z = d[1], d[2], d[3]
	if y < DN_MIN_EL then y = DN_MIN_EL end
	local l = math.sqrt(x * x + y * y + z * z)
	return {x / l, y / l, z / l}, moon
end

-- How strongly the sun's or the moon's disc shows, 0-1: it fades in over the horizon, and the moon with its light.
function dnDiscAlpha(h)
	local d, moon = dnArcDir(h)
	local a = d[2] / 0.06
	if a < 0 then a = 0 elseif a > 1 then a = 1 end
	if moon then
		local m = dnSkyAt(h).sun / DN_MOON
		if m > 1 then m = 1 end
		a = a * m
	end
	return a, moon
end

-- how much daylight there is, 0 (night) to 1 (noon): for other mods (daynight.light)
function dnDaylight(h)
	local k = dnSkyAt(h)
	if not dnIsDaySky(h) then return 0 end
	local v = k.sun / 4
	if v > 1 then v = 1 end
	return v
end
