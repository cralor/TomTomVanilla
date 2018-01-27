----------------------------------------------------------------------------
--  TomTom: A navigational assistant for World of Warcraft
--  CrazyTaxi: A crazy-taxi style arrow used for waypoint navigation.
--  concept taken from MapNotes2 (Thanks to Mery for the idea, along
--  with the artwork.)
----------------------------------------------------------------------------
TomTom = {}
TomTom = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0", "AceConsole-2.0", "AceDebug-2.0", "AceDB-2.0")

local twopi = math.pi * 2

TomTom.active_waypoint = nil
TomTom.active_point = nil -- {c, z, x, y}
TomTom.arrive_distance = nil -- num of yards to show down icon
TomTom.clear_distance = nil -- num of yards to remove arrow
TomTom.showDownArrow = nil
TomTom.point_title = nil
TomTom.isHide = false
TomTom.wayframe = nil
TomTom.waypoints = {}
-- List of zones Astrolabe doesn't know about.
-- the left part is your name without any extra chars (like space, ' or -) in lower case
-- the right part is the Astrolabe zone name. Look it up from Interface/Addons/TomTom/Astrolabe/Astrolabe.lua
-- at the bottom of the file where "WorldMapSize = {" is around the line 621
TomTom.extraZones = {
	thehinterlands = 'Hinterlands',
	tarrenmill = 'Hilsbrad',
	hillsbrad = 'Hilsbrad',
	hillsbradfoothills = 'Hilsbrad',
	alteracmountains = 'Alterac',
	silverpineforest = 'Silverpine',
	trisfalglades = 'Tirisfal',
	tirisfalglades = 'Tirisfal',
	theundercity = 'Undercity',
	stranglethornvale = 'Stranglethorn',
	redridgemountains = 'Redridge',
	elwynnforest = 'Elwynn',
	arathihighlands = 'Arathi',
	thebarrens = 'Barrens',
	darnassus = 'Darnassis',
	dustwallowmarsh = 'Dustwallow',
	duskwallowmarsh = 'Dustwallow',
	orgrimmar = 'Ogrimmar',
	stonetalon = 'StonetalonMountains',
	swampofsorrow='SwampOfSorrows',
}

TomTom.defaults = {
	profile = {
        persistence = {
            cleardistance = 10,
            savewaypoints = false,
        },
        arrow = {
        	autoqueue = true,
        	arrival = 30,
        	locked = true,
        	location = nil,
        	enablePing = true,
        	menu = true,
        	continueclosest = false
        },
        general = {
        	announce = false,
        	confirmremoveall = true,
        	corpsewaypoint = true
        },
        worldmap = {
        	create_modifier = "C",
        	enable = true,
        	tooltip = true,
        	menu = true
        },
        minimap = {
        	enable = true,
        	tooltip = true,
        	menu = true
        }
	}
}

function TomTom:log(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg) -- alias for convenience
end

function TomTom:Modulo(val, by)
	return val - math.floor(val / by) * by
end

function TomTom:modf(number)
	local fractional = self:Modulo(number, 1)
	local integral = number - fractional
	return integral, fractional
end

function TomTom:GetPlayerFacing()
	local p = Minimap
	local m = ({p:GetChildren()})[9]
	return m:GetFacing()
end

function TomTom:ColorGradient(perc, tablee)
	local num = table.getn(tablee)
	local hexes = tablee[1] == "string"
	if perc == 1 then
		return tablee[num-2], tablee[num-1], tablee[num]
	end
	num = num / 3
	local segment, relperc = self:modf(perc*(num-1))
	local r1, g1, b1, r2, g2, b2
	r1, g1, b1 = tablee[(segment*3)+1], tablee[(segment*3)+2], tablee[(segment*3)+3]
	r2, g2, b2 = tablee[(segment*3)+4], tablee[(segment*3)+5], tablee[(segment*3)+6]
	if not r1 then return end
	if not r2 or not g2 or not b2 then
		return r1, g1, b1
	else
		return r1 + (r2-r1)*relperc,
			g1 + (g2-g1)*relperc,
			b1 + (b2-b1)*relperc
	end
end

function TomTom:WayFrame_OnClick()
	if arg1 == "RightButton" and IsShiftKeyDown() then
		TomTom:GoToNextWayPoint(TomTom.active_waypoint);
	elseif arg1 == "RightButton" then
	    if TomTom.db.profile.arrow.menu then
	        TomTom:InitializeDropdown(TomTom.active_waypoint, true)
	        ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
	    end
	end
end

function TomTom:OnInitialize()
	self:CreateFrames();
	self:RegisterDB("TomTomDB")
	self:RegisterDefaults("profile", self.defaults.profile)

    self:OnProfileEnable()
    self:InitConsole()
end

function TomTom:OnEventsUpdate(self)
	if self.profile.general.corpsewaypoint and UnitIsDeadOrGhost("player") and not self.deadWayPoint then
		local deadx, deady = GetCorpseMapPosition();
		if deadx and deady and deadx ~= 0 and deady ~= 0 then
			local cont,zoneid = self:GetCurrentPlayerPosition()
			self.deadWayPoint = self:SetCrazyArrow({c = cont, z = zoneid, x = deadx, y = deady}, 20, "My possibly dead corpse", true)
		end
	elseif not UnitIsDeadOrGhost("player") and self.deadWayPoint then
		if self.active_waypoint == self.deadWayPoint then
			self:GoToNextWayPoint(self.active_waypoint)
		else
			self:RemoveWaypoint(self.deadWayPoint)
		end
		self.deadWayPoint = nil
	end
end

function TomTom:OnEvents()
	if (event == "PLAYER_ENTERING_WORLD") then
		for k, w in pairs(TomTom.waypoints) do
    		TomTom:SetWaypoint(w, w.callbacks, w.minimap, w.world)
		end
	elseif (event == "PLAYER_LEAVING_WORLD") then
		for k, w in pairs(TomTom.waypoints) do
			TomTom:ClearWaypoint(w)
		end
	end
end

function TomTom:CreateFrames()
	self.eventsFrame = CreateFrame("Frame", nil, UIParent)
	self.eventsFrame:SetScript("OnUpdate", function() self:OnEventsUpdate(self) end)
	self.eventsFrame:RegisterEvent("PLAYER_LEAVING_WORLD");
	self.eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	self.eventsFrame:SetScript("OnEvent", self.OnEvents);

	self.dropdown = CreateFrame("Frame", "TomTomDropdown", nil, "UIDropDownMenuTemplate")

	local wayframe = CreateFrame("Button", "TomTomCrazyArrow", UIParent)
	self.wayframe = wayframe
	wayframe:SetHeight(42)
	wayframe:SetWidth(56)
	wayframe:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	wayframe:EnableMouse(true)
	wayframe:SetMovable(true)
	wayframe:Hide()
	wayframe.count = 0
	wayframe.last_distance = 0
	wayframe.tta_throttle = 0
	wayframe.speed = 0
	wayframe.speed_count = 0

	-- Frame used to control the scaling of the title and friends
	local titleframe = CreateFrame("Frame", nil, wayframe)
	wayframe.titleframe = titleframe
	wayframe.title = titleframe:CreateFontString("OVERLAY", nil, "GameFontHighlightSmall")
	wayframe.status = titleframe:CreateFontString("OVERLAY", nil, "GameFontNormalSmall")
	wayframe.tta = titleframe:CreateFontString("OVERLAY", nil, "GameFontNormalSmall")
	wayframe.title:SetPoint("TOP", wayframe, "BOTTOM", 0, 0)
	wayframe.status:SetPoint("TOP", wayframe.title, "BOTTOM", 0, 0)
	wayframe.tta:SetPoint("TOP", wayframe.status, "BOTTOM", 0, 0)

	wayframe:SetScript("OnDragStart", self.OnDragStart)
	wayframe:SetScript("OnDragStop", self.OnDragStop)
	wayframe:RegisterForDrag("LeftButton")
	wayframe:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	wayframe:SetScript("OnEvent", self.OnEvent)
	wayframe.arrow = wayframe:CreateTexture("OVERLAY")
	wayframe.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow")
	wayframe.arrow:SetAllPoints()

	wayframe:SetScript("OnUpdate", self.OnUpdate)
	wayframe:RegisterForClicks("RightButtonUp")
	wayframe:SetScript("OnClick", self.WayFrame_OnClick)

	wayframe:RegisterEvent("ADDON_LOADED")
	wayframe:SetScript("OnEvent", function(self, event, arg1, ...)
		local feed_crazy = CreateFrame("Frame")
		local crazyFeedFrame = CreateFrame("Frame")
		local throttle = 1
		local counter = 0
		crazyFeedFrame:SetScript("OnUpdate", function(self, elapsed)
			elapsed = 1/GetFramerate()
			counter = counter + elapsed
			if counter < throttle then
				return
			end
			counter = 0
			local angle = TomTom:GetDirectionToIcon(TomTom.active_point)
			local player = TomTom:GetPlayerFacing()
			if not angle or not player then
				feed_crazy.iconCoords = TomTom.texcoords["1:1"]
				feed_crazy.iconR = 0.2
				feed_crazy.iconG = 1.0
				feed_crazy.iconB = 0.2
				feed_crazy.text = "No waypoint"
				return
			end
			angle = angle - player
			local perc = math.abs((math.pi - math.abs(angle)) / math.pi)
			local gr,gg,gb = 1, 1, 1
			local mr,mg,mb = 0.75, 0.75, 0.75
			local br,bg,bb = 0.5, 0.5, 0.5
			local tablee = {};
			table.insert(tablee, gr)
			table.insert(tablee, gg)
			table.insert(tablee, gb)
			table.insert(tablee, mr)
			table.insert(tablee, mg)
			table.insert(tablee, mb)
			table.insert(tablee, br)
			table.insert(tablee, bg)
			table.insert(tablee, bb)
			local r,g,b = TomTom:ColorGradient(perc, tablee)
			feed_crazy.iconR = r
			feed_crazy.iconG = g
			feed_crazy.iconB = b
			cell = TomTom:Modulo(floor(angle / twopi * 108 + 0.5) ,108)
			local column = TomTom:Modulo(cell, 9)
			local row = floor(cell / 9)
			local key = column .. ":" .. row
			feed_crazy.iconCoords = TomTom.texcoords[key]
			feed_crazy.text = TomTom.point_title or "Unknown waypoint"
		end)
	end)
end

function TomTom:OnDragStart(self, button)
	if not TomTom.profile.arrow.locked then
		this:StartMoving()
		this:SetClampedToScreen(true);
	end
end

function TomTom:OnDragStop(self, button)
	this:StopMovingOrSizing()
	local a, _, c, d, e = this:GetPoint()
	TomTom.profile.arrow.location = {a, "UIParent", c, d, e}
end

function TomTom:OnEvent(self, event, ...)
	if event == "ZONE_CHANGED_NEW_AREA" then
		this:Show()
	end
end

function TomTom:SetArrowWaypoint(waypoint)
	self.active_waypoint = waypoint
	self.active_point = {c = waypoint.continent, z = waypoint.zone, x = waypoint.x, y = waypoint.y}
	self.arrive_distance = waypoint.arrivaldistance
	self.clear_distance = waypoint.cleardistance
	self.point_title = waypoint.title
	self.wayframe.title:SetText(self.point_title or "Unknown waypoint")
	self.isHide = false
	if self.active_point and not self.isHide then
		self.wayframe:Show()
	else
		self.wayframe:Hide()
	end
end

function TomTom:SetCrazyArrow(point, dist, title, silent)
	return self:AddMFWaypoint(point.c, point.z, point.x, point.y, {
		title = title,
		crazy = true,
		persistent = false,
		silent = silent,
		cleardistance = dist,
		arrivaldistance = dist + 5
	})
end

function TomTom:ClearCrazyArrow()
	self.active_waypoint = nil
	self.active_point = nil
	self.wayframe:Hide()
end

-------------------------
-- Questie integration --
-------------------------
-- local originalQuestieArrowMethod = SetArrowObjective
-- SetArrowObjective = function(hash)
-- 	local existingWP = nil
-- 	for _, wp in TomTom.waypoints do
-- 		if wp.questieHash == hash then
-- 			existingWP = wp
-- 			break
-- 		end
-- 	end
-- 	if existingWP then
-- 		TomTom:GoToNextWayPoint(existingWP)
-- 		return existingWP
-- 	else
-- 		local objective = QuestieTrackedQuests[hash]["arrowPoint"]
-- 		if not objective then return end
-- 		local waypoint = TomTom:SetCrazyArrow(objective, 15, objective.title)
-- 		waypoint.questieHash = hash
-- 		return waypoint
-- 	end
--
-- end

function TomTom:OnUpdate()
	local self = this
	local elapsed = 1/GetFramerate()

	-- if TomTom.active_waypoint and TomTom.active_waypoint.questieHash then
	-- 	if not QuestieTrackedQuests[TomTom.active_waypoint.questieHash] then
	-- 		TomTom:GoToNextWayPoint(TomTom.active_waypoint)
	-- 	end
	-- end
	if not TomTom.active_point or TomTom.isHide then
		self:Hide()
		return
	end
	local dist,x,y = TomTom:GetDistanceToIcon(TomTom.active_point)
	-- The only time we cannot calculate the distance is when the waypoint
	-- is on another continent, or we are in an instance
	if not dist or IsInInstance() then
		if not TomTom.active_point.x and not TomTom.active_point.y then
			TomTom.active_point = nil
		end
		self:Hide()
		return
	end
	self.status:SetText(string.format("%d meters", dist))
	local cell
	-- got there already?
	if dist <= TomTom.clear_distance and not UnitOnTaxi("player") and TomTom.active_point.normalArrowShown then
		TomTom:GoToNextWayPoint(TomTom.active_waypoint)
	-- Showing the arrival arrow?
	elseif dist <= TomTom.arrive_distance then
	    if TomTom.profile.arrow.enablePing and TomTom.active_point.normalArrowShown and not TomTom.active_point.pinged then
	        PlaySoundFile("Interface\\AddOns\\TomTom\\Media\\ping.mp3")
	        TomTom.active_point.pinged = true
	    end
		if not self.showDownArrow then
			self.arrow:SetHeight(70)
			self.arrow:SetWidth(53)
			self.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow-UP")
			self.arrow:SetVertexColor(0, 1, 0)
			self.showDownArrow = true
		end
		self.count = self.count + 1
		if self.count >= 55 then
			self.count = 0
		end
		cell = self.count
		local column = TomTom:Modulo(cell, 9)
		local row = floor(cell / 9)
		local xstart = (column * 53) / 512
		local ystart = (row * 70) / 512
		local xend = ((column + 1) * 53) / 512
		local yend = ((row + 1) * 70) / 512
		self.arrow:SetTexCoord(xstart,xend,ystart,yend)
	-- Still moving there huh
	else
		TomTom.active_point.normalArrowShown = true
		if self.showDownArrow then
			self.arrow:SetHeight(56)
			self.arrow:SetWidth(42)
			self.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow")
			self.showDownArrow = false
		end
		local degtemp = TomTom:GetDirectionToIcon(TomTom.active_point);
		if degtemp < 0 then degtemp = degtemp + 360; end
		local angle = math.rad(degtemp)
		local player = TomTom:GetPlayerFacing()
		angle = angle - player
		local perc = 1-  math.abs(((math.pi - math.abs(angle)) / math.pi))
		local gr,gg,gb = 1, 1, 1
		local mr,mg,mb = 0.75, 0.75, 0.75
		local br,bg,bb = 0.5, 0.5, 0.5
		local tablee = {};
		table.insert(tablee, gr)
		table.insert(tablee, gg)
		table.insert(tablee, gb)
		table.insert(tablee, mr)
		table.insert(tablee, mg)
		table.insert(tablee, mb)
		table.insert(tablee, br)
		table.insert(tablee, bg)
		table.insert(tablee, bb)
		local r,g,b = TomTom:ColorGradient(perc,tablee)
		if not g then
			g = 0;
		end
		self.arrow:SetVertexColor(1-g,-1+g*2,0)
		cell = TomTom:Modulo(floor(angle / twopi * 108 + 0.5), 108);
		local column = TomTom:Modulo(cell, 9)
		local row = floor(cell / 9)
		local xstart = (column * 56) / 512
		local ystart = (row * 42) / 512
		local xend = ((column + 1) * 56) / 512
		local yend = ((row + 1) * 42) / 512
		self.arrow:SetTexCoord(xstart,xend,ystart,yend)
	end
	-- Calculate the TTA every second  (%01d:%02d)
	self.tta_throttle = self.tta_throttle + elapsed
	if self.tta_throttle >= 1.0 then
		-- Calculate the speed in yards per sec at which we're moving
		local current_speed = (self.last_distance - dist) / self.tta_throttle
		if self.last_distance == 0 then
			current_speed = 0
		end
		if self.speed_count < 2 then
			self.speed = (self.speed + current_speed) / 2
			self.speed_count = self.speed_count + 1
		else
			self.speed_count = 0
			self.speed = current_speed
		end
		if self.speed > 0 then
			local eta = math.abs(dist / self.speed)
			local text = string.format("%01d:%02d", eta / 60, TomTom:Modulo(eta, 60))
			self.tta:SetText(text)
		else
			self.tta:SetText("***")
		end
		self.last_distance = dist
		self.tta_throttle = 0
	end
end

function TomTom:ArrowHidden()
	self.isHide = true
end

function TomTom:ArrowShown()
	self.isHide = false
end

function TomTom:getCoords(column, row)
	local xstart = (column * 56) / 512
	local ystart = (row * 42) / 512
	local xend = ((column + 1) * 56) / 512
	local yend = ((row + 1) * 42) / 512
	return xstart, xend, ystart, yend
end

--this is where texcoords are extracted incorrectly (I think), leading the arrow to not point in the correct direction
TomTom.texcoords = setmetatable({}, {__index = function(t, k)
	-- this was k:match("(%d+):(%d+)") - so we need string.match, but that's not in Lua 5.0
	local fIndex, lIndex = string.find(k, "(%d+)")
	local col = string.sub(k, fIndex, lIndex)
	fIndex2, lIndex2 = string.find(k, ":(%d+)")
	local row = string.sub(k, fIndex2+1, lIndex2)
	col,row = tonumber(col), tonumber(row)
	local obj = {TomTom:getCoords(col, row)}
	rawset(t, k, obj)
	return obj
end})

-- calculations have to be redone - we are NOT actually working with Astrolabe "icons" here as TomTom did and want the arrow API
-- to be accessible to everyone
function TomTom:GetDirectionToIcon( point )
	if not point then return end
	local C,Z,X,Y = Astrolabe:GetCurrentPlayerPosition() -- continent, zone, x, y
	local dist, xDelta, yDelta = Astrolabe:ComputeDistance( C, Z, X, Y, point.c, point.z, point.x, point.y )
	if not xDelta or not yDelta then return end
	local dir = atan2(xDelta, -(yDelta))
	if ( dir > 0 ) then
		return twopi - dir;
	else
		return -dir;
	end
end

function TomTom:GetDistanceToIcon( point )
	if not WorldMapSize or table.getn(WorldMapSize) < 1 then
		return 999, 999, 0 -- quick fix to not calculate distances when the system hasnt initiated yet
	end
	local C,Z,X,Y = Astrolabe:GetCurrentPlayerPosition() -- continent, zone, x, y
	local dist, xDelta, yDelta = Astrolabe:ComputeDistance( C, Z, X, Y, point.c or point.continent, point.z or point.zone, point.x, point.y )
	return dist, xDelta, yDelta
end

function TomTom:GetZoneInfo(zone, cont)
	if zone == nil then
		return
	end
	zone = self.extraZones[zone] or zone
	zone = type(zone) == "string" and string.lower(zone) or zone
	for continent, zones in pairs(Astrolabe.ContinentList) do
		for index, zData in pairs(zones) do
			local nameLower = string.lower(zData.mapFile)
			local nameLower2 = string.lower(zData.mapName)
			if (cont ~= nil and cont == continent and zone == index) or zone == nameLower or zone == nameLower2 then
				return continent, index, zData.mapName
			end
		end
	end
	return nil, nil, nil
end

function TomTom:RoundCoords(x,y,prec)
	local fmt = string.format("%%.%df, %%.%df", prec, prec)
	return string.format(fmt, x * 100, y * 100)
end

-- Code courtesy ckknight
function TomTom:GetCurrentCursorPosition()
    local x, y = GetCursorPosition()
    local left, top = WorldMapDetailFrame:GetLeft(), WorldMapDetailFrame:GetTop()
    local width = WorldMapDetailFrame:GetWidth()
    local height = WorldMapDetailFrame:GetHeight()
    local scale = WorldMapDetailFrame:GetEffectiveScale()
    local cx = (x/scale - left) / width
    local cy = (top - y/scale) / height

    if cx < 0 or cx > 1 or cy < 0 or cy > 1 then
        return nil, nil
    end

    return cx, cy
end

-- Hook the WorldMap OnClick
local world_click_verify = {
    ["A"] = function() return IsAltKeyDown() end,
    ["C"] = function() return IsControlKeyDown() end,
    ["S"] = function() return IsShiftKeyDown() end,
}

local origScript = WorldMapButton_OnClick
WorldMapButton_OnClick = function(...)
    if WorldMapButton.ignoreClick then
        WorldMapButton.ignoreClick = false;
        return;
    end
    local mouseButton = unpack(arg)
    if mouseButton == "RightButton" then
        -- Check for all the modifiers that are currently set
        local notSet = false
        string.gsub(TomTom.db.profile.worldmap.create_modifier, "(%S)", function(mod)
            if not world_click_verify[mod] or not world_click_verify[mod]() then
            	notSet = true
            end
        end)
        if notSet then
        	return origScript and origScript(unpack(arg)) or true
        end
		local z = GetCurrentMapZone()
		local c = GetCurrentMapContinent()
        local x,y = TomTom:GetCurrentCursorPosition()

        if c < 1 then
        	local closestC, closestZ, closestX, closestY, closestD = 0, 0, 0, 0, 1
        	for cn, cInfo in WorldMapSize do
        		if cn > 0 then
        			for zn in cInfo do
        				if type(zn) == 'number' then
	        				local nX, nY = Astrolabe:TranslateWorldMapPosition(c, z, x, y, cn, zn)
	        				if nX and nY and 0 < nX and nX <= 1 and 0 < nY and nY <= 1 then
	        					local d = math.abs(nX - 0.5) + math.abs(nX - 0.5)
	        					if d < closestD then
	        						closestC, closestZ, closestX, closestY, closestD = cn, zn, nX, nY, d
	        					end
	        				end
	        			end
        			end
        		end
        	end
        	if closestC > 0 then
        		c, z, x, y = closestC, closestZ, closestX, closestY
        	end
        end
        if c > 0 and z < 1 then
        	local closestZ, closestX, closestY, closestD = 0, 0, 0, 1
			for zn in WorldMapSize[c] do
				if type(zn) == 'number' then
					local nX, nY = Astrolabe:TranslateWorldMapPosition(c, z, x, y, c, zn)
					if nX and nY and 0 < nX and nX <= 1 and 0 < nY and nY <= 1 then
						local d = math.abs(nX - 0.5) + math.abs(nX - 0.5)
						if d < closestD then
							closestZ, closestX, closestY, closestD = zn, nX, nY, d
						end
					end
				end
			end
        	if closestZ > 0 then
        		z, x, y = closestZ, closestX, closestY
        	end
        end

        if c < 1 or z < 1 then
            return origScript and origScript(unpack(arg)) or true
        end

        local uid = TomTom:AddMFWaypoint(c,z,x,y)
    else
        return origScript and origScript(unpack(arg)) or true
    end
end

if WorldMapButton:GetScript("OnClick") == origScript then
    WorldMapButton:SetScript("OnClick", WorldMapButton_OnClick)
end

------------- console -----------------
TomTom.options = {
    type = 'group',
    args = {
    	arrow = {
    		type = 'group',
    		name = 'arrow',
    		desc = 'Crazy arrow related options',
    		args = {
				autoqueue = {
					type = 'toggle',
					name = 'autoqueue',
					desc = 'Put new waypoints as the arrow target',
					get = function() return TomTom.profile.arrow.autoqueue end,
					set = function(value) TomTom.profile.arrow.autoqueue = value end
				},
				locked = {
					type = 'toggle',
					name = 'locked',
					desc = 'Lock the crazy arrow',
					get = function() return TomTom.profile.arrow.locked end,
					set = function(value) TomTom.profile.arrow.locked = value end
				},
				arrival = {
					type = 'range',
					name = 'arrival',
					usage = "<range in meters>",
					min = -1, max = 100,
					desc = 'Range of arrival, when to show the down icon',
					get = function() return TomTom.profile.arrow.arrival end,
					set = function(value) TomTom.profile.arrow.arrival = value end
				},
				continueclosest = {
					type = 'toggle',
					name = 'continueclosest',
					desc = 'Select the closest waypoint when current is cleared',
					get = function() return TomTom.profile.arrow.continueclosest end,
					set = function(value) TomTom.profile.arrow.continueclosest = value end
				},
				enablePing = {
					type = 'toggle',
					name = 'enablePing',
					desc = 'Play the ping sound when arrived',
					get = function() return TomTom.profile.arrow.enablePing end,
					set = function(value) TomTom.profile.arrow.enablePing = value end
				},
				menu = {
					type = 'toggle',
					name = 'menu',
					desc = 'Enable the right mouse button context menu',
					get = function() return TomTom.profile.arrow.menu end,
					set = function(value) TomTom.profile.arrow.menu = value end
				},
				-- debug stuff --
		    	resetpos = {
		    		type = "execute",
		    		name = "resetpos",
		    		desc = "Reset the crazy arrow location to middle of screen",
		    		func = function() TomTom.wayframe:SetPoint("CENTER", UIParent, "CENTER") end
		    	},
				show = {
					type = 'toggle',
					name = 'show',
					desc = 'Show the crazy arrow if there are waypoints. Reset on login',
					get = function() return not TomTom.isHide end,
					set = function(value)
						TomTom.isHide = not value
						if value then TomTom.wayframe:Show() end
						end
				}
    		}
    	},
    	persistence = {
    		type = 'group',
    		name = 'persistence',
    		desc = 'Persistence related info',
    		args = {
				savewaypoints = {
					type = 'toggle',
					name = 'savewaypoints',
					desc = 'Should the default behavior of new waypoints to be save them between sessions?',
					get = function() return TomTom.profile.persistence.savewaypoints end,
					set = function(value) TomTom.profile.persistence.savewaypoints = value end
				},
				cleardistance = {
					type = 'range',
					name = 'cleardistance',
					usage = "<range in meters>",
					min = -1, max = 100,
					desc = 'Range when to remove the waypoint',
					get = function() return TomTom.profile.persistence.cleardistance end,
					set = function(value) TomTom.profile.persistence.cleardistance = value end
				},

    		}
    	},
    	general = {
    		type = 'group',
    		name = 'general',
    		desc = 'General info',
    		args = {
				announce = {
					type = 'toggle',
					name = 'announce',
					desc = 'Write into chat when waypoints are added or removed?',
					get = function() return TomTom.profile.general.announce end,
					set = function(value) TomTom.profile.general.announce = value end
				},
				confirmremoveall = {
					type = 'toggle',
					name = 'confirmremoveall',
					desc = 'Confirm with a popup when removing all waypoints?',
					get = function() return TomTom.profile.general.confirmremoveall end,
					set = function(value) TomTom.profile.general.confirmremoveall = value end
				},
				corpsewaypoint = {
					type = 'toggle',
					name = 'corpsewaypoint',
					desc = 'Add a waypoint when dying?',
					get = function() return TomTom.profile.general.corpsewaypoint end,
					set = function(value) TomTom.profile.general.corpsewaypoint = value end
				},
    		}
    	},
    	worldmap = {
    		type = 'group',
    		name = 'worldmap',
    		desc = 'Worldmap info',
    		args = {
				enable = {
					type = 'toggle',
					name = 'enable',
					desc = 'Put new waypoints on the world map?',
					get = function() return TomTom.profile.worldmap.enable end,
					set = function(value) TomTom.profile.worldmap.enable = value end
				},
				tooltip = {
					type = 'toggle',
					name = 'tooltip',
					desc = 'Show a tooltip when mouse overing in world map?',
					get = function() return TomTom.profile.worldmap.tooltip end,
					set = function(value) TomTom.profile.worldmap.tooltip = value end
				},
				menu = {
					type = 'toggle',
					name = 'menu',
					desc = 'Enable the right mouse button context menu on world map?',
					get = function() return TomTom.profile.worldmap.menu end,
					set = function(value) TomTom.profile.worldmap.menu = value end
				},
				create_modifier = {
					type = 'text',
					name = 'create_modifier',
					validate = { "S", "C", "A", "SC", "SA", "CA", "SCA" },
					desc = 'Which modifiers(S=shift,C=control,A=alt) should be down when right clicking world map to create a waypoint?',
					get = function() return TomTom.profile.worldmap.create_modifier end,
					set = function(value) TomTom.profile.worldmap.create_modifier = value end
				},

    		}
    	},
    	minimap = {
    		type = 'group',
    		name = 'minimap',
    		desc = 'Minimap info',
    		args = {
				enable = {
					type = 'toggle',
					name = 'enable',
					desc = 'Put new waypoints on the minimap?',
					get = function() return TomTom.profile.minimap.enable end,
					set = function(value) TomTom.profile.minimap.enable = value end
				},
				tooltip = {
					type = 'toggle',
					name = 'tooltip',
					desc = 'Show a tooltip when mouse overing in minimap?',
					get = function() return TomTom.profile.minimap.tooltip end,
					set = function(value) TomTom.profile.minimap.tooltip = value end
				},
				menu = {
					type = 'toggle',
					name = 'menu',
					desc = 'Enable the right mouse button context menu on minimap?',
					get = function() return TomTom.profile.minimap.menu end,
					set = function(value) TomTom.profile.minimap.menu = value end
				},
    		}
    	},
	}
}

function TomTom:GetCurrentPlayerPosition()
    return Astrolabe:GetCurrentPlayerPosition()
end

function TomTom:CleanZoneName(s)
	return string.gsub(string.lower(s), "[^%a%d]", "")
end

function TomTom:AddMFWaypoint(pcont, pzone, x, y, opts)
	opts = opts or {}
	local cont, zone = pcont, pzone
	if not cont then
		cont, zone = self:GetZoneInfo(self:CleanZoneName(zone))
	end
	if not cont or not zone then
		if not pcont and pzone then
			self:Print("TomTom: Could not find any matches for the zone %s.", pzone)
			local cleanedName = string.lower(self:CleanZoneName(pzone))
			self:Print("TomTom: Consider adding the zone mapping '%s' to Addons/TomTom/TomTom.lua line 25", cleanedName)
		else
			self:Print("TomTom: Could not find any matches for the continent %s and zone %s in Astrolabe:WorldMapSize map", pcont, pzone)
		end
		return nil
	end

	-- Default values
    if opts.persistent == nil then opts.persistent = self.profile.persistence.savewaypoints end
    if opts.minimap == nil then opts.minimap = self.profile.minimap.enable end
    if opts.world == nil then opts.world = self.profile.worldmap.enable end
    if opts.crazy == nil then opts.crazy = self.profile.arrow.autoqueue end
	if opts.cleardistance == nil then opts.cleardistance = self.profile.persistence.cleardistance end
	if opts.arrivaldistance == nil then opts.arrivaldistance = self.profile.arrow.arrival end

	-- uid is the 'new waypoint' called this for historical reasons
    local uid = {continent = cont, zone = zone, x = x, y = y, title = opts.title}

    -- Copy over any options, so we have em
    for k,v in pairs(opts) do
        if not uid[k] then
            uid[k] = v
        end
    end

    -- If this is a persistent waypoint, then add it to the waypoints table
    if opts.persistent and not isLoading then
        table.insert(self.waypointprofile, uid)
    end

    if not opts.silent and self.profile.general.announce then
    	local _, _, zoneName = self:GetZoneInfo(zone, cont)
        local ctxt = self:RoundCoords(x, y, 2)
        local desc = opts.title and opts.title or ""
        local sep = opts.title and " - " or ""
        self:Print("|cffffff78TomTom:|r Added a waypoint (%s%s%s) in %s", desc, sep, ctxt, zoneName)
    end
    return self:LoadWayPoint(uid)
end

function TomTom:LoadWayPoint(uid)
	table.insert(self.waypoints, uid)
    if uid.crazy then
        self:SetArrowWaypoint(uid)
    end
   if not uid.callbacks then
		uid.callbacks = self:DefaultCallbacks()
	end
    -- No need to convert x and y because they're already 0-1 instead of 0-100
    self:SetWaypoint(uid, uid.callbacks, uid.minimap, uid.world)
    return uid
end
--[[-------------------------------------------------------------------
--  Dropdown menu code
-------------------------------------------------------------------]]--

StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"] = {
	preferredIndex = STATICPOPUPS_NUMDIALOGS,
    text = "Are you sure you would like to remove ALL TomTom waypoints?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        TomTom:RemoveAllWaypoints()
    end,
    timeout = 30,
    whileDead = 1,
    hideOnEscape = 1,
}

local dropdown_info = {
    -- Define level one elements here
    [1] = {
		{ -- Title
	        text = "Waypoint Options",
	        isTitle = 1,
	    },
	    { -- hide crazy arrow
	        text = "Hide waypoint arrow",
		    visible = function()
		    	return TomTom.dropdown.isArrow
		    end,
	        func = function()
	            TomTom.isHide = true
	        end,
	    },
	    { -- set as crazy arrow
	        text = "Set as waypoint arrow",
		    disabled = function()
		        return TomTom.dropdown.uid == TomTom.active_waypoint
		    end,
		    visible = function()
		    	return not TomTom.dropdown.isArrow
		    end,
	        func = function()
	            local uid = TomTom.dropdown.uid
	            local data = uid
	            TomTom:SetArrowWaypoint(uid)
	        end,
	    },
	    { -- Remove waypoint
		    text = "Remove waypoint",
		    func = function()
		        local uid = TomTom.dropdown.uid
		        local data = uid
		        TomTom:GoToNextWayPoint(uid)
		        --TomTom:PrintF("Removing waypoint %0.2f, %0.2f in %s", data.x, data.y, data.zone)
		    end,
		},
		{ -- Remove all waypoints from this zone
			text = "Remove all waypoints from this zone",
			func = function()
			    local uid = TomTom.dropdown.uid
			    local data = uid
			    local continent, zone = data.continent, data.zone

				local _, _, zoneName = TomTom:GetZoneInfo(zone, continent)
	            local numRemoved = 0
	            local waypoints = TomTom:GetWaypoints(continent, zone)
	            if waypoints and table.getn(waypoints) > 0 then
	                for _, uid in pairs(waypoints) do
	                    TomTom:RemoveWaypoint(uid, true)
	                    numRemoved = numRemoved + 1
	                end
	                ChatFrame1:AddMessage(string.format("Removed %d waypoints from %s", numRemoved, zoneName))
				end
			end,
		},
		{ -- Remove ALL waypoints
	        text = "Remove all waypoints",
	        func = function()
	            if TomTom.db.profile.general.confirmremoveall then
	                StaticPopup_Show("TOMTOM_REMOVE_ALL_CONFIRM")
	            else
	                StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"].OnAccept()
	                return
	            end
	        end,
	    },
	    { -- Save this waypoint
		    text = "Save this waypoint between sessions",
		    checked = function()
		        return TomTom.dropdown.uid.persistent
		    end,
		    func = function()
		        -- Add/remove it from the SV file
		        local uid = TomTom.dropdown.uid
		        uid.persistent = not uid.persistent
		        if uid.persistent then
		        	table.insert(TomTom.waypointprofile, uid)
		        else
					for k, w in pairs(TomTom.waypointprofile) do
						if w == uid then
							table.remove(TomTom.waypointprofile, k)
							break
						end
					end
				end
		    end,
		},
    },
}

local function init_dropdown(self, level)
    -- Make sure level is set to 1, if not supplied
    level = level or 1

    -- Get the current level from the info table
    local info = dropdown_info[level]

    -- If a value has been set, try to find it at the current level
    if level > 1 and UIDROPDOWNMENU_MENU_VALUE then
        if info[UIDROPDOWNMENU_MENU_VALUE] then
            info = info[UIDROPDOWNMENU_MENU_VALUE]
        end
    end

    -- Add the buttons to the menu
    for idx,entry in ipairs(info) do
        if type(entry.checked) == "function" then
            -- Make this button dynamic
            local new = {}
            for k,v in pairs(entry) do new[k] = v end
            new.checked = new.checked()
            entry = new
        else
            entry.checked = nil
        end
        if type(entry.visible) == "function" then
            if (not entry.visible()) then
            	entry = nil
            end
        end
        if entry ~= nil then
        	UIDropDownMenu_AddButton(entry, level)
        end
    end
end

function TomTom:InitializeDropdown(uid, isArrow)
    self.dropdown.uid = uid
    self.dropdown.isArrow = isArrow
    UIDropDownMenu_Initialize(self.dropdown, init_dropdown)
end

--[[-------------------------------------------------------------------
--  Define callback functions
-------------------------------------------------------------------]]--
local function _minimap_onclick(event, uid, self, button)
    if TomTom.db.profile.minimap.menu then
        TomTom:InitializeDropdown(uid, false)
        TomTom.dropdown:SetClampedToScreen(true);
        ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
    end
end

local function _world_onclick(event, uid, self, button)
    if TomTom.db.profile.worldmap.menu then
        TomTom:InitializeDropdown(uid, false)
        ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
    end
end

local function _both_tooltip_show(event, tooltip, uid, dist)
    local data = uid

    tooltip:SetText(data.title or "TomTom waypoint")
    if dist and tonumber(dist) then
        tooltip:AddLine(string.format("%s meters away", math.floor(dist)), 1, 1, 1)
    else
        tooltip:AddLine("Unknown distance")
    end
	local _, _, zoneName = TomTom:GetZoneInfo(data.zone, data.continent)
	local x, y = data.x, data.y

    tooltip:AddLine(string.format("%s (%.2f, %.2f)", zoneName, x*100, y*100), 0.7, 0.7, 0.7)
    tooltip:Show()
end

local function _minimap_tooltip_show(event, tooltip, uid, dist)
    if not TomTom.db.profile.minimap.tooltip then
        tooltip:Hide()
        return
    end
    return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _world_tooltip_show(event, tooltip, uid, dist)
    if not TomTom.db.profile.worldmap.tooltip then
        tooltip:Hide()
        return
    end
    return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _both_tooltip_update(event, tooltip, uid, dist)
	if not tooltip or not tooltip.lines then return end
    if dist and tonumber(dist) then
        tooltip.lines[2]:SetFormattedText("%s meters away", math.floor(dist), 1, 1, 1)
    else
        tooltip.lines[2]:SetText("Unknown distance")
    end
end


function TomTom:DefaultCallbacks()
	return {
		minimap = {
			onclick = _minimap_onclick,
			tooltip_show = _minimap_tooltip_show,
			tooltip_update = _both_tooltip_update
		},
		world = {
			onclick = _world_onclick,
			tooltip_show = _world_tooltip_show,
			tooltip_update = _both_tooltip_show
		}
	}
end

function TomTom:Print(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
	a1 = tostring(a1)
	if string.find(a1, "%%") then
		self:log(string.format(a1, tostring(a2), tostring(a3), tostring(a4), tostring(a5), tostring(a6), tostring(a7), tostring(a8), tostring(a9), tostring(a10), tostring(a11), tostring(a12), tostring(a13), tostring(a14), tostring(a15), tostring(a16), tostring(a17), tostring(a18), tostring(a19), tostring(a20)))
	else
		self:log(a1)
	end
end

function TomTom:GetWaypoints(cont, zone)
	local ret = {}
	for _, wp in pairs(self.waypoints) do
		if wp.continent == cont and wp.zone == zone then
			table.insert(ret, wp)
		end
	end
	return ret
end

function TomTom:DebugListWaypoints(zone)
	local all = zone == "all"
	local singleZone = not all and zone ~= nil and zone or nil
    local cont,zoneid,x,y = self:GetCurrentPlayerPosition()
    local _, _, czone = self:GetZoneInfo(zoneid, cont)
    local ctxt = self:RoundCoords(x, y, 2)
    self:Print("You are at (%s) in '%s' (continent: %d, zone id: %d)", ctxt, czone or "UNKNOWN", cont, zoneid)
    if singleZone ~= nil then
    	cont, zoneid, czone = self:GetZoneInfo(singleZone)
    end
    local wps = all and self.waypoints or self:GetWaypoints(cont, zoneid)
    if wps and table.getn(wps) > 0 then
        for key, wp in wps do
            local ctxt = self:RoundCoords(wp.x, wp.y, 2)
            local desc = wp.title and wp.title or "Unknown waypoint"
            local czone = all and select(3, self:GetZoneInfo(wp.zone, wp.continent)) or czone
            local indent = "   "
            self:Print("%s%s - %s (continent: %s, zone id: %s, zone: %s)", indent, desc, ctxt, wp.continent, wp.zone, czone)
        end
    else
        local indent = "   "
        self:Print("%sNo waypoints%s", indent, all and "" or " in this zone")
    end
end

function TomTom:InitConsole()
	self:RegisterChatCommand({'/tomtom'}, self.options)
	TomTomWayHandler:Register(self)
end

function TomTom:SetClosestWaypoint()
	local closestW, closestD
	for _, w in pairs(self.waypoints) do
		local dist = self:GetDistanceToIcon(w)
		if not closestW or not closestD or dist and dist < closestD then
			closestW, closestD = w, dist
		end
	end
	if closestW then
		self:SetArrowWaypoint(closestW)
	else
		self:Print("No waypoints on this continent")
	end
end

function TomTom:GoToNextWayPoint(wpToRemove)
	if wpToRemove ~= nil then
		self:RemoveWaypoint(wpToRemove)
	end
	local nWayPoints = table.getn(self.waypoints)
	if nWayPoints < 1 then
		self:ClearCrazyArrow()
	elseif self.profile.arrow.continueclosest then
		self:SetClosestWaypoint()
	else
		self:SetArrowWaypoint(self.waypoints[nWayPoints])
	end
end

function TomTom:RemoveWaypointsOfGroup(group)
    for i = table.getn(self.waypoints), 1, -1 do
    	local wp = self.waypoints[i]
    	if wp.group == group then
        	self:RemoveWaypoint(wp, true)
        end
    end
    self:GoToNextWayPoint()
end

function TomTom:RemoveWaypoint(waypointUid, silent)
	for k, w in pairs(self.waypoints) do
		if w == waypointUid then
			table.remove(self.waypoints, k)
			break
		end
	end
	for k, w in pairs(self.waypointprofile) do
		if w == waypointUid then
			table.remove(self.waypointprofile, k)
			break
		end
	end
	if self.active_waypoint == waypointUid then
		self:ClearCrazyArrow()
	end
	self:ClearWaypoint(waypointUid)
    if not silent and not waypointUid.silent and self.profile.general.announce then
    	local _, _, zoneName = self:GetZoneInfo(waypointUid.zone, waypointUid.continent)
        local ctxt = self:RoundCoords(waypointUid.x, waypointUid.y, 2)
        local desc = waypointUid.title and waypointUid.title or ""
        local sep = waypointUid.title and " - " or ""
        self:Print("|cffffff78TomTom:|r Removed a waypoint (%s%s%s) in %s", desc, sep, ctxt, zoneName)
	end
end

function TomTom:RemoveAllWaypoints()
    for i = table.getn(self.waypoints), 1, -1 do
        self:RemoveWaypoint(self.waypoints[i], true)
    end
end

function TomTom:OnProfileEnable()
    -- This handles the reloading of all options
    self.profile = self.db.profile
    if self.profile.arrow.location ~= nil then
		self.wayframe:SetPoint(unpack(self.profile.arrow.location))
	else
		self.wayframe:SetPoint("CENTER", UIParent, "CENTER")
	end
	if self.waypoints then
	    for _, w in pairs(self.waypoints) do
	    	self:ClearWaypoint(w)
	    end
	    self:ClearCrazyArrow()
	end

    local waypoints = {}
    self.waypoints = waypoints

    if (self.db.profile.waypoints == nil) then
    	self.db.profile.waypoints = {}
    end
    self.waypointprofile = self.db.profile.waypoints

    for _,waypoint in pairs(self.waypointprofile) do
    	waypoint.callbacks = nil
        self:LoadWayPoint(waypoint)
    end
end
