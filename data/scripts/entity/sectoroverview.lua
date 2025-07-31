-- namespace SectorOverview
SectorOverview = {}

if onClient() then


-- PREDEFINED --

function SectorOverview.getIcon()
    return "data/textures/icons/sectoroverview/icon.png"
end

function SectorOverview.interactionPossible(playerIndex)
    local craft = Player(playerIndex).craft
    if craft ~= nil and craft.index == Entity().index then
        return true
    end
    return false
end

function SectorOverview.initUI()
    ScriptUI():registerInteraction("Sector Overview"%_t, "onSectorOverviewBtn")
end

-- CALLBACKS --

function SectorOverview.onSectorOverviewBtn()
    local status = Player():invokeFunction("data/scripts/player/ui/sectorshipoverview.lua", "sectorOverview_toggleWindow")
    if status ~= 0 then
        eprint("[SectorOverview]: failed to call sectorOverview_toggleWindow, code: %i", status)
    end
end


end