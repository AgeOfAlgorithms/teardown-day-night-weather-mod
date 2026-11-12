-- Day & night: the host's clock and what it does to the environment (API.md, PROJECT.md).
-- The environment can only be set by the server and is the same for everyone, so all of this runs on the host.
--
-- Registry, read on the host:   daynight.off, daynight.off.<name>   stand down, the map's own environment back
--                               daynight.freeze                     the clock stands still
--                               daynight.set.time                   jump to this hour (0-24), taken once
--                               daynight.cycle                      seconds for a day and a night (0 / unset: the host's options)
-- published (synced):           daynight.present, daynight.time (hours), daynight.rate (hours per second),
--                               daynight.day, daynight.night, daynight.light, daynight.active (not stood down)

DayNight = {}

DN_APPLY_EVERY = 0.1             -- seconds between environment updates
DN_PUBLISH_EVERY = 1.0
DN_DAY_MIN = {2, 5, 9, 15, 30, 45}       -- the options page's daylight lengths, minutes (default 9)
DN_NIGHT_MIN = {1, 3, 6, 10, 20, 30}     -- and its night lengths (default 6): 15 minutes for a day and a night
DN_DAY_DEFAULT, DN_NIGHT_DEFAULT = 9, 6
DN_STARTS = {8, 12, 17, 22}      -- the options page's starting hours (5: random, 6: as the map; unset: noon)
DN_NIGHT_FORCE = nil             -- a night level set by a test copy (else the host's option savegame.mod.dark)

-- every property this mod sets: read from the map at the start, put back when standing down
local PROPS = {"skybox", "skyboxbrightness", "skyboxtint", "sunBrightness", "sunColorTint", "sunDir", "sunFogScale",
	"sunGlare", "fogColor", "fogParams", "constant", "nightlight", "ambience", "rain", "wetness", "puddleamount"}

local kept = {}          -- the map's own values {name = {values}}
local sent = {}          -- what was set last {name = {values}}
local hour = 8
local day = 1
local applyT = 0
local publishT = 0
local wasNight = false
local standing = false   -- stood down (daynight.off): the map's environment is back

local function same(a, b)
	if not a or #a ~= #b then return false end
	for i = 1, #b do
		local x, y = a[i], b[i]
		if type(x) == "number" and type(y) == "number" then
			if math.abs(x - y) > 0.00001 + 0.004 * math.abs(y) then return false end      -- (the night's values are tiny)
		elseif x ~= y then
			return false
		end
	end
	return true
end

-- set a property only when it changed enough to see (in multiplayer every set goes to every client)
local function put(name, ...)
	local v = {...}
	if same(sent[name], v) then return end
	sent[name] = v
	SetEnvironmentProperty(name, ...)
end

local function isOff()
	if GetBool("daynight.off") then return true end
	for _, k in ipairs(ListKeys("daynight.off")) do
		if GetBool("daynight.off." .. k) then return true end
	end
	return false
end

-- seconds the daylight (dawn to dusk) and the night (dusk to dawn) take: the host's two options; daynight.cycle
-- (seconds for both together) keeps their proportion
function DayNight.spans()
	local d = (DN_DAY_MIN[GetInt("savegame.mod.daymin")] or DN_DAY_DEFAULT) * 60
	local n = (DN_NIGHT_MIN[GetInt("savegame.mod.nightmin")] or DN_NIGHT_DEFAULT) * 60
	local s = GetFloat("daynight.cycle")
	if s > 0 then
		s = math.max(s, 20)
		d, n = s * d / (d + n), s * n / (d + n)
	end
	return d, n
end

function DayNight.cycleSeconds()
	local d, n = DayNight.spans()
	return d + n
end

-- hours per second at this hour: the night's hours (dusk to dawn) pass at their own pace
function DayNight.rateAt(h)
	local d, n = DayNight.spans()
	if dnIsDaySky(h) then return (DN_DUSK - DN_DAWN) / d end
	return (24 - (DN_DUSK - DN_DAWN)) / n
end

local function startHour()
	local i = GetInt("savegame.mod.start")
	if i == 5 then return math.random() * 24 end
	if DN_STARTS[i] then return DN_STARTS[i] end
	if i == 6 then
		-- "as the map": a map that is a night map starts at night, any other in the morning
		local lamps = kept.nightlight and kept.nightlight[1]
		if lamps == true or lamps == 1 then return 22 end
		return 8
	end
	return 12                                  -- (the default: midday - the user, 2026-11-11)
end

function DayNight.hour() return hour end

function DayNight.apply()
	local k = dnSkyAt(hour)
	local daySky = dnIsDaySky(hour)
	dnNightLight(k, DN_NIGHT_FORCE or GetInt("savegame.mod.dark"))       -- (how dark the night is: the host's option)
	local picture, sound = Weather.look(k, daySky)           -- (the weather on top of the hour: weather.lua)
	put("skybox", daySky and (picture or DN_DAY_SKY) or DN_NIGHT_SKY)
	put("skyboxbrightness", k.sky * (daySky and 1 or DN_NIGHT_SKY_SCALE))
	put("skyboxtint", k.tint[1], k.tint[2], k.tint[3])
	put("sunBrightness", k.sun)
	put("sunColorTint", k.suntint[1], k.suntint[2], k.suntint[3])
	local d = dnLightDir(hour)
	put("sunDir", d[1], d[2], d[3])
	put("sunFogScale", k.sfs)
	put("sunGlare", k.glare)
	put("fogColor", k.fog[1], k.fog[2], k.fog[3])
	put("fogParams", k.fp[1], k.fp[2], k.fp[3], k.fp[4])
	local c = kept.constant
	if c and #c == 3 then put("constant", c[1] * k.const, c[2] * k.const, c[3] * k.const) end
	put("nightlight", dnLampsOn(hour))
	if sound then
		put("ambience", sound)
	elseif daySky then
		if kept.ambience then put("ambience", unpack(kept.ambience)) end
	else
		put("ambience", DN_NIGHT_SOUND)
	end
	-- rain and wet ground: never less than the map's own
	local function own(name) return (kept[name] and type(kept[name][1]) == "number") and kept[name][1] or 0 end
	put("rain", math.max(own("rain"), Weather.level("rain")))
	put("wetness", math.max(own("wetness"), 0.7 * Weather.wet()))
	put("puddleamount", math.max(own("puddleamount"), 0.6 * Weather.wet()))
end

local function restore()
	for _, name in ipairs(PROPS) do
		if kept[name] and #kept[name] > 0 then SetEnvironmentProperty(name, unpack(kept[name])) end
	end
	sent = {}
end

local function publish()
	SetBool("daynight.present", true, true)
	SetFloat("daynight.time", hour, true)
	SetFloat("daynight.rate", GetBool("daynight.freeze") and 0 or DayNight.rateAt(hour), true)
	SetInt("daynight.day", day, true)
	SetBool("daynight.night", not dnIsDaySky(hour), true)
	SetFloat("daynight.light", standing and 1 or dnDaylight(hour), true)
	SetBool("daynight.active", not standing, true)
	Weather.publish()
end

function DayNight.serverInit()
	for _, name in ipairs(PROPS) do kept[name] = {GetEnvironmentProperty(name)} end
	sent = {}
	hour = startHour()
	day = 1
	applyT, publishT = 0, 0
	standing = false
	ClearKey("daynight.set")
	Weather.init()
	publish()
end

function DayNight.serverTick(dt)
	if HasKey("daynight.set.time") then
		hour = dnWrapHour(GetFloat("daynight.set.time"))
		ClearKey("daynight.set.time")
		applyT = 0
	end
	if not GetBool("daynight.freeze") then
		hour = hour + dt * DayNight.rateAt(hour)
		if hour >= 24 then hour = hour - 24; day = day + 1 end
	end
	if Weather.tick(dt) then applyT = 0 end              -- (a flash of lightning shows at once)
	publishT = publishT - dt
	local night = not dnIsDaySky(hour)                -- (the flag flips at once: nobody reads a stale night)
	if publishT <= 0 or night ~= wasNight then publishT = DN_PUBLISH_EVERY; wasNight = night; publish() end

	if isOff() then
		if not standing then standing = true; restore(); publish() end
		return
	end
	if standing then standing = false; publish() end
	applyT = applyT - dt
	if applyT <= 0 then
		applyT = DN_APPLY_EVERY
		DayNight.apply()
	end
end

function DayNight.serverDestroy()
	SetBool("daynight.present", false, true)
end

-- ---------------------------------------------------------------- client: the moon's disc and the stars
-- The sun needs no disc: the engine draws its glare where sunDir points. The moon and the stars are sprites far
-- along their directions, drawn on each machine (the game's sky pictures have no stars). The client's own clock runs
-- on between the host's once-a-second daynight.time so they glide. The stars turn with the moon, about the axis its
-- arc turns on.

DN_DISC_DIST = 400       -- metres from the camera (at 900 a sprite was not drawn: beyond the far plane)
DN_MOON_SIZE = 0.075     -- the picture's width as a share of the distance (the disc is 0.62 of the picture)
DN_MOON_BRIGHT = 0.3     -- the picture's brightness (at 1 the night's exposure burns it to a white blob)
DN_STARS = 400           -- over the whole sphere: about half are above the horizon at a time
DN_STAR_SIZE = 0.0045    -- a middling star's picture as a share of the distance
DN_STAR_BRIGHT = 0.8
DN_SKY_OFF = false       -- true: no moon, no stars drawn

local moonSprite, starSprite
local thunderSounds = {}
local thunderSeen = nil      -- the host's counter (daynight.thunder) last heard
local thunderDue = nil       -- {seconds left, volume, which sound}
local stars = nil        -- {{x, y, z, size, r, g, b, -, alpha}} in the frame that turns
local clientHour = nil
local seenTime = nil

-- the same stars on every machine: a small generator of our own, not math.random
local function makeStars()
	local seed = 20261111
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	stars = {}
	for i = 1, DN_STARS do
		local z = rnd() * 2 - 1
		local a = rnd() * 2 * math.pi
		local r = math.sqrt(1 - z * z)
		local mag = rnd() ^ 3                    -- (most stars faint, a few bright)
		local tone = rnd()
		stars[i] = {r * math.cos(a), z, r * math.sin(a), 1.0 + 1.6 * mag, 0.75 + 0.25 * tone, 0.85, 1.0 - 0.25 * tone,
			rnd() * 6.283, 0.5 + 0.5 * mag}
	end
end

function DayNight.clientInit()
	moonSprite = LoadSprite("MOD/images/moon.png")
	starSprite = LoadSprite("MOD/images/star.png")
	makeStars()
	for i = 0, 6 do thunderSounds[i + 1] = LoadSound("thunder" .. i .. ".ogg") end      -- (the game's own)
	clientHour, seenTime, thunderSeen, thunderDue = nil, nil, nil, nil
end

function DayNight.clientHour() return clientHour end

-- The turned directions are kept and only worked out again every DN_STAR_TURN_EVERY seconds (the sky turns slowly):
-- per frame a star costs one DrawSprite and a little arithmetic.
DN_STAR_TURN_EVERY = 0.5
local turned = nil       -- {{x, y, z, alpha, size}} of the stars above the horizon
local turnedT = -1

local function turnStars(moon)
	-- turn the star frame about the arc's axis n = (0, -sin tilt, cos tilt) by the moon's angle (Rodrigues)
	local tilt = math.rad(DN_TILT)
	local ny, nz = -math.sin(tilt), math.cos(tilt)
	local ang = dnWrapHour(clientHour - 18) / 12 * math.pi
	local c, s = math.cos(ang), math.sin(ang)
	turned = {}
	for i = 1, #stars do
		local st = stars[i]
		local x, y, z = st[1], st[2], st[3]
		local dot = y * ny + z * nz
		-- n x v = (ny * z - nz * y, nz * x, -ny * x)
		local rx = x * c + (ny * z - nz * y) * s
		local ry = y * c + (nz * x) * s + ny * dot * (1 - c)
		local rz = z * c + (-ny * x) * s + nz * dot * (1 - c)
		if ry > 0.03 and rx * moon[1] + ry * moon[2] + rz * moon[3] < 0.9985 then      -- (none in front of the moon)
			turned[#turned + 1] = {rx * DN_DISC_DIST, ry * DN_DISC_DIST, rz * DN_DISC_DIST,
				st[9] * math.min(1, (ry - 0.03) / 0.15), DN_DISC_DIST * DN_STAR_SIZE * st[4], st[5], st[6], st[7]}
		end
	end
end

local function drawStars(cam, night, t, moon)
	if not turned or math.abs(t - turnedT) >= DN_STAR_TURN_EVERY then
		turnedT = t
		turnStars(moon)
	end
	local px, py, pz = cam.pos[1], cam.pos[2], cam.pos[3]
	local b = DN_STAR_BRIGHT
	local rot = cam.rot
	for i = 1, #turned do
		local st = turned[i]
		DrawSprite(starSprite, Transform(Vec(px + st[1], py + st[2], pz + st[3]), rot), st[5], st[5],
			st[6] * b, st[7] * b, st[8] * b, night * st[4], true, true, false)
	end
end

-- thunder: the host counts the flashes; each machine plays the rumble a moment after (the same on every machine:
-- the delay and the sound come from the counter)
local function thunder(dt)
	local n = GetInt("daynight.thunder")
	if thunderSeen == nil then thunderSeen = n end
	if n ~= thunderSeen then
		thunderSeen = n
		thunderDue = {0.4 + (n * 7 % 10) * 0.22, 0.6 + (n * 3 % 5) * 0.1, n % 7 + 1}
	end
	if thunderDue then
		thunderDue[1] = thunderDue[1] - dt
		if thunderDue[1] <= 0 then
			PlaySound(thunderSounds[thunderDue[3]], GetCameraTransform().pos, thunderDue[2], false)
			thunderDue = nil
		end
	end
end

function DayNight.clientTick(dt)
	if not GetBool("daynight.present") then return end
	if GetBool("daynight.active") then thunder(dt) end
	local t = GetFloat("daynight.time")
	if t ~= seenTime then
		seenTime = t
		clientHour = t
	elseif clientHour then
		clientHour = dnWrapHour(clientHour + dt * GetFloat("daynight.rate"))
	end
	if not clientHour or not GetBool("daynight.active") then return end       -- (stood down: the map's own sky)
	if DN_SKY_OFF then return end                                              -- (benchmarks: tools/autotest/bench.lua)
	if dnIsDaySky(clientHour) then return end
	local night = dnSkyAt(clientHour).sun / DN_MOON          -- (0 at the twilight swap, 1 in full night)
	if night > 1 then night = 1 end
	-- (clouds and fog hide the stars, and all but a glow of the moon)
	local cloud = math.max(GetFloat("daynight.cloud"), GetFloat("daynight.fog"))
	local starry = night * (1 - math.min(1, cloud * 1.5))
	if night <= 0 then return end
	local cam = GetCameraTransform()
	local d = dnArcDir(clientHour)
	if starry > 0.02 and not GetBool("savegame.mod.nostars") then drawStars(cam, starry, GetTime(), d) end      -- (each player's own option)
	local a = dnDiscAlpha(clientHour) * (1 - 0.9 * math.min(1, cloud * 1.2))
	if a > 0.01 then
		local at = VecAdd(cam.pos, VecScale(d, DN_DISC_DIST))
		local s = DN_DISC_DIST * DN_MOON_SIZE
		local b = DN_MOON_BRIGHT
		DrawSprite(moonSprite, Transform(at, QuatLookAt(at, cam.pos)), s, s, b, b, b, a, true, false, false)
	end
end
