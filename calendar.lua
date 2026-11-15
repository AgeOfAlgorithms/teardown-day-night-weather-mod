-- The calendar: a date that turns over at midnight with the clock, and goes on from session to session on the same
-- map (the host's savegame, one date per level). Asked for by the Villagers mod (2026-11-14), whose AI stamps what it
-- hears with the date. Gregorian, with the northern seasons. Mods can't read the real-world date (no `os`), so a
-- map's calendar starts on the host's chosen date (options) or on one a map or mod sets (daynight.set.date).
--
-- Registry, read on the host:   daynight.set.date      "YYYY-MM-DD": jump to this date; taken once
-- published (synced):           daynight.date ("Tuesday, 14 March"), daynight.weekday (1 Monday - 7 Sunday),
--                               daynight.weekdayname, daynight.dayofmonth, daynight.month (1-12),
--                               daynight.monthname, daynight.year, daynight.season (spring / summer / autumn / winter)

Calendar = {}

CAL_WEEKDAYS = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
CAL_MONTHS = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December"}
CAL_SEASONS = {"winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn",
	"autumn", "winter"}
CAL_YEAR = 1                      -- a new map's year (its own story's year 1, not ours)
-- the options page's first dates: spring, summer, autumn, winter (5: random; unset: spring)
CAL_STARTS = {{3, 1}, {6, 1}, {9, 1}, {12, 1}}
CAL_SAVE_EVERY = 10               -- seconds between two saves of the date and the hour

local serial = 0                  -- days since 1970-01-01 (negative before)
local saveT = 0
local key = nil                   -- savegame.mod.cal.<level>

local function floor(x) return math.floor(x) end

-- days since 1970-01-01 <-> year, month, day (H. Hinnant's civil-calendar algorithms; proleptic Gregorian)
function Calendar.serialOf(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function Calendar.dateOf(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	local y = yoe + era * 400
	if m <= 2 then y = y + 1 end
	return y, m, d
end

-- 1 Monday ... 7 Sunday (1970-01-01 was a Thursday)
function Calendar.weekdayOf(z) return (z + 3) % 7 + 1 end

function Calendar.serial() return serial end

-- the level's id AND its file: a mod's map has the id "main" (from its main.xml; seen in the savegame, 2026-11-14), so
-- the id alone gave every mod map one shared date
local function levelKey()
	local id = GetString("game.levelid") .. "_" .. GetString("game.levelpath")
	if id == "_" then id = "default" end
	id = string.gsub(id, "[^%w]", "_")
	return "savegame.mod.cal." .. id
end

local function firstDate()
	local i = GetInt("savegame.mod.calstart")
	if i == 5 then
		local y = CAL_YEAR
		return Calendar.serialOf(y, 1, 1) + floor(Weather.random() * 365)
	end
	local md = CAL_STARTS[i] or CAL_STARTS[1]
	return Calendar.serialOf(CAL_YEAR, md[1], md[2])
end

local function save(hour)
	SetInt(key .. ".day", serial)
	SetFloat(key .. ".hour", hour)
	SetBool(key .. ".set", true)
end

-- the session's first date: where this map's calendar stopped (the next day when the clock would otherwise run
-- back: the last session got past the hour this one starts at), or the first date for a map never played
function Calendar.init(hour)
	key = levelKey()
	if GetBool(key .. ".set") then
		serial = GetInt(key .. ".day")
		if GetFloat(key .. ".hour") > hour then serial = serial + 1 end
	else
		serial = firstDate()
	end
	saveT = 0
	save(hour)
end

function Calendar.midnight() serial = serial + 1 end

function Calendar.tick(dt, hour)
	if HasKey("daynight.set.date") then
		local y, m, d = string.match(GetString("daynight.set.date"), "^(%-?%d+)%-(%d+)%-(%d+)$")
		ClearKey("daynight.set.date")
		y, m, d = tonumber(y), tonumber(m), tonumber(d)
		if y and m and d and m >= 1 and m <= 12 and d >= 1 and d <= 31 then serial = Calendar.serialOf(y, m, d) end
		saveT = 0
	end
	saveT = saveT - dt
	if saveT <= 0 then saveT = CAL_SAVE_EVERY; save(hour) end
end

function Calendar.destroy(hour) if key then save(hour) end end

function Calendar.name(z)
	local y, m, d = Calendar.dateOf(z)
	return CAL_WEEKDAYS[Calendar.weekdayOf(z)] .. ", " .. d .. " " .. CAL_MONTHS[m]
end

function Calendar.publish()
	local y, m, d = Calendar.dateOf(serial)
	local w = Calendar.weekdayOf(serial)
	SetString("daynight.date", Calendar.name(serial), true)
	SetInt("daynight.weekday", w, true)
	SetString("daynight.weekdayname", CAL_WEEKDAYS[w], true)
	SetInt("daynight.dayofmonth", d, true)
	SetInt("daynight.month", m, true)
	SetString("daynight.monthname", CAL_MONTHS[m], true)
	SetInt("daynight.year", y, true)
	SetString("daynight.season", CAL_SEASONS[m], true)
end
