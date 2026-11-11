-- Weather: four layers that overlap, each a level 0-1 that drifts slowly toward its target (API.md, PROJECT.md).
--   cloud   the sky closes: grey sky picture, weak sun, no stars
--   rain    the game's rain, wet ground and puddles, the rain's sound (clouds come first and stay until it stops)
--   fog     thick fog close in
--   storm   lightning and thunder (only while it rains hard)
-- Two kinds of front, each on its own clock, so they can overlap: a SKY front (cloudy, rain or a thunderstorm) and
-- a FOG front. Every few minutes each clock rolls a die: mostly nothing happens and it waits for its next roll, so
-- the weather keeps no timetable (the user, 2026-11-11) and clear skies are the rule.
-- All of it runs on the host; the levels are published (synced) for other mods and for each client's stars / thunder.
--
-- Registry, read on the host:   daynight.set.weather   "clear", "cloudy", "rain", "storm", "fog" or several joined
--                                                      with "+" ("rain+fog"): starts that now; taken once
--                               daynight.weather.hold  the weather stays as it is (no front ends, none starts)
--                               daynight.weather.off   clear skies, no fronts
-- published (synced):           daynight.weather (the name of what is strongest), daynight.weather.all (all that is
--                               going on, "rain+fog"), daynight.cloud, daynight.rain,
--                               daynight.fog, daynight.storm, daynight.wet (0-1), daynight.thunder (a counter)

Weather = {}

-- seconds a level takes from 0 to 1 and back
WX_RISE = {cloud = 50, rain = 35, fog = 70, storm = 20}
WX_FALL = {cloud = 70, rain = 45, fog = 90, storm = 20}
WX_WET_RISE, WX_WET_FALL = 60, 240      -- the ground gets wet in a minute of rain and stays wet for minutes
-- minutes between two rolls of a kind, the chance a roll starts a front at the "Rare" setting, minutes a front lasts
WX_SKY_GAP = {8, 16}
WX_FOG_GAP = {10, 20}
WX_SKY_CHANCE = 0.45
WX_FOG_CHANCE = 0.40
WX_SKY_KINDS = {cloudy = 0.25, rain = 0.50}      -- the share of sky fronts that are only cloudy / rain (the rest: storms)
WX_SKY_LASTS = {3, 7}
WX_FOG_LASTS = {3, 6}
WX_OFTEN = {[2] = 1, [3] = 1.7, [4] = 2.6}       -- the option: Rare, Sometimes, Often (1 = off) -> the chances' scale
WX_THUNDER_GAP = {5, 16}                -- seconds between two flashes in a full storm
-- a flash swells and dies away, never a hard cut (the user, 2026-11-11: too abrupt, and hard flashes are a risk for
-- photosensitive players): seconds it rises, stays, falls
WX_FLASH_RISE, WX_FLASH_HOLD, WX_FLASH_FALL = 0.4, 0.08, 0.4       -- (the user: in as long as out)

local level = {cloud = 0, rain = 0, fog = 0, storm = 0}
local target = {cloud = 0, rain = 0, fog = 0, storm = 0}
local wet = 0
local sky = {wait = 0, left = 0}        -- wait: seconds to the next front; left: seconds the running one still lasts
local fog = {wait = 0, left = 0}
local thunderT = 0
local thunderN = 0
local flashT = 0                        -- seconds left of the running flash
local flashHold = 0                     -- its middle part's length

local function between(r) return r[1] + (r[2] - r[1]) * math.random() end

local function often()
	local i = GetInt("savegame.mod.weather")
	if i == 1 then return nil end
	return WX_OFTEN[i] or 1
end

function Weather.level(name) return level[name] end
function Weather.wet() return wet end
-- how bright the running flash is, 0-1 (smooth at both ends)
function Weather.flash()
	if flashT <= 0 then return 0 end
	local e = WX_FLASH_RISE + flashHold + WX_FLASH_FALL - flashT
	local f = 1
	if e < WX_FLASH_RISE then
		f = e / WX_FLASH_RISE
	elseif e > WX_FLASH_RISE + flashHold then
		f = flashT / WX_FLASH_FALL
	end
	f = math.max(0, math.min(1, f))
	return f * f * (3 - 2 * f)
end

-- the levels set at once, no drifting (test copies' photo runs)
function Weather.set(cloud, rain, fogLevel, storm)
	level.cloud, level.rain, level.fog, level.storm = cloud, rain, fogLevel, storm
	target.cloud, target.rain, target.fog, target.storm = cloud, rain, fogLevel, storm
	wet = rain
	sky.left = (cloud > 0 or rain > 0) and 600 or 0
	fog.left = fogLevel > 0 and 600 or 0
end

-- a flash now, `seconds` long
function Weather.strike(seconds)
	thunderN = thunderN + 1
	flashHold = seconds or WX_FLASH_HOLD
	flashT = WX_FLASH_RISE + flashHold + WX_FLASH_FALL
	SetInt("daynight.thunder", thunderN, true)
end

-- the strongest thing going on, for mods that want one word
function Weather.name()
	if level.storm > 0.5 and level.rain > 0.5 then return "storm" end
	if level.rain > 0.15 then return "rain" end
	if level.fog > 0.4 then return "fog" end
	if level.cloud > 0.4 then return "cloudy" end
	return "clear"
end

-- everything going on, joined with "+" in a fixed order ("cloudy+rain+storm+fog"); "clear" when nothing is.
-- A storm also lists the rain and the clouds it comes with.
function Weather.all()
	local out = {}
	if level.cloud > 0.4 then out[#out + 1] = "cloudy" end
	if level.rain > 0.15 then out[#out + 1] = "rain" end
	if level.storm > 0.5 and level.rain > 0.5 then out[#out + 1] = "storm" end
	if level.fog > 0.4 then out[#out + 1] = "fog" end
	if #out == 0 then return "clear" end
	return table.concat(out, "+")
end

local function startSky(kind)
	if kind == "cloudy" then
		target.cloud, target.rain, target.storm = 0.6 + 0.4 * math.random(), 0, 0
	elseif kind == "rain" then
		target.cloud, target.rain, target.storm = 1, 0.3 + 0.5 * math.random(), 0
	else
		target.cloud, target.rain, target.storm = 1, 0.85 + 0.15 * math.random(), 1
	end
	sky.left = between(WX_SKY_LASTS) * 60
end

local function startFog()
	target.fog = 0.55 + 0.45 * math.random()
	fog.left = between(WX_FOG_LASTS) * 60
end

function Weather.pickSky()
	local r = math.random()
	return (r < WX_SKY_KINDS.cloudy and "cloudy") or (r < WX_SKY_KINDS.cloudy + WX_SKY_KINDS.rain and "rain") or "storm"
end

local function clearSky() target.cloud, target.rain, target.storm = 0, 0, 0; sky.left = 0 end
local function clearFog() target.fog = 0; fog.left = 0 end

-- The opening rolls, a second into the session: by then the frames' uneven lengths have stirred the generator (see
-- Weather.tick), in case the game starts every script on the same random sequence.
local opening = nil

local function open()
	-- a session does not open on fresh clocks: each die is rolled once right away (a hit: that weather is already
	-- there, somewhere in its run), and the first wait is anywhere inside a gap
	sky.wait, sky.left = math.random() * WX_SKY_GAP[2] * 60, 0
	fog.wait, fog.left = math.random() * WX_FOG_GAP[2] * 60, 0
	local o = often()
	if o and not GetBool("daynight.weather.off") then
		if math.random() < math.min(0.95, WX_SKY_CHANCE * o) * 0.5 then
			startSky(Weather.pickSky())
			sky.left = sky.left * (0.3 + 0.7 * math.random())
			level.cloud, level.rain, level.storm, wet = target.cloud, target.rain, target.storm, target.rain
		end
		if math.random() < math.min(0.95, WX_FOG_CHANCE * o) * 0.5 then
			startFog()
			fog.left = fog.left * (0.3 + 0.7 * math.random())
			level.fog = target.fog
		end
	end
end

function Weather.init()
	for k in pairs(level) do level[k], target[k] = 0, 0 end
	wet, thunderT, thunderN, flashT = 0, 0, 0, 0
	opening = 1
	ClearKey("daynight.set.weather")
end

-- a front's clock: while one runs, its time runs out; otherwise wait for the next roll, and on a roll start one
-- with `chance` or wait again
local function front(f, gap, chance, start, clear, dt)
	if f.left > 0 then
		f.left = f.left - dt
		if f.left <= 0 then clear(); f.wait = between(gap) * 60 end
	else
		f.wait = f.wait - dt
		if f.wait <= 0 then
			if math.random() < chance then start() else f.wait = between(gap) * 60 end
		end
	end
end

-- returns true when something changed that should be shown at once (a flash is running)
function Weather.tick(dt)
	for i = 1, math.floor(dt * 1000000) % 3 do math.random() end      -- (stirred by the frame time's last digits)
	if opening then
		opening = opening - dt
		if opening > 0 then return false end
		opening = nil
		open()
	end
	if HasKey("daynight.set.weather") then
		local want = GetString("daynight.set.weather")
		ClearKey("daynight.set.weather")
		clearSky(); clearFog()
		for word in string.gmatch(want, "[^+]+") do
			if word == "cloudy" or word == "rain" or word == "storm" then startSky(word) end
			if word == "fog" then startFog() end
		end
	end
	local o = often()
	if GetBool("daynight.weather.off") or not o then
		if not GetBool("daynight.weather.off") and (sky.left > 0 or fog.left > 0) then
			-- (the option is off but a mod asked for weather: let that front run out)
			front(sky, WX_SKY_GAP, 0, function() end, clearSky, dt)
			front(fog, WX_FOG_GAP, 0, function() end, clearFog, dt)
		else
			clearSky(); clearFog()
		end
	elseif not GetBool("daynight.weather.hold") then
		front(sky, WX_SKY_GAP, math.min(0.95, WX_SKY_CHANCE * o), function()
			startSky(Weather.pickSky())
		end, clearSky, dt)
		front(fog, WX_FOG_GAP, math.min(0.95, WX_FOG_CHANCE * o), startFog, clearFog, dt)
	end

	-- the clouds come before the rain and stay until it has stopped; thunder only in hard rain
	local goal = {cloud = target.cloud, rain = target.rain, fog = target.fog, storm = target.storm}
	if level.cloud < 0.6 then goal.rain = 0 end
	if level.rain > 0.05 then goal.cloud = math.max(goal.cloud, 1) end
	if level.rain < 0.5 then goal.storm = 0 end
	for k, v in pairs(level) do
		if v < goal[k] then
			level[k] = math.min(goal[k], v + dt / WX_RISE[k])
		elseif v > goal[k] then
			level[k] = math.max(goal[k], v - dt / WX_FALL[k])
		end
	end
	if wet < level.rain then wet = math.min(level.rain, wet + dt / WX_WET_RISE) else wet = math.max(level.rain, wet - dt / WX_WET_FALL) end

	local changed = false
	if flashT > 0 then
		flashT = flashT - dt
		changed = true                                       -- (shown every frame while it swells and fades)
	end
	if level.storm > 0.5 then
		thunderT = thunderT - dt
		if thunderT <= 0 then
			thunderT = between(WX_THUNDER_GAP) / level.storm
			thunderN = thunderN + 1
			flashHold = WX_FLASH_HOLD
			flashT = WX_FLASH_RISE + flashHold + WX_FLASH_FALL
			SetInt("daynight.thunder", thunderN, true)
			changed = true
		end
	else
		thunderT = 2
	end
	return changed
end

function Weather.publish()
	SetString("daynight.weather", Weather.name(), true)
	SetString("daynight.weather.all", Weather.all(), true)
	SetFloat("daynight.cloud", level.cloud, true)
	SetFloat("daynight.rain", level.rain, true)
	SetFloat("daynight.fog", level.fog, true)
	SetFloat("daynight.storm", level.storm, true)
	SetFloat("daynight.wet", wet, true)
end

-- ---------------------------------------------------------------- what the weather does to the hour's look
-- `k` is sky.lua's blended key (changed in place); returns the day sky picture and the ambience the weather wants
-- (nil: the hour's own)

WX_SKY_CLOUDY = "MOD/images/sky_cloudy.dds"
WX_SKY_OVERCAST = "MOD/images/sky_overcast.dds"
WX_RAIN_FOG = {0, 90, 0.9, 2}            -- fogParams in full rain (the game's rain presets)
WX_FOG_FOG = {0, 38, 1.0, 1.5}           -- and in full fog
WX_FLASH_SKY = 0.30                      -- the sky's brightness in a flash, at night (by day: 2.5 times the hour's)

local function lerp(a, b, t) return a + (b - a) * t end

function Weather.look(k, daySky)
	local c, r, f = level.cloud, level.rain, level.fog
	k.sun = k.sun * (1 - 0.92 * c)
	k.glare = k.glare * (1 - c)
	k.sfs = k.sfs * (1 - c)
	k.sky = k.sky * (1 - 0.40 * c) * (1 - 0.25 * r)
	-- the fog's colour goes grey (as bright as the hour's own fog), the fog comes close
	local m = math.max(k.fog[1], k.fog[2], k.fog[3])
	local w = math.max(f, 0.6 * c, 0.8 * r)
	local dim = 1 - 0.35 * math.max(c, r)
	k.fog = {lerp(k.fog[1], m * 0.80, w) * dim, lerp(k.fog[2], m * 0.82, w) * dim, lerp(k.fog[3], m * 0.86, w) * dim}
	local fp = {}
	for i = 1, 4 do
		fp[i] = lerp(k.fp[i], WX_RAIN_FOG[i], 0.8 * r)
		fp[i] = lerp(fp[i], WX_FOG_FOG[i], f)
	end
	k.fp = fp
	-- the sunset's colours fade under clouds
	for i = 1, 3 do k.tint[i] = lerp(k.tint[i], 1, 0.7 * c) end
	local fl = Weather.flash()
	if fl > 0 then
		k.sky = lerp(k.sky, daySky and k.sky * 2.5 + 0.2 or WX_FLASH_SKY, fl)
		k.tint = {lerp(k.tint[1], 0.85, fl), lerp(k.tint[2], 0.9, fl), lerp(k.tint[3], 1, fl)}
	end
	local picture = nil
	if daySky then picture = (c >= 0.66 and WX_SKY_OVERCAST) or (c >= 0.33 and WX_SKY_CLOUDY) or nil end
	local sound = (r > 0.6 and "outdoor/rain_heavy.ogg") or (r > 0.15 and "outdoor/rain_light.ogg") or nil
	return picture, sound
end
