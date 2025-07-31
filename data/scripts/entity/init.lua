if onServer() then
    local entity = Entity()
    if not entity.aiOwned and (entity.isShip or entity.isStation or entity.isDrone) then
        entity:addScriptOnce("sectoroverview.lua")
    end
end