include("callable")
include("azimuthlib-uiproportionalsplitter")
local Azimuth = include("azimuthlib-basic")
local CustomTabbedWindow = include("azimuthlib-customtabbedwindow")

local SectorOverviewConfig -- client/server
local sectorOverview_notifyAboutEnemies -- server
local sectorOverview_configOptions, sectorOverview_isVisible, sectorOverview_refreshCounter, sectorOverview_settingsModified, sectorOverview_playerAddedList, sectorOverview_playerCoords, sectorOverview_GT135 -- client
local sectorOverview_tabbedWindow, sectorOverview_stationTab, sectorOverview_stationList, sectorOverview_shipTab, sectorOverview_shipList, sectorOverview_gateTab, sectorOverview_gateList, sectorOverview_playerTab, sectorOverview_playerList, sectorOverview_playerCombo, sectorOverview_windowWidthBox, sectorOverview_windowHeightBox, sectorOverview_notifyAboutEnemiesCheckBox, sectorOverview_showNPCNamesCheckBox, sectorOverview_toggleBtnComboBox, sectorOverview_prevTabBtnComboBox, sectorOverview_nextTabBtnComboBox -- client UI
local sectorOverview_iconColumnWidthBox, sectorOverview_rowHeightBox, sectorOverview_iconsPerRowBox, sectorOverview_showBulletinBoardsTabCheckBox, sectorOverview_showWreckagesCheckBox, sectorOverview_showGoodsTabCheckBox, sectorOverview_showCrewTabCheckBox -- new UI controls
local sectorOverview_goodsTab, sectorOverview_goodsList, sectorOverview_crewTab, sectorOverview_crewList, sectorOverview_missionTab, sectorOverview_missionList -- additional tabs


if onClient() then


sectorOverview_GT135 = GameVersion() >= Version(1, 3, 5)

-- PREDEFINED --

-- Store base initialize function before overriding
local BaseInitialize = SectorShipOverview.initialize

function SectorShipOverview.initialize() -- overridden
    -- Call base game initialization first to set up overviewList and other base UI
    if BaseInitialize then
        BaseInitialize()
    end
    
    local allowedKeys = {
      {"", "-"},
      {"KP_Divide", "Divide"%_t},
      {"KP_Multiply", "Multiply"%_t},
      {"KP_Minus", "Minus"%_t},
      {"KP_Plus", "Plus"%_t},
      {"KP_1", "1"},
      {"KP_2", "2"},
      {"KP_3", "3"},
      {"KP_4", "4"},
      {"KP_5", "5"},
      {"KP_6", "6"},
      {"KP_7", "7"},
      {"KP_8", "8"},
      {"KP_9", "9"},
      {"KP_0", "0"}
    }
    local keysEnum = {}
    for k, v in ipairs(allowedKeys) do
        keysEnum[k] = v[1]
    end

    sectorOverview_configOptions = {
      ["_version"] = {"1.1", comment = "Config version. Don't touch."},
      ["WindowWidth"] = {320, round = -1, min = 320, max = 800, comment = "UI window width"},
      ["WindowHeight"] = {400, round = -1, min = 360, max = 1000, comment = "UI window height"},
      ["NotifyAboutEnemies"] = {true, comment = "If true, will notify when enemy player (at war) enters a sector."},
      ["ShowNPCNames"] = {true, comment = "If true, sector overview will show unique NPC names in addition to their titles."},
      ["ToggleButton"] = {"KP_Minus", enum = keysEnum, comment = "Pressing this button will open/close the overview window."},
      ["PrevTabButton"] = {"KP_Divide", enum = keysEnum, comment = "Pressing this button will cycle to the previous tab."},
      ["NextTabButton"] = {"KP_Multiply", enum = keysEnum, comment = "Pressing this button will cycle to the next tab."},
      -- Content sizing options
      ["IconColumnWidth"] = {25, round = -1, min = 15, max = 50, comment = "Width of icon columns in all tabs"},
      ["RowHeight"] = {25, round = -1, min = 15, max = 50, comment = "Height of each row in all tabs"},
      ["IconsPerRow"] = {11, round = -1, min = 5, max = 20, comment = "Number of icons per row in multi-column tabs"},
      -- Tab toggle options
      ["ShowBulletinBoardsTab"] = {true, comment = "Show Bulletin Boards tab"},
      ["ShowWreckages"] = {false, comment = "Show wreckages in overview tab"},
      ["ShowGoodsTab"] = {true, comment = "Show Goods tab"},
      ["ShowCrewTab"] = {true, comment = "Show Crew tab"}
    }
    local isModified
    SectorOverviewConfig, isModified = Azimuth.loadConfig("SectorOverview", sectorOverview_configOptions)
    if isModified then
        Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)
    end
    
    -- Override vanilla content sizing properties with our config values (now that config is loaded)
    self.iconColumnWidth = SectorOverviewConfig.IconColumnWidth or 25
    self.rowHeight = SectorOverviewConfig.RowHeight or 25
    self.iconsPerRow = SectorOverviewConfig.IconsPerRow or 11

    -- init UI
    local res = getResolution()
    local size = vec2(SectorOverviewConfig.WindowWidth, SectorOverviewConfig.WindowHeight)
    local position = vec2(res.x - size.x - 5, 180)

    self.window = Hud():createWindow(Rect(position, position + size))
    self.window.caption = "Sector Overview"%_t
    self.window.moveable = true
    self.window.showCloseButton = true
    self.window.visible = false

    local helpLabel = self.window:createLabel(Rect(size.x - 55, -29, size.x - 30, -10), "?", 15)
    helpLabel.tooltip = [[Colors of the object icons indicate ownership type:
* Green - yours.
* Purple - your alliance.
* Yellow - other player.
* Blue - other alliance.
* White - NPC.

Object name color represents relation status (war, ceasefire, neutral, allies)]]%_t

    sectorOverview_tabbedWindow = CustomTabbedWindow(self, self.window, Rect(vec2(10, 10), size - 10))
    sectorOverview_tabbedWindow.onSelectedFunction = "refreshList"

    -- stations
    sectorOverview_stationTab = sectorOverview_tabbedWindow:createTab("Station List"%_t, "data/textures/icons/solar-system.png", "Station List"%_t)
    sectorOverview_stationList = sectorOverview_stationTab:createListBoxEx(Rect(sectorOverview_stationTab.size))
    sectorOverview_stationList.columns = 4
    sectorOverview_stationList:setColumnWidth(0, 25)
    sectorOverview_stationList:setColumnWidth(1, 25)
    sectorOverview_stationList:setColumnWidth(2, sectorOverview_stationList.width - 85)
    sectorOverview_stationList:setColumnWidth(3, 25)
    sectorOverview_stationList.onSelectFunction = "onEntrySelected"

    -- ships
    sectorOverview_shipTab = sectorOverview_tabbedWindow:createTab("Ship List"%_t, "data/textures/icons/ship.png", "Ship List"%_t)
    sectorOverview_shipList = sectorOverview_shipTab:createListBoxEx(Rect(sectorOverview_shipTab.size))
    sectorOverview_shipList.columns = 4
    sectorOverview_shipList:setColumnWidth(0, 25)
    sectorOverview_shipList:setColumnWidth(1, 25)
    sectorOverview_shipList:setColumnWidth(2, sectorOverview_shipList.width - 85)
    sectorOverview_shipList:setColumnWidth(3, 25)
    sectorOverview_shipList.onSelectFunction = "onEntrySelected"

    -- gates
    sectorOverview_gateTab = sectorOverview_tabbedWindow:createTab("Gate & Wormhole List"%_t, "data/textures/icons/vortex.png", "Gate & Wormhole List"%_t)
    sectorOverview_gateList = sectorOverview_gateTab:createListBoxEx(Rect(sectorOverview_gateTab.size))
    sectorOverview_gateList.columns = 2
    sectorOverview_gateList:setColumnWidth(0, 25)
    sectorOverview_gateList:setColumnWidth(1, sectorOverview_gateList.width - 35)
    sectorOverview_gateList.onSelectFunction = "onEntrySelected"

    -- players
    sectorOverview_playerTab = sectorOverview_tabbedWindow:createTab("Player List"%_t, "data/textures/icons/crew.png", "Player List"%_t)
    sectorOverview_playerTab.onSelectedFunction = "sectorOverview_onPlayerTabSelected"

    local hsplit = UIHorizontalProportionalSplitter(Rect(sectorOverview_playerTab.size), 10, 0, {30, 0.5, 25, 35})
    local showButton = sectorOverview_playerTab:createButton(hsplit[1], "Show on Galaxy Map"%_t, "sectorOverview_onShowPlayerPressed")
    showButton.maxTextSize = 14
    showButton.tooltip = [[Show the selected player on the galaxy map.]]%_t

    sectorOverview_playerList = sectorOverview_playerTab:createListBoxEx(hsplit[2])
    sectorOverview_playerCombo = sectorOverview_playerTab:createValueComboBox(hsplit[3], "")

    local vsplit = UIVerticalSplitter(hsplit[4], 10, 0, 0.5)
    local button = sectorOverview_playerTab:createButton(vsplit.left, "Add"%_t, "sectorOverview_onAddPlayerTracking")
    button.maxTextSize = 14
    button.tooltip = "Add the selected player from the combo box to the list of tracked players."%_t
    button = sectorOverview_playerTab:createButton(vsplit.right, "Remove"%_t, "sectorOverview_onRemovePlayerTracking")
    button.maxTextSize = 14
    button.tooltip = "Remove the selected player from the list of tracked players."%_t

    -- settings
    local tab = sectorOverview_tabbedWindow:createTab("Settings"%_t, "data/textures/icons/gears.png", "Settings"%_t)
    local hsplit = UIHorizontalProportionalSplitter(Rect(tab.size), 10, 5, {0.85, 50}) -- 85% for content, 50px for reset
    
    -- Create scrollable frame for settings
    local scrollFrame = tab:createScrollFrame(hsplit[1])
    local lister = UIVerticalLister(Rect(vec2(0, 0), vec2(hsplit[1].width, 1000)), 10, 10)

    local rect = lister:placeCenter(vec2(lister.inner.width, 30))
    local splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    local label = scrollFrame:createLabel(splitter.left, "Open window (numpad)"%_t, 16)
    label:setLeftAligned()
    sectorOverview_toggleBtnComboBox = scrollFrame:createValueComboBox(splitter.right, "sectorOverview_onSettingsModified")

    local rect = lister:placeCenter(vec2(lister.inner.width, 30))
    local splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    local label = scrollFrame:createLabel(splitter.left, "Prev. tab (numpad)"%_t, 16)
    label:setLeftAligned()
    sectorOverview_prevTabBtnComboBox = scrollFrame:createValueComboBox(splitter.right, "sectorOverview_onSettingsModified")
    
    local rect = lister:placeCenter(vec2(lister.inner.width, 30))
    local splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    local label = scrollFrame:createLabel(splitter.left, "Next tab (numpad)"%_t, 16)
    label:setLeftAligned()
    sectorOverview_nextTabBtnComboBox = scrollFrame:createValueComboBox(splitter.right, "sectorOverview_onSettingsModified")

    for _, v in ipairs(allowedKeys) do
        sectorOverview_toggleBtnComboBox:addEntry(v[1], v[2])
        sectorOverview_prevTabBtnComboBox:addEntry(v[1], v[2])
        sectorOverview_nextTabBtnComboBox:addEntry(v[1], v[2])
    end
    sectorOverview_toggleBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.ToggleButton)
    sectorOverview_prevTabBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.PrevTabButton)
    sectorOverview_nextTabBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.NextTabButton)

    local rect = lister:placeCenter(vec2(lister.inner.width, 30))
    local splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    local label = scrollFrame:createLabel(splitter.left, "Window width"%_t, 16)
    label:setLeftAligned()
    sectorOverview_windowWidthBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_windowWidthBox.allowedCharacters = "0123456789"
    sectorOverview_windowWidthBox.text = SectorOverviewConfig.WindowWidth
    sectorOverview_windowWidthBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Window height"%_t, 16)
    label:setLeftAligned()
    sectorOverview_windowHeightBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_windowHeightBox.allowedCharacters = "0123456789"
    sectorOverview_windowHeightBox.text = SectorOverviewConfig.WindowHeight
    sectorOverview_windowHeightBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_notifyAboutEnemiesCheckBox = scrollFrame:createCheckBox(rect, "Notify - enemy players"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_notifyAboutEnemiesCheckBox:setCheckedNoCallback(SectorOverviewConfig.NotifyAboutEnemies)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_showNPCNamesCheckBox = scrollFrame:createCheckBox(rect, "Show NPC names"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_showNPCNamesCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowNPCNames)

    -- Content sizing controls
    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Icon column width"%_t, 16)
    label:setLeftAligned()
    sectorOverview_iconColumnWidthBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_iconColumnWidthBox.allowedCharacters = "0123456789"
    sectorOverview_iconColumnWidthBox.text = SectorOverviewConfig.IconColumnWidth
    sectorOverview_iconColumnWidthBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Row height"%_t, 16)
    label:setLeftAligned()
    sectorOverview_rowHeightBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_rowHeightBox.allowedCharacters = "0123456789"
    sectorOverview_rowHeightBox.text = SectorOverviewConfig.RowHeight
    sectorOverview_rowHeightBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Icons per row"%_t, 16)
    label:setLeftAligned()
    sectorOverview_iconsPerRowBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_iconsPerRowBox.allowedCharacters = "0123456789"
    sectorOverview_iconsPerRowBox.text = SectorOverviewConfig.IconsPerRow
    sectorOverview_iconsPerRowBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    -- Tab toggle controls
    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_showBulletinBoardsTabCheckBox = scrollFrame:createCheckBox(rect, "Show Bulletin Boards tab"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_showBulletinBoardsTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowBulletinBoardsTab)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_showWreckagesCheckBox = scrollFrame:createCheckBox(rect, "Show wreckages in overview"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_showWreckagesCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowWreckages)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_showGoodsTabCheckBox = scrollFrame:createCheckBox(rect, "Show Goods tab"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_showGoodsTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowGoodsTab)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_showCrewTabCheckBox = scrollFrame:createCheckBox(rect, "Show Crew tab"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_showCrewTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowCrewTab)

    local button = tab:createButton(hsplit[2], "Reset"%_t, "sectorOverview_onResetBtnPressed")
    button.maxTextSize = 16

    -- Conditionally create additional tabs using CustomTabbedWindow
    if SectorOverviewConfig.ShowGoodsTab then
        sectorOverview_goodsTab = sectorOverview_tabbedWindow:createTab("Goods"%_t, "data/textures/icons/procure-command.png", "Goods"%_t)
        local hsplit = UIHorizontalSplitter(Rect(sectorOverview_goodsTab.size), 0, 0, 0.045)
        local vsplit = UIVerticalSplitter(hsplit.top, 0, 0, 0.5)
        local supplyLabel = sectorOverview_goodsTab:createLabel(vsplit.left, "[SUPPLY]"%_t, 12)
        supplyLabel:setTopAligned()
        local demandLabel = sectorOverview_goodsTab:createLabel(vsplit.right, "[DEMAND]"%_t, 12)
        demandLabel:setTopAligned()
        
        sectorOverview_goodsList = sectorOverview_goodsTab:createListBoxEx(hsplit.bottom)
        local numColumns = (self.iconsPerRow or 11) + 2
        sectorOverview_goodsList.columns = numColumns
        sectorOverview_goodsList.rowHeight = self.rowHeight or 25
        for i = 1, numColumns do
            sectorOverview_goodsList:setColumnWidth(0, self.iconColumnWidth or 25)
        end
        sectorOverview_goodsList.onSelectFunction = "onEntrySelected"
    end
    
    if SectorOverviewConfig.ShowCrewTab then
        sectorOverview_crewTab = sectorOverview_tabbedWindow:createTab("Crew"%_t, "data/textures/icons/crew.png", "Crew"%_t)
        local hsplit = UIHorizontalSplitter(Rect(sectorOverview_crewTab.size), 0, 0, 0.0)
        sectorOverview_crewList = sectorOverview_crewTab:createListBoxEx(hsplit.bottom)
        local numColumns = (self.iconsPerRow or 11) + 2
        sectorOverview_crewList.columns = numColumns
        sectorOverview_crewList.rowHeight = self.rowHeight or 25
        for i = 1, numColumns do
            sectorOverview_crewList:setColumnWidth(0, self.iconColumnWidth or 25)
        end
        sectorOverview_crewList.onSelectFunction = "onEntrySelected"
    end
    
    if SectorOverviewConfig.ShowBulletinBoardsTab then
        sectorOverview_missionTab = sectorOverview_tabbedWindow:createTab("Bulletin Boards"%_t, "data/textures/icons/wormhole.png", "Bulletin Boards"%_t)
        local hsplit = UIHorizontalSplitter(Rect(sectorOverview_missionTab.size), 0, 0, 0.0)
        sectorOverview_missionList = sectorOverview_missionTab:createListBoxEx(hsplit.bottom)
        local numColumns = (self.iconsPerRow or 11) + 2
        sectorOverview_missionList.columns = numColumns
        sectorOverview_missionList.rowHeight = self.rowHeight or 25
        for i = 1, numColumns do
            sectorOverview_missionList:setColumnWidth(0, self.iconColumnWidth or 25)
        end
        sectorOverview_missionList.onSelectFunction = "onEntrySelected"
    end

    -- callbacks
    Player():registerCallback("onStateChanged", "onPlayerStateChanged")

    self.show()
    self.hide()

    sectorOverview_refreshCounter = 0
    sectorOverview_settingsModified = 0
    sectorOverview_playerAddedList = {}
    sectorOverview_playerCoords = {}

    -- Refresh additional tabs if they were created
    if SectorOverviewConfig.ShowGoodsTab and sectorOverview_goodsList then
        self.sectorOverview_refreshGoodsList()
    end
    
    if SectorOverviewConfig.ShowCrewTab and sectorOverview_crewList then
        self.sectorOverview_refreshCrewList()
    end
    
    if SectorOverviewConfig.ShowBulletinBoardsTab and sectorOverview_missionList then
        self.sectorOverview_refreshMissionList()
    end

    invokeServerFunction("sectorOverview_sendServerConfig")
    invokeServerFunction("sectorOverview_setNotifyAboutEnemies", SectorOverviewConfig.NotifyAboutEnemies)
end

function SectorShipOverview.getUpdateInterval() -- overridden
    return 0
end

function SectorShipOverview.updateClient(timeStep) -- overridden
    if not self.window or not SectorOverviewConfig then return end

    -- Initialize refresh counter if it's nil (safety check)
    if not sectorOverview_refreshCounter then
        sectorOverview_refreshCounter = 0
    end

    local keyboard = Keyboard()
    if SectorOverviewConfig.ToggleButton and SectorOverviewConfig.ToggleButton ~= "" and keyboard:keyDown(KeyboardKey[SectorOverviewConfig.ToggleButton]) then
        if self.window.visible then
            self.hide()
        else
            self.show()
        end
    end
    if self.window.visible then
        -- cycle tabs
        if SectorOverviewConfig.PrevTabButton and SectorOverviewConfig.PrevTabButton ~= "" and keyboard:keyDown(KeyboardKey[SectorOverviewConfig.PrevTabButton]) then
            local pos = sectorOverview_tabbedWindow.activeTab._pos
            if pos == 1 then
                pos = #sectorOverview_tabbedWindow._tabs -- cycle to the end
            else
                pos = pos - 1
            end
            sectorOverview_tabbedWindow:selectTab(sectorOverview_tabbedWindow._tabs[pos])
        elseif SectorOverviewConfig.NextTabButton and SectorOverviewConfig.NextTabButton ~= "" and keyboard:keyDown(KeyboardKey[SectorOverviewConfig.NextTabButton]) then
            local pos = sectorOverview_tabbedWindow.activeTab._pos
            if pos == #sectorOverview_tabbedWindow._tabs then
                pos = 1 -- cycle to the start
            else
                pos = pos + 1
            end
            sectorOverview_tabbedWindow:selectTab(sectorOverview_tabbedWindow._tabs[pos])
        end
        -- update lists
        sectorOverview_refreshCounter = sectorOverview_refreshCounter + timeStep
        if sectorOverview_refreshCounter >= 1 then
            sectorOverview_refreshCounter = 0
            self.refreshList()
            
            -- Refresh additional tabs if they exist
            if SectorOverviewConfig.ShowGoodsTab then
                self.sectorOverview_refreshGoodsList()
            end
            
            if SectorOverviewConfig.ShowCrewTab then
                self.sectorOverview_refreshCrewList()
            end
            
            if SectorOverviewConfig.ShowBulletinBoardsTab then
                self.sectorOverview_refreshMissionList()
            end
        end
    end
    if sectorOverview_settingsModified > 0 then
        sectorOverview_settingsModified = sectorOverview_settingsModified - timeStep
        if sectorOverview_settingsModified <= 0 then -- save config
            SectorOverviewConfig.WindowWidth = tonumber(sectorOverview_windowWidthBox.text) or 0
            if SectorOverviewConfig.WindowWidth < 320 or SectorOverviewConfig.WindowWidth > 800 then
                SectorOverviewConfig.WindowWidth = math.max(320, math.min(800, SectorOverviewConfig.WindowWidth))
                if not sectorOverview_windowWidthBox.isTypingActive then
                    sectorOverview_windowWidthBox.text = SectorOverviewConfig.WindowWidth
                end
            end
            SectorOverviewConfig.WindowHeight = tonumber(sectorOverview_windowHeightBox.text) or 0
            if SectorOverviewConfig.WindowHeight < 360 or SectorOverviewConfig.WindowHeight > 800 then
                SectorOverviewConfig.WindowHeight = math.max(360, math.min(800, SectorOverviewConfig.WindowHeight))
                if not sectorOverview_windowHeightBox.isTypingActive then
                    sectorOverview_windowHeightBox.text = SectorOverviewConfig.WindowHeight
                end
            end
            
            -- Content sizing settings
            SectorOverviewConfig.IconColumnWidth = tonumber(sectorOverview_iconColumnWidthBox.text) or 25
            if SectorOverviewConfig.IconColumnWidth < 15 or SectorOverviewConfig.IconColumnWidth > 50 then
                SectorOverviewConfig.IconColumnWidth = math.max(15, math.min(50, SectorOverviewConfig.IconColumnWidth))
                if not sectorOverview_iconColumnWidthBox.isTypingActive then
                    sectorOverview_iconColumnWidthBox.text = SectorOverviewConfig.IconColumnWidth
                end
            end
            SectorOverviewConfig.RowHeight = tonumber(sectorOverview_rowHeightBox.text) or 25
            if SectorOverviewConfig.RowHeight < 15 or SectorOverviewConfig.RowHeight > 50 then
                SectorOverviewConfig.RowHeight = math.max(15, math.min(50, SectorOverviewConfig.RowHeight))
                if not sectorOverview_rowHeightBox.isTypingActive then
                    sectorOverview_rowHeightBox.text = SectorOverviewConfig.RowHeight
                end
            end
            SectorOverviewConfig.IconsPerRow = tonumber(sectorOverview_iconsPerRowBox.text) or 11
            if SectorOverviewConfig.IconsPerRow < 5 or SectorOverviewConfig.IconsPerRow > 20 then
                SectorOverviewConfig.IconsPerRow = math.max(5, math.min(20, SectorOverviewConfig.IconsPerRow))
                if not sectorOverview_iconsPerRowBox.isTypingActive then
                    sectorOverview_iconsPerRowBox.text = SectorOverviewConfig.IconsPerRow
                end
            end
            
            -- Tab toggle settings
            SectorOverviewConfig.NotifyAboutEnemies = sectorOverview_notifyAboutEnemiesCheckBox.checked
            SectorOverviewConfig.ShowNPCNames = sectorOverview_showNPCNamesCheckBox.checked
            SectorOverviewConfig.ShowBulletinBoardsTab = sectorOverview_showBulletinBoardsTabCheckBox.checked
            SectorOverviewConfig.ShowWreckages = sectorOverview_showWreckagesCheckBox.checked
            SectorOverviewConfig.ShowGoodsTab = sectorOverview_showGoodsTabCheckBox.checked
            SectorOverviewConfig.ShowCrewTab = sectorOverview_showCrewTabCheckBox.checked
            SectorOverviewConfig.ToggleButton = sectorOverview_toggleBtnComboBox.selectedValue
            SectorOverviewConfig.PrevTabButton = sectorOverview_prevTabBtnComboBox.selectedValue
            SectorOverviewConfig.NextTabButton = sectorOverview_nextTabBtnComboBox.selectedValue

            Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)

            -- Apply window resize when settings change
            self.updateWindowSize()

            invokeServerFunction("sectorOverview_setNotifyAboutEnemies", SectorOverviewConfig.NotifyAboutEnemies)
        end
    end
end

function SectorShipOverview.updateWindowSize()
    if not self.window or not SectorOverviewConfig then return end
    
    local newSize = vec2(SectorOverviewConfig.WindowWidth or 320, SectorOverviewConfig.WindowHeight or 400)
    self.window.size = newSize
    
    -- Update tabbed window size (account for margins)
    if sectorOverview_tabbedWindow then
        sectorOverview_tabbedWindow.size = newSize - vec2(20, 20)
    end
    
    -- Update all tab list sizes
    if sectorOverview_stationList then
        sectorOverview_stationList.size = sectorOverview_stationTab.size
        sectorOverview_stationList:setColumnWidth(2, sectorOverview_stationList.width - 85)
    end
    if sectorOverview_shipList then
        sectorOverview_shipList.size = sectorOverview_shipTab.size
        sectorOverview_shipList:setColumnWidth(2, sectorOverview_shipList.width - 85)
    end
    if sectorOverview_gateList then
        sectorOverview_gateList.size = sectorOverview_gateTab.size
        sectorOverview_gateList:setColumnWidth(1, sectorOverview_gateList.width - 35)
    end
    if sectorOverview_playerList then
        sectorOverview_playerList.size = sectorOverview_playerTab.size
    end
end

-- CALLABLE --

function SectorShipOverview.sectorOverview_receiveServerConfig(serverConfig)
    if not serverConfig.AllowPlayerTracking then
        sectorOverview_tabbedWindow:deactivateTab(sectorOverview_playerTab)
    end
end

function SectorShipOverview.sectorOverview_enemySpotted(entityIndex, secondAttempt)
    local entity = Sector():getEntity(entityIndex)
    if not entity or not valid(entity) then
        if not secondAttempt then -- try even later
            deferredCallback(1, "sectorOverview_enemySpotted", entityIndex, true)
        end
        return
    end
    local factionName = "?"
    if Galaxy():factionExists(entity.factionIndex) then
        factionName = Faction(entity.factionIndex).translatedName
    end
    displayChatMessage(string.format("Detected enemy ship '%s' (%s) in the sector!"%_t, entity.name, factionName), "Sector Overview"%_t, 2)
end

function SectorShipOverview.sectorOverview_receivePlayerCoord(data)
    for index, coord in pairs(data) do
        sectorOverview_playerCoords[index] = coord
    end
    self.sectorOverview_refreshPlayerList()
end

-- FUNCTIONS --

function SectorShipOverview.refreshList() -- overridden
    local craft = getPlayerCraft()
    if not craft then return end

    local white = ColorRGB(1, 1, 1)
    local player = Player()
    local ownerFaction = craft.allianceOwned and Alliance() or player
    local selectionGroups = sectorOverview_GT135 and self.getSelectionGroupTable(player) or nil
    local renderer = UIRenderer()
    local entities = {}

    local sort = function(entities)
        table.sort(entities, function(a, b)
            if a.entity.factionIndex == b.entity.factionIndex then
                if a.name == b.name then
                    return a.entity.id.string < b.entity.id.string
                end
                return a.name < b.name
            end
            return (a.entity.factionIndex or 0) < (b.entity.factionIndex or 0)
        end)
    end

    if sectorOverview_stationTab.isActiveTab then -- stations

        for _, entity in ipairs({Sector():getEntitiesByType(EntityType.Station)}) do
            entities[#entities+1] = {entity = entity, name = self.sectorOverview_getEntityName(entity)}
        end
        for _, entity in ipairs({Sector():getEntitiesByScript("data/scripts/entity/sellobject.lua")}) do
            entities[#entities+1] = {entity = entity, name = self.sectorOverview_getEntityName(entity, "Claimed Asteroid"%_t), isClaimed = true}
        end
        
        -- Add wreckages if enabled
        if SectorOverviewConfig.ShowWreckages then
            for _, entity in ipairs({Sector():getEntitiesByType(EntityType.Wreckage)}) do
                local name = "Wreckage"%_t
                if entity.translatedTitle and entity.translatedTitle ~= "" then
                    name = entity.translatedTitle
                elseif entity.title and entity.title ~= "" then
                    name = entity.title
                end
                entities[#entities+1] = {entity = entity, name = name, isWreckage = true}
            end
        end
        sort(entities)
        local selectedValue = sectorOverview_stationList.selectedValue
        local scrollPosition = sectorOverview_stationList.scrollPosition
        sectorOverview_stationList:clear()
        for _, pair in ipairs(entities) do
            local entryColor
            if sectorOverview_GT135 then
                entryColor = renderer:getEntityTargeterColor(pair.entity)
            else
                entryColor = ownerFaction:getRelation(pair.entity.factionIndex).color -- Relation object
            end
            local icon = ""
            local secondaryIcon = ""
            local secondaryIconColor = white
            local iconComponent = EntityIcon(pair.entity)
            if iconComponent then
                icon = iconComponent.icon
                secondaryIcon = iconComponent.secondaryIcon
                secondaryIconColor = iconComponent.secondaryIconColor
            end
            if pair.isClaimed then
                icon = "data/textures/icons/pixel/credits.png"
            elseif pair.isWreckage then
                icon = "data/textures/icons/pixel/wreckage.png"
            elseif icon == "" then
                icon = "data/textures/icons/sectoroverview/pixel/diamond.png"
            end
            local group = sectorOverview_GT135 and " "..self.getGroupString(selectionGroups, pair.entity.factionIndex, pair.entity.name) or ""
            sectorOverview_stationList:addRow(pair.entity.id.string)
            sectorOverview_stationList:setEntry(0, sectorOverview_stationList.rows - 1, icon, false, false, self.sectorOverview_getOwnershipTypeColor(pair.entity))
            sectorOverview_stationList:setEntry(1, sectorOverview_stationList.rows - 1, secondaryIcon, false, false, secondaryIconColor)
            sectorOverview_stationList:setEntry(2, sectorOverview_stationList.rows - 1, pair.name, false, false, entryColor)
            sectorOverview_stationList:setEntry(3, sectorOverview_stationList.rows - 1, group, false, false, white)
            sectorOverview_stationList:setEntryType(0, sectorOverview_stationList.rows - 1, 3)
            sectorOverview_stationList:setEntryType(1, sectorOverview_stationList.rows - 1, 3)
        end
        sectorOverview_stationList:selectValueNoCallback(selectedValue)
        sectorOverview_stationList.scrollPosition = scrollPosition

    elseif sectorOverview_shipTab.isActiveTab then -- ships

        for _, entity in ipairs({Sector():getEntitiesByComponents(ComponentType.Engine)}) do
            if entity.isShip or entity.isDrone then
                entities[#entities+1] = {entity = entity, name = self.sectorOverview_getEntityName(entity)}
            end
        end
        
        -- Add wreckages if enabled
        if SectorOverviewConfig.ShowWreckages then
            for _, entity in ipairs({Sector():getEntitiesByType(EntityType.Wreckage)}) do
                local name = "Wreckage"%_t
                if entity.translatedTitle and entity.translatedTitle ~= "" then
                    name = entity.translatedTitle
                elseif entity.title and entity.title ~= "" then
                    name = entity.title
                end
                entities[#entities+1] = {entity = entity, name = name, isWreckage = true}
            end
        end
        sort(entities)
        local selectedValue = sectorOverview_shipList.selectedValue
        local scrollPosition = sectorOverview_shipList.scrollPosition
        sectorOverview_shipList:clear()
        for _, pair in ipairs(entities) do
            local entryColor
            if sectorOverview_GT135 then
                entryColor = renderer:getEntityTargeterColor(pair.entity)
            else
                entryColor = ownerFaction:getRelation(pair.entity.factionIndex).color -- Relation object
            end
            local icon = ""
            local secondaryIcon = ""
            local secondaryIconColor = white
            local iconComponent = EntityIcon(pair.entity)
            if iconComponent then
                if sectorOverview_GT135 and player.craftIndex == pair.entity.id then
                    icon = "data/textures/icons/pixel/player.png"
                else
                    icon = iconComponent.icon
                end
                secondaryIcon = iconComponent.secondaryIcon
                secondaryIconColor = iconComponent.secondaryIconColor
            end
            if pair.isWreckage then
                icon = "data/textures/icons/pixel/wreckage.png"
            elseif icon == "" then
                icon = "data/textures/icons/sectoroverview/pixel/diamond.png"
            end
            local group = sectorOverview_GT135 and " "..self.getGroupString(selectionGroups, pair.entity.factionIndex, pair.entity.name) or ""
            sectorOverview_shipList:addRow(pair.entity.id.string)
            sectorOverview_shipList:setEntry(0, sectorOverview_shipList.rows - 1, icon, false, false, self.sectorOverview_getOwnershipTypeColor(pair.entity))
            sectorOverview_shipList:setEntry(1, sectorOverview_shipList.rows - 1, secondaryIcon, false, false, secondaryIconColor)
            sectorOverview_shipList:setEntry(2, sectorOverview_shipList.rows - 1, pair.name, false, false, entryColor)
            sectorOverview_shipList:setEntry(3, sectorOverview_shipList.rows - 1, group, false, false, white)
            sectorOverview_shipList:setEntryType(0, sectorOverview_shipList.rows - 1, 3)
            sectorOverview_shipList:setEntryType(1, sectorOverview_shipList.rows - 1, 3)
        end
        sectorOverview_shipList:selectValueNoCallback(selectedValue)
        sectorOverview_shipList.scrollPosition = scrollPosition

    elseif sectorOverview_gateTab.isActiveTab then -- gates

        for _, entity in ipairs({Sector():getEntitiesByComponents(ComponentType.WormHole)}) do
            local isGate = entity:hasComponent(ComponentType.Plan)
            entities[#entities+1] = {
              entity = entity,
              name = isGate and self.sectorOverview_getEntityName(entity) or "Wormhole"%_t,
              isGate = isGate
            }
        end
        sort(entities)
        local selectedValue = sectorOverview_gateList.selectedValue
        local scrollPosition = sectorOverview_gateList.scrollPosition
        sectorOverview_gateList:clear()
        for _, pair in ipairs(entities) do
            local icon = ""
            local ownershipColor = white
            local entryColor = white
            if pair.isGate then
                ownershipColor = self.sectorOverview_getOwnershipTypeColor(pair.entity)
                if sectorOverview_GT135 then
                    entryColor = renderer:getEntityTargeterColor(pair.entity)
                else
                    entryColor = ownerFaction:getRelation(pair.entity.factionIndex).color
                end
                local iconComponent = EntityIcon(pair.entity)
                if iconComponent then
                    icon = iconComponent.icon
                end
            else
                icon = "data/textures/icons/sectoroverview/pixel/spiral.png"
            end
            sectorOverview_gateList:addRow(pair.entity.id.string)
            sectorOverview_gateList:setEntry(0, sectorOverview_gateList.rows - 1, icon, false, false, ownershipColor)
            sectorOverview_gateList:setEntry(1, sectorOverview_gateList.rows - 1, pair.name, false, false, entryColor)
            sectorOverview_gateList:setEntryType(0, sectorOverview_gateList.rows - 1, 3)
        end
        sectorOverview_gateList:selectValueNoCallback(selectedValue)
        sectorOverview_gateList.scrollPosition = scrollPosition

    end
end

if sectorOverview_GT135 then

local doubleClick = {}
function SectorShipOverview.onEntrySelected(index, value) -- overridden
    if not value or value == "" then return end

    local time = appTime()
    if doubleClick.value ~= value then
        doubleClick.value = value
        doubleClick.time = time
    else
        if time - doubleClick.time < 0.5 then
            if Player().state == PlayerStateType.Strategy then
                StrategyState():centerCameraOnSelection()
            end
        else
            doubleClick.time = time
        end
    end

    local player = Player()

    if player.state == PlayerStateType.Strategy then
        if Keyboard().controlPressed then
            StrategyState():toggleSelect(value)
            return
        end
        StrategyState():clearSelection()
    end
    player.selectedObject = Entity(value)
end

end

function SectorShipOverview.sectorOverview_toggleWindow()
    if self.window.visible then
        self.hide()
    else
        self.show()
    end
end

function SectorShipOverview.sectorOverview_getOwnershipTypeColor(entity)
    local player = Player()
    local factionIndex = entity.factionIndex or -1
    if not entity.aiOwned then
        if factionIndex == player.index then
            return ColorInt(0xff4CE34B)
        elseif player.allianceIndex and factionIndex == player.allianceIndex then
            return ColorInt(0xffFF00FF)
        elseif entity.playerOwned then
            return ColorInt(0xffFCFF3A)
        else
            return ColorInt(0xff4B9EF2)
        end
    end
    return ColorRGB(1, 1, 1)
end

function SectorShipOverview.sectorOverview_getEntityName(entity, custom)
    local entryName = ""
    if custom then
        entryName = custom
    else
        if entity.translatedTitle and entity.translatedTitle ~= "" then
            entryName = entity.translatedTitle
        elseif entity.title and entity.title ~= "" then
            entryName = (entity.title % entity:getTitleArguments())
        end
        if entity.name and (entryName == "" or not entity.aiOwned or SectorOverviewConfig.ShowNPCNames) then
            if entryName == "" then
                entryName = entity.name
            else
                entryName = entryName.." - "..entity.name
            end
        end
    end
    if entryName == "" and not entity.name then
        entryName = "<No Name>"%_t
    end
    if Galaxy():factionExists(entity.factionIndex) then
        entryName = entryName .. " | " .. Faction(entity.factionIndex).translatedName
    else
        entryName = entryName .. " | " .. ("Not owned"%_t)
    end
    return entryName
end

function SectorShipOverview.sectorOverview_refreshPlayerList(updateAllCoordinates)
    local sorted = {}
    for name, index in pairs(sectorOverview_playerAddedList) do
        sorted[#sorted+1] = name
    end
    table.sort(sorted)

    local trackedPlayerIndexes = {}
    local white = ColorRGB(1, 1, 1)

    sectorOverview_playerList:clear()
    for _, name in ipairs(sorted) do
        local index = sectorOverview_playerAddedList[name]
        local coord = sectorOverview_playerCoords[index]
        sectorOverview_playerList:addRow(name)
        if coord then
            sectorOverview_playerList:setEntry(0, sectorOverview_playerList.rows-1, string.format("%s (%i:%i)", name, coord[1], coord[2]), false, false, white)
        else
            sectorOverview_playerList:setEntry(0, sectorOverview_playerList.rows-1, name, false, false, white)
        end
        
        trackedPlayerIndexes[#trackedPlayerIndexes+1] = index
    end

    if updateAllCoordinates and #trackedPlayerIndexes > 0 then
        invokeServerFunction("sectorOverview_sendPlayersCoord", trackedPlayerIndexes)
    end
end

-- CALLBACKS --

function SectorShipOverview.onPlayerStateChanged(new, old) -- overridden
    local isOldNormal = old == PlayerStateType.Fly or old == PlayerStateType.Interact
    local isNewNormal = new == PlayerStateType.Fly or new == PlayerStateType.Interact
    
    if isOldNormal and not isNewNormal then -- save status
        sectorOverview_isVisible = self.window.visible
        if new == PlayerStateType.Strategy then -- always show
            self.show()
        else -- always hide in build mode
            self.hide()
        end
    elseif not isOldNormal and isNewNormal then
        if sectorOverview_isVisible then
            self.show()
        else
            self.hide()
        end
    end
end

function SectorShipOverview.sectorOverview_onPlayerTabSelected(tab)
    -- fill player combo box
    sectorOverview_playerCombo:clear()
    local playerName = Player().name
    for index, name in pairs(Galaxy():getPlayerNames()) do
        if playerName ~= name then
            sectorOverview_playerCombo:addEntry(index, name)
        end
    end

    self.sectorOverview_refreshPlayerList(true)
end

-- Custom refresh functions for new tabs
function SectorShipOverview.sectorOverview_refreshGoodsList()
    if not sectorOverview_goodsList then return end
    
    local lists = self.collectEntities()
    local stationList = lists[1]
    local player = Player()
    
    local scrollPosition = sectorOverview_goodsList.scrollPosition
    sectorOverview_goodsList:clear()
    
    local white = ColorRGB(1, 1, 1)
    local buyColor = ColorRGB(1, 0.8, 0.7)
    local sellColor = ColorRGB(0.8, 0.8, 1)
    
    local renderer = UIRenderer()
    
    for _, entry in pairs(stationList.entries) do
        local entity = entry.entity
        local color = renderer:getEntityTargeterColor(entity)
        
        local sellable, buyable = TradingUtility.getBuyableAndSellableGoods(entity, nil, nil, player)
        
        local soldGoods = {}
        for _, good in pairs(buyable) do
            table.insert(soldGoods, good.good)
        end
        
        local goodsInDemand = {}
        for _, good in pairs(sellable) do
            table.insert(goodsInDemand, good.good)
        end
        
        if #soldGoods > 0 or #goodsInDemand > 0 then
            sectorOverview_goodsList:addRow(entity.id.string)
            sectorOverview_goodsList:setEntry(0, sectorOverview_goodsList.rows - 1, entry.icon, false, false, white, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            sectorOverview_goodsList:setEntry(1, sectorOverview_goodsList.rows - 1, entry.name, false, false, color, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            sectorOverview_goodsList:setEntry(11, sectorOverview_goodsList.rows - 1, entry.group, false, false, white, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            sectorOverview_goodsList:setEntryType(0, sectorOverview_goodsList.rows - 1, ListBoxEntryType.PixelIcon)
            
            local supplyIcons = {}
            local supplyTooltips = {}
            for _, good in pairs(soldGoods) do
                table.insert(supplyTooltips, good.name % _t)
                table.insert(supplyIcons, good.icon)
            end
            
            local demandIcons = {}
            local demandTooltips = {}
            for _, good in pairs(goodsInDemand) do
                table.insert(demandTooltips, good.name % _t)
                table.insert(demandIcons, good.icon)
            end
            
            sectorOverview_goodsList:addRow(entity.id.string)
            
            local length = #supplyIcons
            if #demandIcons > length then
                length = #demandIcons
            end
            
            local column = 1
            local iconsPerRow = SectorOverviewConfig.IconsPerRow or 11
            
            for i = 1, length do
                local demandColumn = column + 6
                if i < #supplyIcons + 1 then
                    sectorOverview_goodsList:setEntry(column, sectorOverview_goodsList.rows - 1, supplyIcons[i], false, false, sellColor, 0)
                    sectorOverview_goodsList:setEntryType(column, sectorOverview_goodsList.rows - 1, ListBoxEntryType.Icon)
                    sectorOverview_goodsList:setEntryTooltip(column, sectorOverview_goodsList.rows - 1, supplyTooltips[i])
                end
                
                if i < #demandIcons + 1 then
                    sectorOverview_goodsList:setEntry(demandColumn, sectorOverview_goodsList.rows - 1, demandIcons[i], false, false, buyColor, 0)
                    sectorOverview_goodsList:setEntryType(demandColumn, sectorOverview_goodsList.rows - 1, ListBoxEntryType.Icon)
                    sectorOverview_goodsList:setEntryTooltip(demandColumn, sectorOverview_goodsList.rows - 1, demandTooltips[i])
                end
                
                column = column + 1
                
                if i % math.floor(iconsPerRow/2) == 0 and length > i then
                    sectorOverview_goodsList:addRow(entity.id.string)
                    column = 1
                end
            end
        end
    end
    
    if player.selectedObject then
        sectorOverview_goodsList:selectValueNoCallback(player.selectedObject.string)
    end
    sectorOverview_goodsList.scrollPosition = scrollPosition
end

function SectorShipOverview.sectorOverview_refreshCrewList()
    if not sectorOverview_crewList then return end
    
    local lists = self.collectEntities()
    local stationList = lists[1]
    local player = Player()
    
    local scrollPosition = sectorOverview_crewList.scrollPosition
    sectorOverview_crewList:clear()
    
    local white = ColorRGB(1, 1, 1)
    local renderer = UIRenderer()
    
    local simplifiedIcons = {}
    simplifiedIcons[CaptainUtility.ClassType.Commodore] = {path = "data/textures/icons/captain-commodore.png", color = ColorRGB(0, 0.74, 0.74)}
    simplifiedIcons[CaptainUtility.ClassType.Smuggler] = {path = "data/textures/icons/captain-smuggler.png", color = ColorRGB(0.78, 0.03, 0.75)}
    simplifiedIcons[CaptainUtility.ClassType.Merchant] = {path = "data/textures/icons/captain-merchant.png", color = ColorRGB(0.5, 0.8, 0)}
    simplifiedIcons[CaptainUtility.ClassType.Miner] = {path = "data/textures/icons/captain-miner.png", color = ColorRGB(0.5, 0.8, 0)}
    simplifiedIcons[CaptainUtility.ClassType.Scavenger] = {path = "data/textures/icons/captain-scavenger.png", color = ColorRGB(0.1, 0.5, 1)}
    simplifiedIcons[CaptainUtility.ClassType.Explorer] = {path = "data/textures/icons/captain-explorer.png", color = ColorRGB(1, 0.88, 0.04)}
    simplifiedIcons[CaptainUtility.ClassType.Daredevil] = {path = "data/textures/icons/captain-daredevil.png", color = ColorRGB(0.9, 0.1, 0.1)}
    simplifiedIcons[CaptainUtility.ClassType.Scientist] = {path = "data/textures/icons/captain-scientist.png", color = ColorRGB(1, 0.47, 0)}
    simplifiedIcons[CaptainUtility.ClassType.Hunter] = {path = "data/textures/icons/captain-hunter.png", color = ColorRGB(1, 0.43, 0.77)}
    
    local classProperties = CaptainUtility.ClassProperties()
    
    for _, entry in pairs(stationList.entries) do
        local entity = entry.entity
        local color = renderer:getEntityTargeterColor(entity)
        
        if not entity:hasScript("data/scripts/entity/crewboard.lua") then goto continue end
        
        local ok, crew, captain = entity:invokeFunction("data/scripts/entity/crewboard.lua", "getAvailableCrewAndCaptain")
        
        if not crew and not captain then goto continue end
        
        local captainIcons = {}
        local captainTooltip = ""
        
        if captain then
            if captain.primaryClass == 0 then
                table.insert(captainIcons, {path = "data/textures/icons/captain-noclass.png", color = ColorRGB(1, 1, 1)})
                captainTooltip = "Captain [no class"%_t
            else
                table.insert(captainIcons, simplifiedIcons[captain.primaryClass])
                captainTooltip = "Captain ["%_t .. classProperties[captain.primaryClass].displayName % _t
            end
            
            if captain.secondaryClass and captain.secondaryClass ~= 0 then
                table.insert(captainIcons, simplifiedIcons[captain.secondaryClass])
                captainTooltip = captainTooltip .. ", " .. classProperties[captain.secondaryClass].displayName % _t
            end
            
            captainTooltip = captainTooltip .. "]"
        end
        
        local icons = {}
        local tooltips = {}
        
        for _, crewMember in pairs(crew) do
            local professionNumber = crewMember.profession
            local profession = CrewProfession(professionNumber)
            table.insert(icons, profession.icon)
            table.insert(tooltips, profession:name(profession) % _t)
        end
        
        if captain or #icons > 0 then
            sectorOverview_crewList:addRow(entity.id.string)
            sectorOverview_crewList:setEntry(0, sectorOverview_crewList.rows - 1, entry.icon, false, false, white, sectorOverview_crewList.width - 2 * self.iconColumnWidth)
            sectorOverview_crewList:setEntryType(0, sectorOverview_crewList.rows - 1, ListBoxEntryType.PixelIcon)
            
            sectorOverview_crewList:setEntry(1, sectorOverview_crewList.rows - 1, entry.name, false, false, color, sectorOverview_crewList.width - 2 * self.iconColumnWidth)
            sectorOverview_crewList:setEntryType(1, sectorOverview_crewList.rows - 1, ListBoxEntryType.Text)
            
            sectorOverview_crewList:setEntry(11, sectorOverview_crewList.rows - 1, entry.group, false, false, white, sectorOverview_crewList.width - 2 * self.iconColumnWidth)
            
            sectorOverview_crewList:addRow(entity.id.string)
            for i = 1, #icons do
                if i == 1 then
                    if captain then
                        sectorOverview_crewList:setEntry(i, sectorOverview_crewList.rows - 1, captainIcons[i].path, false, false, captainIcons[i].color, 0)
                    else
                        sectorOverview_crewList:setEntry(i, sectorOverview_crewList.rows - 1, "data/textures/icons/nothing.png", false, false, white, 0)
                    end
                    
                    sectorOverview_crewList:setEntryType(i, sectorOverview_crewList.rows - 1, ListBoxEntryType.Icon)
                    sectorOverview_crewList:setEntryTooltip(i, sectorOverview_crewList.rows - 1, captainTooltip)
                else
                    sectorOverview_crewList:setEntry(i, sectorOverview_crewList.rows - 1, icons[i], false, false, white, 0)
                    sectorOverview_crewList:setEntryType(i, sectorOverview_crewList.rows - 1, ListBoxEntryType.Icon)
                    sectorOverview_crewList:setEntryTooltip(i, sectorOverview_crewList.rows - 1, tooltips[i])
                end
            end
        end
        
        ::continue::
    end
    
    if player.selectedObject then
        sectorOverview_crewList:selectValueNoCallback(player.selectedObject.string)
    end
    sectorOverview_crewList.scrollPosition = scrollPosition
end

function SectorShipOverview.sectorOverview_refreshMissionList()
    if not sectorOverview_missionList then 
        print("DEBUG: sectorOverview_missionList is nil")
        return 
    end
    
    local lists = self.collectEntities()
    local stationList = lists[1]
    local player = Player()
    
    print("DEBUG: Mission refresh - Found " .. #stationList.entries .. " stations")
    
    local scrollPosition = sectorOverview_missionList.scrollPosition
    sectorOverview_missionList:clear()
    
    local white = ColorRGB(1, 1, 1)
    local renderer = UIRenderer()
    
    local stationsProcessed = 0
    local stationsWithMissions = 0
    
    for _, entry in pairs(stationList.entries) do
        local entity = entry.entity
        local color = renderer:getEntityTargeterColor(entity)
        stationsProcessed = stationsProcessed + 1
        
        local missions = {}
        local hasRiftScript = entity:hasScript("dlc/rift/entity/riftresearchcenter.lua")
        local hasBulletinScript = entity:hasScript("data/scripts/entity/bulletinboard.lua")
        
        print("DEBUG: Station " .. (entity.name or "Unknown") .. " - Rift:" .. tostring(hasRiftScript) .. " Bulletin:" .. tostring(hasBulletinScript))
        
        if hasRiftScript and player.ownsIntoTheRiftDLC then
            _, missions = entity:invokeFunction("dlc/rift/entity/riftresearchcenter.lua", "getDisplayedBulletins")
            print("DEBUG: Rift research center missions: " .. (missions and #missions or "nil"))
        elseif hasBulletinScript then
            _, missions = entity:invokeFunction("data/scripts/entity/bulletinboard.lua", "getDisplayedBulletins")
            print("DEBUG: Bulletin board missions: " .. (missions and #missions or "nil"))
        else
            print("DEBUG: Station has no mission scripts")
            goto continue
        end
        
        if not missions then 
            print("DEBUG: No missions returned from station")
            goto continue 
        end
        
        stationsWithMissions = stationsWithMissions + 1
        local icons = {}
        local tooltips = {}
        for _, mission in pairs(missions) do
            if mission.icon then
                table.insert(icons, mission.icon)
            else
                table.insert(icons, "data/textures/icons/basic-mission-marker.png")
            end
            
            table.insert(tooltips, mission.brief % _t % mission.formatArguments)
        end
        
        print("DEBUG: Station missions - Icons: " .. #icons .. ", Tooltips: " .. #tooltips)
        
        if #tooltips > 0 then
            sectorOverview_missionList:addRow(entity.id.string)
            sectorOverview_missionList:setEntry(0, sectorOverview_missionList.rows - 1, entry.icon, false, false, white, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            sectorOverview_missionList:setEntry(1, sectorOverview_missionList.rows - 1, entry.name, false, false, color, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            sectorOverview_missionList:setEntry(11, sectorOverview_missionList.rows - 1, entry.group, false, false, white, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            sectorOverview_missionList:setEntryType(0, sectorOverview_missionList.rows - 1, ListBoxEntryType.PixelIcon)
            
            sectorOverview_missionList:addRow(entity.id.string)
            for i = 1, #icons do
                sectorOverview_missionList:setEntry(i, sectorOverview_missionList.rows - 1, icons[i], false, false, missions[i].iconColor or white, 0)
                sectorOverview_missionList:setEntryType(i, sectorOverview_missionList.rows - 1, ListBoxEntryType.Icon)
                sectorOverview_missionList:setEntryTooltip(i, sectorOverview_missionList.rows - 1, tooltips[i])
            end
            print("DEBUG: Added station to mission list with " .. #icons .. " mission icons")
        end
        
        ::continue::
    end
    
    print("DEBUG: Mission refresh complete - Processed: " .. stationsProcessed .. ", With missions: " .. stationsWithMissions .. ", Total rows: " .. sectorOverview_missionList.rows)
    
    if player.selectedObject then
        sectorOverview_missionList:selectValueNoCallback(player.selectedObject.string)
    end
    sectorOverview_missionList.scrollPosition = scrollPosition
end

function SectorShipOverview.sectorOverview_onShowPlayerPressed()
    local name = sectorOverview_playerList.selectedValue
    if name then
        local index = sectorOverview_playerAddedList[name]
        if index then
            local coords = sectorOverview_playerCoords[index]
            if coords then
                GalaxyMap():show(coords[1], coords[2])
            end
        end
    end
end

function SectorShipOverview.sectorOverview_onAddPlayerTracking()
    local name = sectorOverview_playerCombo.selectedEntry
    if name ~= "" and not sectorOverview_playerAddedList[name] then
        sectorOverview_playerAddedList[name] = sectorOverview_playerCombo.selectedValue
        self.sectorOverview_refreshPlayerList()
        invokeServerFunction("sectorOverview_sendPlayersCoord", sectorOverview_playerCombo.selectedValue)
    end
end

function SectorShipOverview.sectorOverview_onRemovePlayerTracking()
    local name = sectorOverview_playerList.selectedValue
    if name then
        local index = sectorOverview_playerAddedList[name]
        if index then
            sectorOverview_playerAddedList[name] = nil
            sectorOverview_playerCoords[index] = nil
            self.sectorOverview_refreshPlayerList()
        end
    end
end

function SectorShipOverview.sectorOverview_onSettingsModified()
    sectorOverview_settingsModified = 1
end

function SectorShipOverview.sectorOverview_onResetBtnPressed()
    SectorOverviewConfig.WindowWidth = sectorOverview_configOptions.WindowWidth[1]
    sectorOverview_windowWidthBox.text = SectorOverviewConfig.WindowWidth

    SectorOverviewConfig.WindowHeight = sectorOverview_configOptions.WindowHeight[1]
    sectorOverview_windowHeightBox.text = SectorOverviewConfig.WindowHeight

    -- Content sizing resets
    SectorOverviewConfig.IconColumnWidth = sectorOverview_configOptions.IconColumnWidth[1]
    sectorOverview_iconColumnWidthBox.text = SectorOverviewConfig.IconColumnWidth

    SectorOverviewConfig.RowHeight = sectorOverview_configOptions.RowHeight[1]
    sectorOverview_rowHeightBox.text = SectorOverviewConfig.RowHeight

    SectorOverviewConfig.IconsPerRow = sectorOverview_configOptions.IconsPerRow[1]
    sectorOverview_iconsPerRowBox.text = SectorOverviewConfig.IconsPerRow

    -- Tab toggle resets
    SectorOverviewConfig.NotifyAboutEnemies = sectorOverview_configOptions.NotifyAboutEnemies[1]
    sectorOverview_notifyAboutEnemiesCheckBox:setCheckedNoCallback(SectorOverviewConfig.NotifyAboutEnemies)

    SectorOverviewConfig.ShowNPCNames = sectorOverview_configOptions.ShowNPCNames[1]
    sectorOverview_showNPCNamesCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowNPCNames)

    SectorOverviewConfig.ShowBulletinBoardsTab = sectorOverview_configOptions.ShowBulletinBoardsTab[1]
    sectorOverview_showBulletinBoardsTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowBulletinBoardsTab)

    SectorOverviewConfig.ShowWreckages = sectorOverview_configOptions.ShowWreckages[1]
    sectorOverview_showWreckagesCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowWreckages)

    SectorOverviewConfig.ShowGoodsTab = sectorOverview_configOptions.ShowGoodsTab[1]
    sectorOverview_showGoodsTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowGoodsTab)

    SectorOverviewConfig.ShowCrewTab = sectorOverview_configOptions.ShowCrewTab[1]
    sectorOverview_showCrewTabCheckBox:setCheckedNoCallback(SectorOverviewConfig.ShowCrewTab)

    SectorOverviewConfig.ToggleButton = sectorOverview_configOptions.ToggleButton[1]
    sectorOverview_toggleBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.ToggleButton)

    SectorOverviewConfig.PrevTabButton = sectorOverview_configOptions.PrevTabButton[1]
    sectorOverview_prevTabBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.PrevTabButton)

    SectorOverviewConfig.NextTabButton = sectorOverview_configOptions.NextTabButton[1]
    sectorOverview_nextTabBtnComboBox:setSelectedValueNoCallback(SectorOverviewConfig.NextTabButton)

    Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)

    -- Apply window resize after reset
    self.updateWindowSize()

    invokeServerFunction("sectorOverview_setNotifyAboutEnemies", SectorOverviewConfig.NotifyAboutEnemies)
end


else -- onServer


-- PREDEFINED --

function SectorShipOverview.initialize()
    local configOptions = {
      ["_version"] = {"1.1", comment = "Config version. Don't touch."},
      ["AllowPlayerTracking"] = {true, comment = "If false, server will not reveal players coordinates (useful for PvP servers)."}
    }
    local isModified
    SectorOverviewConfig, isModified = Azimuth.loadConfig("SectorOverview", configOptions)
    if isModified then
        Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, configOptions)
    end

    Player():registerCallback("onSectorEntered", "sectorOverview_onSectorEntered")
end

-- CALLABLE --

function SectorShipOverview.sectorOverview_sendServerConfig()
    invokeClientFunction(Player(callingPlayer), "sectorOverview_receiveServerConfig", { AllowPlayerTracking = SectorOverviewConfig.AllowPlayerTracking })
end
callable(SectorShipOverview, "sectorOverview_sendServerConfig")

function SectorShipOverview.sectorOverview_setNotifyAboutEnemies(value)
    sectorOverview_notifyAboutEnemies = value
    self.sectorOverview_onSectorEntered()
end
callable(SectorShipOverview, "sectorOverview_setNotifyAboutEnemies")

function SectorShipOverview.sectorOverview_sendPlayersCoord(playerIndexes)
    local player = Player()
    if not SectorOverviewConfig.AllowPlayerTracking then
        player:sendChatMessage("", ChatMessageType.Error, "Server doesn't allow to track players."%_t)
        return
    end

    local typestr = type(playerIndexes)
    if typestr == "number" then
        playerIndexes = { playerIndexes }
    elseif typestr ~= "table" then
        return
    end

    local results = {}
    for _, v in ipairs(playerIndexes) do
        local otherPlayer = Player(v)
        if otherPlayer then
            results[v] = { otherPlayer:getSectorCoordinates() }
        else
            player:sendChatMessage("", ChatMessageType.Error, "Can't get coordinates, %s doesn't exist."%_t, otherPlayer.name)
        end
    end

    invokeClientFunction(player, "sectorOverview_receivePlayerCoord", results)
end
callable(SectorShipOverview, "sectorOverview_sendPlayersCoord")

-- CALLBACKS --

function SectorShipOverview.sectorOverview_onSectorEntered()
    if sectorOverview_notifyAboutEnemies then
        Sector():registerCallback("onEntityCreated", "sectorOverview_onEntityEntered")
        Sector():registerCallback("onEntityEntered", "sectorOverview_onEntityEntered")
    end
end

function SectorShipOverview.sectorOverview_onEntityEntered(entityIndex)
    if not sectorOverview_notifyAboutEnemies then return end

    local entity = Entity(entityIndex)
    if not entity.isShip or entity.isDrone or entity.aiOwned then return end

    local player = Player()
    if player:getRelationStatus(entity.factionIndex) == RelationStatus.War
      or (player.alliance and player.alliance:getRelationStatus(entity.factionIndex) == RelationStatus.War) then
        invokeClientFunction(player, "sectorOverview_enemySpotted", entityIndex)
    end
end


end