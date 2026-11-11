-- Day & Night's options (Mod Manager). In multiplayer the host's lengths and start count; the stars are each
-- player's own (they are drawn on that player's machine).

local function pick(label, y, items, cur, set, w)
	w = w or 150
	UiPush()
	UiTranslate(0, y)
	UiFont("regular.ttf", 28)
	UiColor(1, 1, 1)
	UiText(label)
	UiTranslate(0, 50)
	UiFont("bold.ttf", 30)
	for i, name in ipairs(items) do
		UiPush()
		UiTranslate((i - (#items + 1) / 2) * (w + 20), 0)
		if i == cur then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(name, w, 46) then set(i) end
		UiPop()
	end
	UiPop()
end

function draw()
	local d = GetInt("savegame.mod.daymin")
	if d < 1 or d > 6 then d = 3 end
	local n = GetInt("savegame.mod.nightmin")
	if n < 1 or n > 6 then n = 3 end
	local s = GetInt("savegame.mod.start")
	if s < 0 or s > 5 then s = 0 end
	UiTranslate(UiCenter(), 80)
	UiAlign("center middle")
	UiFont("bold.ttf", 48)
	UiText("Day & Night & Weather Cycle")
	pick("Daylight lasts", 80, {"2 min", "5 min", "9 min", "15 min", "30 min", "45 min"}, d,
		function(i) SetInt("savegame.mod.daymin", i) end, 130)
	pick("Night lasts", 200, {"1 min", "3 min", "6 min", "10 min", "20 min", "30 min"}, n,
		function(i) SetInt("savegame.mod.nightmin", i) end, 130)
	local wx = GetInt("savegame.mod.weather")
	if wx < 1 or wx > 4 then wx = 2 end
	pick("Weather (clouds, rain, storms, fog)", 320, {"Off", "Rare", "Sometimes", "Often"}, wx,
		function(i) SetInt("savegame.mod.weather", i) end)
	pick("A map starts", 440, {"As the map", "Morning", "Noon", "Evening", "Night", "Random"}, s + 1,
		function(i) SetInt("savegame.mod.start", i - 1) end, 170)
	pick("Stars at night (your own screen)", 560, {"Shown", "Hidden"}, GetBool("savegame.mod.nostars") and 2 or 1,
		function(i) SetBool("savegame.mod.nostars", i == 2) end)
	UiTranslate(0, 690)
	UiFont("regular.ttf", 22)
	UiColor(0.7, 0.7, 0.7)
	UiText("\"As the map\": a night map starts at night, any other in the morning.")
	UiTranslate(0, 60)
	UiColor(1, 1, 1)
	UiFont("bold.ttf", 32)
	if UiTextButton("Close", 200, 50) then Menu() end
end
