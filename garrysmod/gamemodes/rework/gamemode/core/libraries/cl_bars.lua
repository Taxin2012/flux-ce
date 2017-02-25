--[[
	Rework © 2016-2017 TeslaCloud Studios
	Do not share or re-distribute before
	the framework is publicly released.
--]]

library.New("bars", rw)

local stored = rw.bars.stored or {}
rw.bars.stored = stored

local sorted = rw.bars.sorted or {}
rw.bars.sorted = sorted

-- Some fail-safety variables.
rw.bars.defaultX = 8
rw.bars.defaultY = 8
rw.bars.defaultW = ScrW() / 4
rw.bars.defaultH = 14
rw.bars.defaultSpacing = 4
rw.bars.drawing = rw.bars.drawing or 0; -- Amount of bars currently being drawn.

function rw.bars:Register(uniqueID, data, force)
	if (!data) then return end

	force = rw.Devmode or force

	if (stored[uniqueID] and !force) then
		return stored[uniqueID]
	end

	stored[uniqueID] = {
		uniqueID = uniqueID,
		text = data.text or "",
		color = data.color or Color(200, 90, 90),
		maxValue = data.maxValue or 100,
		hinderColor = data.hinderColor or Color(255, 0, 0),
		hinderText = data.hinderText or "",
		display = data.display or 100,
		minDisplay = data.minDisplay or 0,
		hinderDisplay = data.hinderDisplay or false,
		value = data.value or 0,
		hinderValue = data.hinderValue or 0,
		x = data.x or self.defaultX,
		y = data.y or self.defaultY,
		width = data.width or self.defaultW,
		height = data.height or self.defaultH,
		cornerRadius = data.cornerRadius or 4,
		priority = data.priority or table.Count(stored),
		type = data.type or BAR_TOP,
		font = data.font or "bar_text",
		spacing = data.spacing or self.defaultSpacing,
		textOffset = data.textOffset or 0,
		callback = data.callback
	}

	hook.Run("OnBarRegistered", stored[uniqueID], uniqueID, force)

	return stored[uniqueID]
end

function rw.bars:Get(uniqueID)
	if (stored[uniqueID]) then
		return stored[uniqueID]
	end

	return false
end

function rw.bars:SetValue(uniqueID, newValue)
	local bar = self:Get(uniqueID)

	if (bar) then
		theme.Call("PreBarValueSet", bar, bar.value, newValue)

		if (bar.value != newValue) then
			if (bar.hinderDisplay and bar.hinderValue) then
				bar.value = math.Clamp(newValue, 0, bar.maxValue - bar.hinderValue + 2)
			end

			bar.interpolated = util.CubicEaseInOutTable(150, bar.value, newValue)
			bar.value = math.Clamp(newValue, 0, bar.maxValue)
		end
	end
end

function rw.bars:HinderValue(uniqueID, newValue)
	local bar = self:Get(uniqueID)

	if (bar) then
		theme.Call("PreBarHinderValueSet", bar, bar.hinderValue, newValue)

		if (bar.value != newValue) then
			bar.hinderValue = math.Clamp(newValue, 0, bar.maxValue)
		end
	end
end

function rw.bars:Prioritize()
	sorted = {}

	for k, v in pairs(stored) do
		if (!hook.Run("ShouldDrawBar", v)) then
			continue
		end

		hook.Run("PreBarPrioritized", v)

		sorted[v.priority] = sorted[v.priority] or {}

		if (v.type == BAR_TOP) then
			table.insert(sorted[v.priority], v.uniqueID)
		end
	end

	return sorted
end

function rw.bars:Position()
	self:Prioritize()

	local lastY = self.defaultY
	local lastX = self.defaultX

	for priority, ids in pairs(sorted) do
		for k, v in pairs(ids) do
			local bar = self:Get(v)

			if (bar and bar.type == BAR_TOP) then
				local offX, offY = hook.Run("AdjustBarPos", bar)
				offX = offX or 0
				offY = offY or 0

				bar.y = lastY + offY
				bar.x = bar.x + offX
				lastY = lastY + bar.height + bar.spacing
			end
		end
	end

end

function rw.bars:Draw(uniqueID)
	local barInfo = self:Get(uniqueID)

	if (barInfo) then
		hook.Run("PreDrawBar", barInfo)
		theme.Call("PreDrawBar", barInfo)

		if (!hook.Run("ShouldDrawBar", barInfo)) then
			return
		end

		theme.Call("DrawBarBackground", barInfo)

		if (hook.Run("ShouldFillBar", barInfo) or barInfo.value != 0) then
			theme.Call("DrawBarFill", barInfo)
		end

		if (barInfo.hinderDisplay and barInfo.hinderDisplay <= barInfo.hinderValue) then
			theme.Call("DrawBarHindrance", barInfo)
		end

		if (rw.settings:GetBool("DrawBarText")) then
			theme.Call("DrawBarTexts", barInfo)
		end

		hook.Run("PostDrawBar", barInfo)
		theme.Call("PostDrawBar", barInfo)
	end
end

function rw.bars:DrawTopBars()
	for priority, ids in pairs(sorted) do
		for k, v in ipairs(ids) do
			self:Draw(v)
		end
	end
end

function rw.bars:Adjust(uniqueID, data)
	local bar = self:Get(uniqueID)

	if (bar) then
		table.Merge(bar, data)
	end
end

do
	local rwBars = {}

	function rwBars:LazyTick()
		if (IsValid(rw.client)) then
			rw.bars:Position()

			for k, v in pairs(stored) do
				if (v.callback) then
					rw.bars:SetValue(v.uniqueID, v.callback(stored[k]))
				end

				hook.Run("AdjustBarInfo", k, stored[k])
			end
		end
	end

	function rwBars:PreDrawBar(bar)
		bar.curI = bar.curI or 1

		if (bar.interpolated == nil) then
			bar.fillWidth = bar.width * (bar.value / bar.maxValue)
		else
			if (bar.curI > 150) then
				bar.interpolated = nil
				bar.curI = 1
			else
				bar.fillWidth = bar.width * (bar.interpolated[math.Round(bar.curI)] / bar.maxValue)
				bar.curI = bar.curI + 1
			end
		end

		bar.text = string.utf8upper(rw.lang:TranslateText(bar.text))
		bar.hinderText = string.utf8upper(rw.lang:TranslateText(bar.hinderText))
	end

	function rwBars:ShouldDrawBar(bar)
		if (bar.display < bar.value or bar.minDisplay >= bar.value) then
			return false
		end

		return true
	end

	plugin.AddHooks("RWBarHooks", rwBars)

	rw.bars:Register("health", {
		text = "#BarText_Health",
		color = Color(200, 40, 40),
		maxValue = 100,
		callback = function(bar)
			return rw.client:Health()
		end
	})

	rw.bars:Register("armor", {
		text = "#BarText_Armor",
		color = Color(80, 80, 220),
		maxValue = 100,
		callback = function(bar)
			return rw.client:Armor()
		end
	})

	rw.bars:Register("respawn", {
		text = "#BarText_Respawn",
		color = Color(50, 200, 50),
		maxValue = 100,
		x = ScrW() / 2 - rw.bars.defaultW / 2,
		y = ScrH() / 2 - 8,
		textOffset = 1,
		height = 16,
		type = BAR_MANUAL
	})
end