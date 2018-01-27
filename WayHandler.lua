
TomTomWayHandler = {}

TomTomWayHandler.tomtom = nil

function TomTomWayHandler:Register(tomtom)
	self.tomtom = tomtom
	
	SLASH_TOMTOM_WAY1 = "/way"
	SLASH_TOMTOM_WAY2 = "/tway"
	SLASH_TOMTOM_WAY3 = "/tomtomway"
	SlashCmdList["TOMTOM_WAY"] = function(msg) self:ChatHandler(msg) end
	
	SLASH_TOMTOM_CLOSEST_WAYPOINT1 = "/cway"
	SLASH_TOMTOM_CLOSEST_WAYPOINT2 = "/closestway"
	SlashCmdList["TOMTOM_CLOSEST_WAYPOINT"] = function(msg) self.tomtom:SetClosestWaypoint() end
	
	SLASH_TOMTOM_WAYBACK1 = "/wayb"
	SLASH_TOMTOM_WAYBACK2 = "/wayback"
	SlashCmdList["TOMTOM_WAYBACK"] = function(msg) self:AddWayBack() end
end

--[[
/way <x> <y> [desc] - Adds a waypoint at x,y with description desc
/way <zone> <x> <y> [desc] - Adds a waypoint at x,y in zone with descript desc
/way reset all - Resets all waypoints
/way reset <zone> - Resets all waypoints in zone
/way list - Lists active waypoints
]]

function TomTomWayHandler:Usage()
    ChatFrame1:AddMessage("|cffffff78TomTom |r/way |cffffff78Usage:|r")
    ChatFrame1:AddMessage("|cffffff78/way <x> <y> [desc]|r - Adds a waypoint at x,y with descrtiption desc")
    ChatFrame1:AddMessage("|cffffff78/way <zone> <x> <y> [desc]|r - Adds a waypoint at x,y in zone with description desc")
    ChatFrame1:AddMessage("|cffffff78/way reset|r - Resets waypoints in current zone")
    ChatFrame1:AddMessage("|cffffff78/way reset all|r - Resets all waypoints")
    ChatFrame1:AddMessage("|cffffff78/way reset <zone>|r - Resets all waypoints in zone")
    ChatFrame1:AddMessage("|cffffff78/way list|r - Lists active waypoints in current zone")
    ChatFrame1:AddMessage("|cffffff78/way list all|r - Lists all active waypoints")
    ChatFrame1:AddMessage("|cffffff78/way list <zone>|r - Lists active waypoints in zone")
end

function TomTomWayHandler:AddWayBack()
	local backc,backz,backx,backy = TomTom:GetCurrentPlayerPosition()
	TomTom:AddMFWaypoint(backc, backz, backx, backy, {
	    title = "Wayback",
	})
end

function TomTomWayHandler:ChatHandler(msg)
	msg = msg or ""
	local wrongseparator = "(%d)" .. (tonumber("1.1") and "," or ".") .. "(%d)"
	local rightseparator = "%1" .. (tonumber("1.1") and "." or ",") .. "%2"

    msg = string.gsub(string.gsub(msg, "(%d)[%.,] (%d)", "%1 %2"), wrongseparator, rightseparator)
    local tokens = {}
    string.gsub(msg, "(%S+)", function(c) table.insert(tokens, c) end)

    -- Lower the first token
    local ltoken = tokens[1] and string.lower(tokens[1])

    if ltoken == "list" then
    	local ltoken2 = tokens[2] and string.lower(tokens[2])
    	if ltoken2 ~= nil and ltoken2 ~= "all" then
    		ltoken2 = TomTom:CleanZoneName(table.concat(tokens, " ", 2))
    	end
    	TomTom:DebugListWaypoints(ltoken2)
        return
    elseif ltoken == "reset" or ltoken == "remove" or ltoken == "clear" or ltoken == "clean" or ltoken == "del" or ltoken == "delete" then
        local ltoken2 = tokens[2] and string.lower(tokens[2])
        if ltoken2 == "all" then
            if TomTom.db.profile.general.confirmremoveall then
                StaticPopup_Show("TOMTOM_REMOVE_ALL_CONFIRM")
            else
                StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"].OnAccept()
                return
            end
        else
        	local cont, zoneid
        	if not ltoken2 then
        		cont, zoneid = TomTom:GetCurrentPlayerPosition()
        	else
	            local zone = table.concat(tokens, " ", 2)
	            cont, zoneid = TomTom:GetZoneInfo(lowergsub(zone))
        	end
            if cont == nil then
                local msg = string.format("Could not find any matches for zone %s.", zone)
                ChatFrame1:AddMessage(msg)
                return
            end
            local _, _, zoneName = TomTom:GetZoneInfo(zoneid, cont)
            local numRemoved = 0
            local waypoints = TomTom:GetWaypoints(cont, zoneid)
            if waypoints and table.getn(waypoints) > 0 then
                for key, uid in pairs(waypoints) do
                    TomTom:RemoveWaypoint(uid, true)
                    numRemoved = numRemoved + 1
                end
                ChatFrame1:AddMessage(string.format("Removed %d waypoints from %s", numRemoved, zoneName))
            else
                ChatFrame1:AddMessage(string.format("There were no waypoints to remove in %s", zoneName))
            end
        end
    elseif tokens[1] and not tonumber(tokens[1]) then
        -- Example: /way Elwynn Forest 34.2 50.7 Party in the forest!
        -- tokens[1] = Elwynn
        -- tokens[2] = Forest
        -- tokens[3] = 34.2
        -- tokens[4] = 50.7
        -- tokens[5] = Party
        -- ...
        --
        -- Find the first numeric token
        local zoneEnd
        for idx = 1, table.getn(tokens) do
            local token = tokens[idx]
            if tonumber(token) then
                -- We've encountered a number, so the zone name must have
                -- ended at the prior token
                zoneEnd = idx - 1
                break
            end
        end

        if not zoneEnd then
            self:Usage()
            return
        end

        -- This is a waypoint set, with a zone before the coords
        local zone = table.concat(tokens, " ", 1, zoneEnd)
        local x, y, desc = tokens[zoneEnd + 1], tokens[zoneEnd + 2], tokens[zoneEnd + 3]
        if desc then desc = table.concat(tokens, " ", zoneEnd + 3) end
		local cont, zoneid = TomTom:GetZoneInfo(TomTom:CleanZoneName(zone))

        if cont == nil then
            local msg = string.format("Could not find any matches for zone %s.", zone)
            ChatFrame1:AddMessage(msg)
            return
        end
        --self.tomtom:log(string.format("%s %s %s %s", lowergsub(zone), x or "nil", y or "nil", desc or "nil"))

        x = x and tonumber(x)
        y = y and tonumber(y)

        if not x or not y then
            return self:Usage()
        end
        self.tomtom:AddMFWaypoint(cont, zoneid, x/100, y/100, {
            title = desc,
        })
    elseif tonumber(tokens[1]) then
        -- A vanilla set command
        local x,y,desc = unpack(tokens)
        if not x or not tonumber(x) then
            return self:Usage()
        elseif not y or not tonumber(y) then
            return self:Usage()
        end
        if desc then
            desc = table.concat(tokens, " ", 3)
        end
        x = tonumber(x)
        y = tonumber(y)

        local cont, zone = TomTom:GetCurrentPlayerPosition()
        if cont and zone and x and y then
            self.tomtom:AddMFWaypoint(cont, zone, x/100, y/100, {
                title = desc
            })
        end
    else
        return self:Usage()
    end
end
