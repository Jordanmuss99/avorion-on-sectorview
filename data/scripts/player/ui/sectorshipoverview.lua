include("callable")
include("azimuthlib-uiproportionalsplitter")
local Azimuth = include("azimuthlib-basic")
local CustomTabbedWindow = include("azimuthlib-customtabbedwindow")
local ResizableWindow = include("resizablewindow")

-- ========================================
-- MOUSE HANDLING SYSTEM: POLLING-BASED
-- ========================================
-- CRITICAL: Player UI scripts cannot use global onMouseEvent function
-- The global onMouseEvent function is ONLY called in Entity scripts, NOT Player UI scripts
-- 
-- SOLUTION: Polling-based state change detection in updateClient (60 FPS)
-- - Mouse() state is polled every frame in updateClient()  
-- - State changes are detected by comparing current vs last frame state
-- - Press/release events are generated when buttonDown() transitions occur
-- - Events are forwarded to ResizableWindow.handlePlayerUIMouseEvent()
-- 
-- IMPLEMENTATION:
-- - Mouse state tracking initialized in SectorShipOverview.initialize()
-- - State change detection runs in SectorShipOverview.updateClient()
-- - Compatible with existing ResizableWindow event interface
-- - Debugging available via /run reportMousePollingStatus()
-- ========================================

-- Diagnostic function to test mouse polling system manually
-- Can be called from console: /run testMousePolling()
function testMousePolling()
    local mouse = Mouse()
    if not mouse then
        print("[SectorShipOverview] ERROR: Mouse() not available")
        return false
    end
    
    local pos = mouse.position
    local leftPressed = mouse:buttonPressed(MouseButton.Left)
    local leftDown = mouse:buttonDown(MouseButton.Left)
    
    print("[SectorShipOverview] Mouse polling test:")
    print("[SectorShipOverview]   Position: (" .. pos.x .. ", " .. pos.y .. ")")
    print("[SectorShipOverview]   Left Pressed: " .. tostring(leftPressed))
    print("[SectorShipOverview]   Left Down: " .. tostring(leftDown))
    
    return true
end

-- Comprehensive status report for mouse polling system
-- Can be called from console: /run reportMousePollingStatus()
function reportMousePollingStatus()
    print("[SectorShipOverview] *** MOUSE POLLING SYSTEM STATUS REPORT ***")
    
    -- Check ResizableWindow module
    if ResizableWindow then
        print("[SectorShipOverview] ✓ ResizableWindow: LOADED")
        if ResizableWindow.handlePlayerUIMouseEvent then
            print("[SectorShipOverview]   ✓ handlePlayerUIMouseEvent: AVAILABLE")
        else
            print("[SectorShipOverview]   ✗ handlePlayerUIMouseEvent: MISSING")
        end
        if ResizableWindow.handlePlayerUIUpdate then
            print("[SectorShipOverview]   ✓ handlePlayerUIUpdate: AVAILABLE")
        else
            print("[SectorShipOverview]   ✗ handlePlayerUIUpdate: MISSING")
        end
    else
        print("[SectorShipOverview] ✗ ResizableWindow: NOT LOADED")
    end
    
    -- Check Mouse() for polling
    local mouse = Mouse()
    if mouse then
        print("[SectorShipOverview] ✓ Mouse() polling: AVAILABLE")
        local pos = mouse.position
        local leftDown = mouse:buttonDown(MouseButton.Left)
        local rightDown = mouse:buttonDown(MouseButton.Right)
        print("[SectorShipOverview]   Current position: (" .. pos.x .. ", " .. pos.y .. ")")
        print("[SectorShipOverview]   Current state: leftDown=" .. tostring(leftDown) .. ", rightDown=" .. tostring(rightDown))
    else
        print("[SectorShipOverview] ✗ Mouse() polling: NOT AVAILABLE")
    end
    
    -- Check polling state tracking
    if SectorShipOverview._mouseState then
        print("[SectorShipOverview] ✓ Mouse State Tracking: ACTIVE")
        local state = SectorShipOverview._mouseState
        print("[SectorShipOverview]   Initialized: " .. tostring(state.initialized))
        print("[SectorShipOverview]   Last Position: (" .. (state.lastPosition.x or 0) .. ", " .. (state.lastPosition.y or 0) .. ")")
        print("[SectorShipOverview]   Last Left Down: " .. tostring(state.lastLeftDown))
        print("[SectorShipOverview]   Events Generated: " .. (state.eventsGenerated or 0))
    else
        print("[SectorShipOverview] ✗ Mouse State Tracking: NOT INITIALIZED")
    end
    
    -- Check window status
    if sectorOverview_tabbedWindow then
        print("[SectorShipOverview] ✓ UI Window: CREATED")
        if sectorOverview_tabbedWindow._config and sectorOverview_tabbedWindow._config.resizable then
            print("[SectorShipOverview]   ✓ Resize enabled: " .. tostring(sectorOverview_tabbedWindow._config.resizable))
        end
    else
        print("[SectorShipOverview] ✗ UI Window: NOT CREATED")
    end
    
    print("[SectorShipOverview] *** End of status report ***")
    print("[SectorShipOverview] To test mouse polling manually: /run testMousePolling()")
end

local SectorOverviewConfig -- client/server
local sectorOverview_notifyAboutEnemies -- server
local sectorOverview_configOptions, sectorOverview_isVisible, sectorOverview_refreshCounter, sectorOverview_settingsModified, sectorOverview_playerAddedList, sectorOverview_playerCoords, sectorOverview_GT135 -- client
local sectorOverview_tabbedWindow, sectorOverview_stationTab, sectorOverview_stationList, sectorOverview_shipTab, sectorOverview_shipList, sectorOverview_gateTab, sectorOverview_gateList, sectorOverview_playerTab, sectorOverview_playerList, sectorOverview_playerCombo, sectorOverview_windowWidthBox, sectorOverview_windowHeightBox, sectorOverview_notifyAboutEnemiesCheckBox, sectorOverview_showNPCNamesCheckBox, sectorOverview_toggleBtnComboBox, sectorOverview_prevTabBtnComboBox, sectorOverview_nextTabBtnComboBox -- client UI
local sectorOverview_iconColumnWidthBox, sectorOverview_rowHeightBox, sectorOverview_iconsPerRowBox, sectorOverview_showBulletinBoardsTabCheckBox, sectorOverview_showWreckagesCheckBox, sectorOverview_showGoodsTabCheckBox, sectorOverview_showCrewTabCheckBox -- new UI controls
local sectorOverview_enableResizeCheckBox, sectorOverview_constrainToScreenCheckBox, sectorOverview_snapToSizeCheckBox, sectorOverview_minWindowWidthBox, sectorOverview_minWindowHeightBox, sectorOverview_maxWindowWidthBox, sectorOverview_maxWindowHeightBox -- resize UI controls
local sectorOverview_goodsTab, sectorOverview_goodsList, sectorOverview_crewTab, sectorOverview_crewList, sectorOverview_missionTab, sectorOverview_missionList -- additional tabs


if onClient() then


sectorOverview_GT135 = GameVersion() >= Version(1, 3, 5)

-- PREDEFINED --

-- Store base initialize function before overriding
local BaseInitialize = SectorShipOverview.initialize
-- Store base game functions that might interfere with custom components
local BaseRefreshGoodsList = nil
local BaseShow = nil

-- Component tagging system to distinguish custom components
local customComponents = {}

function SectorShipOverview.initialize() -- overridden
    print("[SectorShipOverview] *** INITIALIZATION STARTED ***")
    print("[SectorShipOverview] Setting up mouse polling system...")
    
    -- Initialize mouse state tracking for polling-based event detection
    SectorShipOverview._mouseState = {
        lastPosition = {x = 0, y = 0},
        lastLeftDown = false,
        lastRightDown = false,
        eventsGenerated = 0,
        initialized = false
    }
    
    -- Verify Mouse() availability for polling
    local success, mouse = pcall(Mouse)
    if success and mouse then
        local pos = mouse.position
        SectorShipOverview._mouseState.lastPosition = {x = pos.x, y = pos.y}
        SectorShipOverview._mouseState.initialized = true
        print("[SectorShipOverview] ✓ Mouse polling system initialized at (" .. pos.x .. ", " .. pos.y .. ")")
    else
        print("[SectorShipOverview] ✗ WARNING: Mouse() not available - polling disabled")
    end
    
    -- Verify ResizableWindow module availability
    if ResizableWindow then
        print("[SectorShipOverview] ✓ ResizableWindow module loaded successfully")
        
        if ResizableWindow.handlePlayerUIMouseEvent then
            print("[SectorShipOverview] ✓ ResizableWindow.handlePlayerUIMouseEvent available")
        else
            print("[SectorShipOverview] ✗ WARNING: ResizableWindow.handlePlayerUIMouseEvent missing")
        end
        
        if ResizableWindow.handlePlayerUIUpdate then
            print("[SectorShipOverview] ✓ ResizableWindow.handlePlayerUIUpdate available")
        else
            print("[SectorShipOverview] ⚠ ResizableWindow.handlePlayerUIUpdate not found")
        end
    else
        print("[SectorShipOverview] ✗ ResizableWindow module not loaded")
    end
    
    -- Call base game initialization first to set up overviewList and other base UI
    if BaseInitialize then
        BaseInitialize()
    end
    
    -- Override base game functions after base initialization
    setupBaseGameOverrides()
    
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
      ["ShowCrewTab"] = {true, comment = "Show Crew tab"},
      -- Resize window options
      ["EnableResize"] = {true, comment = "Enable window resizing with mouse"},
      ["MinWindowWidth"] = {320, round = -1, min = 300, max = 500, comment = "Minimum window width when resizing"},
      ["MinWindowHeight"] = {360, round = -1, min = 300, max = 500, comment = "Minimum window height when resizing"},
      ["MaxWindowWidth"] = {1600, round = -1, min = 800, max = 2400, comment = "Maximum window width when resizing"},
      ["MaxWindowHeight"] = {1200, round = -1, min = 600, max = 1800, comment = "Maximum window height when resizing"},
      ["ConstrainToScreen"] = {true, comment = "Constrain window size to screen dimensions"},
      ["ShowResizeHandles"] = {true, comment = "Show resize handles for debugging (normally invisible)"},
      ["SnapToSize"] = {true, comment = "Snap to common window sizes during resize"},
      ["ShowResizePreview"] = {false, comment = "Show preview outline when resizing (for debugging)"}
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

    -- Create ResizableWindow with configuration options and fallback
    local resizeOptions = {
        resizable = SectorOverviewConfig.EnableResize,
        minSize = vec2(SectorOverviewConfig.MinWindowWidth or 320, SectorOverviewConfig.MinWindowHeight or 360),
        maxSize = vec2(SectorOverviewConfig.MaxWindowWidth or 1600, SectorOverviewConfig.MaxWindowHeight or 1200),
        constrainToScreen = SectorOverviewConfig.ConstrainToScreen ~= false,
        snapToSize = SectorOverviewConfig.SnapToSize ~= false,
        showPreview = SectorOverviewConfig.ShowResizePreview or false,
        showHandles = true -- DEBUGGING: Always show handles to test mouse events (was: SectorOverviewConfig.ShowResizeHandles or false)
    }
    
    -- Try to create ResizableWindow with fallback to CustomTabbedWindow
    local success, result = pcall(function()
        return ResizableWindow(self, self.window, Rect(vec2(10, 10), size - 10), resizeOptions)
    end)
    
    if success and result then
        sectorOverview_tabbedWindow = result
        sectorOverview_tabbedWindow.onSelectedFunction = "refreshList"
        
        -- Set up resize callback
        sectorOverview_tabbedWindow.onResized = function(newSize)
            self.sectorOverview_onWindowResized(newSize)
        end
        
        -- Mouse events handled via polling-based state change detection in updateClient
        print("[SectorShipOverview] Mouse events handled via polling-based state change detection")
        
        print("[SectorShipOverview] ✓ ResizableWindow initialized successfully with handles visible: " .. tostring(result._config.showHandles))
        print("[SectorShipOverview] ✓ Mouse polling system fully operational:")
        print("[SectorShipOverview]   - Mouse polling: ACTIVE (updateClient @ 60 FPS)")
        print("[SectorShipOverview]   - State change detection: ENABLED")
        print("[SectorShipOverview]   - ResizableWindow integration: READY")
        print("[SectorShipOverview]   - Global events: REMOVED (not supported in Player UI)")
        print("[SectorShipOverview] *** Ready for mouse interaction testing ***")
    else
        -- Fallback to CustomTabbedWindow if ResizableWindow fails
        print("ResizableWindow initialization failed, falling back to CustomTabbedWindow: " .. tostring(result))
        
        -- Ensure CustomTabbedWindow is available
        if not CustomTabbedWindow then
            error("CustomTabbedWindow not available - missing include statement")
        end
        
        -- Create CustomTabbedWindow with error handling
        local fallbackSuccess, fallbackResult = pcall(function()
            return CustomTabbedWindow(self, self.window, Rect(vec2(10, 10), size - 10))
        end)
        
        if fallbackSuccess and fallbackResult then
            sectorOverview_tabbedWindow = fallbackResult
            sectorOverview_tabbedWindow.onSelectedFunction = "refreshList"
            
            -- Mouse events handled via polling-based state change detection in updateClient
            print("[SectorShipOverview] Mouse events handled via polling-based state change detection (fallback)")
            
            print("[SectorShipOverview] ✓ CustomTabbedWindow fallback initialized successfully")
            print("[SectorShipOverview] ⚠ ResizableWindow unavailable - using basic window")
            print("[SectorShipOverview] ✓ Mouse polling system operational with fallback:")
            print("[SectorShipOverview]   - Mouse polling: ACTIVE (basic support)")
            print("[SectorShipOverview]   - Global events: REMOVED (not supported in Player UI)")
            print("[SectorShipOverview] *** Basic UI ready for testing ***")
        else
            error("Both ResizableWindow and CustomTabbedWindow initialization failed: " .. tostring(fallbackResult))
        end
    end

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
    sectorOverview_playerTab = sectorOverview_tabbedWindow:createTab("Player List"%_t, "data/textures/icons/sectoroverview/playerfind.png", "Player List"%_t)
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

    -- Resize settings section
    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_enableResizeCheckBox = scrollFrame:createCheckBox(rect, "Enable window resizing"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_enableResizeCheckBox:setCheckedNoCallback(SectorOverviewConfig.EnableResize)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_constrainToScreenCheckBox = scrollFrame:createCheckBox(rect, "Constrain to screen"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_constrainToScreenCheckBox:setCheckedNoCallback(SectorOverviewConfig.ConstrainToScreen)

    rect = lister:placeCenter(vec2(lister.inner.width, 35))
    sectorOverview_snapToSizeCheckBox = scrollFrame:createCheckBox(rect, "Snap to common sizes"%_t, "sectorOverview_onSettingsModified")
    sectorOverview_snapToSizeCheckBox:setCheckedNoCallback(SectorOverviewConfig.SnapToSize)

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Min window width"%_t, 16)
    label:setLeftAligned()
    sectorOverview_minWindowWidthBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_minWindowWidthBox.allowedCharacters = "0123456789"
    sectorOverview_minWindowWidthBox.text = SectorOverviewConfig.MinWindowWidth
    sectorOverview_minWindowWidthBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Min window height"%_t, 16)
    label:setLeftAligned()
    sectorOverview_minWindowHeightBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_minWindowHeightBox.allowedCharacters = "0123456789"
    sectorOverview_minWindowHeightBox.text = SectorOverviewConfig.MinWindowHeight
    sectorOverview_minWindowHeightBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Max window width"%_t, 16)
    label:setLeftAligned()
    sectorOverview_maxWindowWidthBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_maxWindowWidthBox.allowedCharacters = "0123456789"
    sectorOverview_maxWindowWidthBox.text = SectorOverviewConfig.MaxWindowWidth
    sectorOverview_maxWindowWidthBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    rect = lister:placeCenter(vec2(lister.inner.width, 30))
    splitter = UIVerticalSplitter(rect, 10, 0, 0.5)
    label = scrollFrame:createLabel(splitter.left, "Max window height"%_t, 16)
    label:setLeftAligned()
    sectorOverview_maxWindowHeightBox = scrollFrame:createTextBox(splitter.right, "")
    sectorOverview_maxWindowHeightBox.allowedCharacters = "0123456789"
    sectorOverview_maxWindowHeightBox.text = SectorOverviewConfig.MaxWindowHeight
    sectorOverview_maxWindowHeightBox.onTextChangedFunction = "sectorOverview_onSettingsModified"

    local button = tab:createButton(hsplit[2], "Reset"%_t, "sectorOverview_onResetBtnPressed")
    button.maxTextSize = 16

    -- Create all additional tabs (always create, show/hide based on settings)
    sectorOverview_goodsTab = sectorOverview_tabbedWindow:createTab("Goods"%_t, "data/textures/icons/procure-command.png", "Goods"%_t)
    local hsplit = UIHorizontalSplitter(Rect(sectorOverview_goodsTab.size), 0, 0, 0.045)
    local vsplit = UIVerticalSplitter(hsplit.top, 0, 0, 0.5)
    local supplyLabel = sectorOverview_goodsTab:createLabel(vsplit.left, "[SUPPLY]"%_t, 12)
    supplyLabel:setTopAligned()
    local demandLabel = sectorOverview_goodsTab:createLabel(vsplit.right, "[DEMAND]"%_t, 12)
    demandLabel:setTopAligned()
    
    sectorOverview_goodsList = sectorOverview_goodsTab:createListBoxEx(hsplit.bottom)
    -- Fix: Ensure minimum 14 columns for base game compatibility (base game expects column 13)
    local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
    local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
    sectorOverview_goodsList.columns = numColumns
    sectorOverview_goodsList.rowHeight = SectorOverviewConfig.RowHeight or 25
    for i = 1, numColumns do
        sectorOverview_goodsList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
    end
    sectorOverview_goodsList.onSelectFunction = "onEntrySelected"
    
    -- Tag as custom component to prevent base game interference
    customComponents[sectorOverview_goodsList] = true
    
    sectorOverview_crewTab = sectorOverview_tabbedWindow:createTab("Crew"%_t, "data/textures/icons/crew.png", "Crew"%_t)
    local hsplit = UIHorizontalSplitter(Rect(sectorOverview_crewTab.size), 0, 0, 0.0)
    sectorOverview_crewList = sectorOverview_crewTab:createListBoxEx(hsplit.bottom)
    -- Fix: Ensure minimum 14 columns for base game compatibility
    local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
    local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
    sectorOverview_crewList.columns = numColumns
    sectorOverview_crewList.rowHeight = SectorOverviewConfig.RowHeight or 25
    for i = 1, numColumns do
        sectorOverview_crewList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
    end
    sectorOverview_crewList.onSelectFunction = "onEntrySelected"
    
    -- Tag as custom component to prevent base game interference
    customComponents[sectorOverview_crewList] = true
    
    sectorOverview_missionTab = sectorOverview_tabbedWindow:createTab("Bulletin Boards"%_t, "data/textures/icons/wormhole.png", "Bulletin Boards"%_t)
    local hsplit = UIHorizontalSplitter(Rect(sectorOverview_missionTab.size), 0, 0, 0.0)
    sectorOverview_missionList = sectorOverview_missionTab:createListBoxEx(hsplit.bottom)
    -- Fix: Ensure minimum 14 columns for base game compatibility
    local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
    local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
    sectorOverview_missionList.columns = numColumns
    sectorOverview_missionList.rowHeight = SectorOverviewConfig.RowHeight or 25
    for i = 1, numColumns do
        sectorOverview_missionList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
    end
    sectorOverview_missionList.onSelectFunction = "onEntrySelected"
    
    -- Tag as custom component to prevent base game interference
    customComponents[sectorOverview_missionList] = true

    -- Apply initial visibility based on config
    self.sectorOverview_updateTabVisibility()

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

function SectorShipOverview.sectorOverview_updateTabVisibility()
    if not sectorOverview_tabbedWindow then return end
    
    -- Show/hide tabs based on current config
    if SectorOverviewConfig.ShowGoodsTab then
        sectorOverview_tabbedWindow:activateTab(sectorOverview_goodsTab)
    else
        sectorOverview_tabbedWindow:deactivateTab(sectorOverview_goodsTab)
    end
    
    if SectorOverviewConfig.ShowCrewTab then
        sectorOverview_tabbedWindow:activateTab(sectorOverview_crewTab)
    else
        sectorOverview_tabbedWindow:deactivateTab(sectorOverview_crewTab)
    end
    
    if SectorOverviewConfig.ShowBulletinBoardsTab then
        sectorOverview_tabbedWindow:activateTab(sectorOverview_missionTab)
    else
        sectorOverview_tabbedWindow:deactivateTab(sectorOverview_missionTab)
    end
end

function SectorShipOverview.getUpdateInterval() -- overridden
    return 0
end

function SectorShipOverview.updateClient(timeStep) -- overridden
    if not self.window or not SectorOverviewConfig then return end

    -- Mouse polling-based state change detection system
    -- This replaces the broken global onMouseEvent approach
    if self._mouseState and self._mouseState.initialized then
        local mouse = Mouse()
        if mouse then
            local currentPos = mouse.position
            local currentLeftDown = mouse:mouseDown(MouseButton.Left)
            local currentRightDown = mouse:mouseDown(MouseButton.Right)
            
            local lastState = self._mouseState
            
            -- Detect state changes and generate events
            local eventGenerated = false
            
            -- Left button press detection
            if currentLeftDown and not lastState.lastLeftDown then
                -- Left button pressed
                if ResizableWindow and ResizableWindow.handlePlayerUIMouseEvent then
                    ResizableWindow.handlePlayerUIMouseEvent(1, true, currentPos.x, currentPos.y)
                    lastState.eventsGenerated = lastState.eventsGenerated + 1
                    eventGenerated = true
                end
            elseif not currentLeftDown and lastState.lastLeftDown then
                -- Left button released
                if ResizableWindow and ResizableWindow.handlePlayerUIMouseEvent then
                    ResizableWindow.handlePlayerUIMouseEvent(1, false, currentPos.x, currentPos.y)
                    lastState.eventsGenerated = lastState.eventsGenerated + 1
                    eventGenerated = true
                end
            end
            
            -- Right button press detection (if needed in future)
            if currentRightDown and not lastState.lastRightDown then
                -- Right button pressed
                if ResizableWindow and ResizableWindow.handlePlayerUIMouseEvent then
                    ResizableWindow.handlePlayerUIMouseEvent(2, true, currentPos.x, currentPos.y)
                    lastState.eventsGenerated = lastState.eventsGenerated + 1
                    eventGenerated = true
                end
            elseif not currentRightDown and lastState.lastRightDown then
                -- Right button released
                if ResizableWindow and ResizableWindow.handlePlayerUIMouseEvent then
                    ResizableWindow.handlePlayerUIMouseEvent(2, false, currentPos.x, currentPos.y)
                    lastState.eventsGenerated = lastState.eventsGenerated + 1
                    eventGenerated = true
                end
            end
            
            -- Update state tracking
            lastState.lastPosition = {x = currentPos.x, y = currentPos.y}
            lastState.lastLeftDown = currentLeftDown
            lastState.lastRightDown = currentRightDown
            
            -- Periodic debug logging (every ~5 seconds at 60fps)
            if not self._pollingLogCount then self._pollingLogCount = 0 end
            self._pollingLogCount = self._pollingLogCount + 1
            
            if self._pollingLogCount % 300 == 0 then
                print("[SectorShipOverview] Mouse polling: pos=(" .. currentPos.x .. "," .. currentPos.y .. ") leftDown=" .. tostring(currentLeftDown) .. " events=" .. lastState.eventsGenerated)
            end
            
            -- Enhanced debug logging when events are generated
            if eventGenerated then
                print("[SectorShipOverview] *** Mouse state change detected and event generated ***")
            end
            
        else
            -- Only log mouse error once
            if not self._mouseErrorLogged then
                print("[SectorShipOverview] ERROR: Mouse() not available for polling")
                self._mouseErrorLogged = true
            end
        end
    end
    
    -- Handle ResizableWindow updates if available
    if ResizableWindow and ResizableWindow.handlePlayerUIUpdate then
        ResizableWindow.handlePlayerUIUpdate(timeStep)
    end

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
    if sectorOverview_settingsModified and sectorOverview_settingsModified > 0 then
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
            
            -- Resize settings
            SectorOverviewConfig.EnableResize = sectorOverview_enableResizeCheckBox.checked
            SectorOverviewConfig.ConstrainToScreen = sectorOverview_constrainToScreenCheckBox.checked
            SectorOverviewConfig.SnapToSize = sectorOverview_snapToSizeCheckBox.checked
            
            -- Resize dimension settings with validation
            SectorOverviewConfig.MinWindowWidth = tonumber(sectorOverview_minWindowWidthBox.text) or 320
            if SectorOverviewConfig.MinWindowWidth < 300 or SectorOverviewConfig.MinWindowWidth > 500 then
                SectorOverviewConfig.MinWindowWidth = math.max(300, math.min(500, SectorOverviewConfig.MinWindowWidth))
                if not sectorOverview_minWindowWidthBox.isTypingActive then
                    sectorOverview_minWindowWidthBox.text = SectorOverviewConfig.MinWindowWidth
                end
            end
            
            SectorOverviewConfig.MinWindowHeight = tonumber(sectorOverview_minWindowHeightBox.text) or 360
            if SectorOverviewConfig.MinWindowHeight < 300 or SectorOverviewConfig.MinWindowHeight > 500 then
                SectorOverviewConfig.MinWindowHeight = math.max(300, math.min(500, SectorOverviewConfig.MinWindowHeight))
                if not sectorOverview_minWindowHeightBox.isTypingActive then
                    sectorOverview_minWindowHeightBox.text = SectorOverviewConfig.MinWindowHeight
                end
            end
            
            SectorOverviewConfig.MaxWindowWidth = tonumber(sectorOverview_maxWindowWidthBox.text) or 1600
            if SectorOverviewConfig.MaxWindowWidth < 800 or SectorOverviewConfig.MaxWindowWidth > 2400 then
                SectorOverviewConfig.MaxWindowWidth = math.max(800, math.min(2400, SectorOverviewConfig.MaxWindowWidth))
                if not sectorOverview_maxWindowWidthBox.isTypingActive then
                    sectorOverview_maxWindowWidthBox.text = SectorOverviewConfig.MaxWindowWidth
                end
            end
            
            SectorOverviewConfig.MaxWindowHeight = tonumber(sectorOverview_maxWindowHeightBox.text) or 1200
            if SectorOverviewConfig.MaxWindowHeight < 600 or SectorOverviewConfig.MaxWindowHeight > 1800 then
                SectorOverviewConfig.MaxWindowHeight = math.max(600, math.min(1800, SectorOverviewConfig.MaxWindowHeight))
                if not sectorOverview_maxWindowHeightBox.isTypingActive then
                    sectorOverview_maxWindowHeightBox.text = SectorOverviewConfig.MaxWindowHeight
                end
            end
            
            -- Update ResizableWindow configuration if resize settings changed
            if sectorOverview_tabbedWindow and sectorOverview_tabbedWindow._config then
                sectorOverview_tabbedWindow._config.resizable = SectorOverviewConfig.EnableResize
                sectorOverview_tabbedWindow._config.minSize = vec2(SectorOverviewConfig.MinWindowWidth, SectorOverviewConfig.MinWindowHeight)
                sectorOverview_tabbedWindow._config.maxSize = vec2(SectorOverviewConfig.MaxWindowWidth, SectorOverviewConfig.MaxWindowHeight)
                sectorOverview_tabbedWindow._config.constrainToScreen = SectorOverviewConfig.ConstrainToScreen
                sectorOverview_tabbedWindow._config.snapToSize = SectorOverviewConfig.SnapToSize
            end

            Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)

            -- Apply window resize when settings change
            self.updateWindowSize()
            
            -- Update tab visibility when settings change
            self.sectorOverview_updateTabVisibility()

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
    
    -- Perform comprehensive layout update
    self.updateAllSplitterLayouts()
    self.updateListSizes()
end

-- Callback for ResizableWindow resize events
function SectorShipOverview.sectorOverview_onWindowResized(newSize)
    if not SectorOverviewConfig then return end
    
    -- Update config with new size (from resize operation)
    local actualWindowSize = newSize + vec2(20, 20) -- Account for margins
    SectorOverviewConfig.WindowWidth = actualWindowSize.x
    SectorOverviewConfig.WindowHeight = actualWindowSize.y
    
    -- Update UI text boxes to reflect new size
    if sectorOverview_windowWidthBox and not sectorOverview_windowWidthBox.isTypingActive then
        sectorOverview_windowWidthBox.text = tostring(math.floor(actualWindowSize.x))
    end
    if sectorOverview_windowHeightBox and not sectorOverview_windowHeightBox.isTypingActive then
        sectorOverview_windowHeightBox.text = tostring(math.floor(actualWindowSize.y))
    end
    
    -- Update actual window size to match
    if self.window then
        self.window.size = actualWindowSize
    end
    
    -- Perform deferred layout updates for performance during resize
    deferredCallback(0.1, "sectorOverview_deferredLayoutUpdate")
    
    -- Save config after resize completes
    Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)
end

-- Deferred layout update for performance during resize operations
function SectorShipOverview.sectorOverview_deferredLayoutUpdate()
    self.updateAllSplitterLayouts()
    self.updateListSizes()
end

-- Update all splitter layouts after resize
function SectorShipOverview.updateAllSplitterLayouts()
    if not sectorOverview_tabbedWindow then return end
    
    -- Update player tab splitter if it exists
    if sectorOverview_playerTab and sectorOverview_playerTab.size then
        -- Recreate the proportional splitter with new dimensions
        local newHsplit = UIHorizontalProportionalSplitter(Rect(sectorOverview_playerTab.size), 10, 0, {30, 0.5, 25, 35})
        
        -- Update existing UI elements with new rects if they exist
        if sectorOverview_playerList and sectorOverview_playerList.rect then
            sectorOverview_playerList.rect = newHsplit[2]
        end
        if sectorOverview_playerCombo and sectorOverview_playerCombo.rect then
            sectorOverview_playerCombo.rect = newHsplit[3]
        end
    end
    
    -- Update other tab splitters as needed
    -- Additional splitter updates can be added here for other tabs that use proportional layouts
end

-- Update all list sizes and column widths
function SectorShipOverview.updateListSizes()
    -- Update station list
    if sectorOverview_stationList and sectorOverview_stationTab then
        sectorOverview_stationList.size = sectorOverview_stationTab.size
        sectorOverview_stationList:setColumnWidth(0, SectorOverviewConfig.IconColumnWidth or 25)
        sectorOverview_stationList:setColumnWidth(1, SectorOverviewConfig.IconColumnWidth or 25)
        sectorOverview_stationList:setColumnWidth(2, sectorOverview_stationList.width - 85)
        sectorOverview_stationList:setColumnWidth(3, SectorOverviewConfig.IconColumnWidth or 25)
    end
    
    -- Update ship list
    if sectorOverview_shipList and sectorOverview_shipTab then
        sectorOverview_shipList.size = sectorOverview_shipTab.size
        sectorOverview_shipList:setColumnWidth(0, SectorOverviewConfig.IconColumnWidth or 25)
        sectorOverview_shipList:setColumnWidth(1, SectorOverviewConfig.IconColumnWidth or 25)
        sectorOverview_shipList:setColumnWidth(2, sectorOverview_shipList.width - 85)
        sectorOverview_shipList:setColumnWidth(3, SectorOverviewConfig.IconColumnWidth or 25)
    end
    
    -- Update gate list
    if sectorOverview_gateList and sectorOverview_gateTab then
        sectorOverview_gateList.size = sectorOverview_gateTab.size
        sectorOverview_gateList:setColumnWidth(0, SectorOverviewConfig.IconColumnWidth or 25)
        sectorOverview_gateList:setColumnWidth(1, sectorOverview_gateList.width - 35)
    end
    
    -- Update player list
    if sectorOverview_playerList and sectorOverview_playerTab then
        sectorOverview_playerList.size = sectorOverview_playerTab.size
    end
    
    -- Update additional tab lists with content sizing settings
    if sectorOverview_goodsList and sectorOverview_goodsTab then
        sectorOverview_goodsList.size = sectorOverview_goodsTab.size
        sectorOverview_goodsList.rowHeight = SectorOverviewConfig.RowHeight or 25
        -- Fix: Ensure minimum 14 columns for base game compatibility
        local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
        local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
        for i = 1, numColumns do
            sectorOverview_goodsList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
        end
    end
    
    if sectorOverview_crewList and sectorOverview_crewTab then
        sectorOverview_crewList.size = sectorOverview_crewTab.size
        sectorOverview_crewList.rowHeight = SectorOverviewConfig.RowHeight or 25
        -- Fix: Ensure minimum 14 columns for base game compatibility
        local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
        local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
        for i = 1, numColumns do
            sectorOverview_crewList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
        end
    end
    
    if sectorOverview_missionList and sectorOverview_missionTab then
        sectorOverview_missionList.size = sectorOverview_missionTab.size
        sectorOverview_missionList.rowHeight = SectorOverviewConfig.RowHeight or 25
        -- Fix: Ensure minimum 14 columns for base game compatibility
        local baseColumns = (SectorOverviewConfig.IconsPerRow or 11) + 2
        local numColumns = math.max(baseColumns, 14)  -- Minimum 14 columns
        for i = 1, numColumns do
            sectorOverview_missionList:setColumnWidth(i-1, SectorOverviewConfig.IconColumnWidth or 25)
        end
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
    -- Safety check: only operate on properly initialized custom components
    if not sectorOverview_goodsList or not isCustomComponent(sectorOverview_goodsList) then 
        return 
    end
    
    -- Additional safety check for component integrity
    if not sectorOverview_goodsList.columns or sectorOverview_goodsList.columns < 14 then
        print("Warning: Custom goodsList component not properly initialized with minimum columns (has " .. (sectorOverview_goodsList.columns or "nil") .. ", needs 14+)")
        return
    end

    local lists = self.collectEntities()
    local stationList = lists[1]
    local player = Player()

    local scrollPosition = sectorOverview_goodsList.scrollPosition
    sectorOverview_goodsList:clear()

    local white = ColorRGB(1, 1, 1)
    local buyColor = ColorRGB(1, 0.8, 0.7)
    local sellColor = ColorRGB(0.8, 0.8, 1)

    local renderer = UIRenderer()
    
    -- Calculate maximum columns available (0-based indexing)
    local maxColumns = sectorOverview_goodsList.columns - 1

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
            safeSetEntry(sectorOverview_goodsList, 0, sectorOverview_goodsList.rows - 1, entry.icon, false, false, white, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            safeSetEntry(sectorOverview_goodsList, 1, sectorOverview_goodsList.rows - 1, entry.name, false, false, color, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            
            -- Safe bounds check for group column
            local groupColumn = math.min(11, maxColumns)
            safeSetEntry(sectorOverview_goodsList, groupColumn, sectorOverview_goodsList.rows - 1, entry.group, false, false, white, sectorOverview_goodsList.width - 2 * self.iconColumnWidth)
            safeSetEntryType(sectorOverview_goodsList, 0, sectorOverview_goodsList.rows - 1, ListBoxEntryType.PixelIcon)

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
                
                -- Safe bounds checking for supply column
                if i < #supplyIcons + 1 and column <= maxColumns then
                    safeSetEntry(sectorOverview_goodsList, column, sectorOverview_goodsList.rows - 1, supplyIcons[i], false, false, sellColor, 0)
                    safeSetEntryType(sectorOverview_goodsList, column, sectorOverview_goodsList.rows - 1, ListBoxEntryType.Icon)
                    safeSetEntryTooltip(sectorOverview_goodsList, column, sectorOverview_goodsList.rows - 1, supplyTooltips[i])
                end

                -- Safe bounds checking for demand column
                if i < #demandIcons + 1 and demandColumn <= maxColumns then
                    safeSetEntry(sectorOverview_goodsList, demandColumn, sectorOverview_goodsList.rows - 1, demandIcons[i], false, false, buyColor, 0)
                    safeSetEntryType(sectorOverview_goodsList, demandColumn, sectorOverview_goodsList.rows - 1, ListBoxEntryType.Icon)
                    safeSetEntryTooltip(sectorOverview_goodsList, demandColumn, sectorOverview_goodsList.rows - 1, demandTooltips[i])
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
    
    -- Calculate maximum columns available (0-based indexing)
    local maxColumns = sectorOverview_crewList.columns - 1

    -- Use global shared captain icon registry for cross-mod compatibility
    -- If no registry exists, we become the baseline provider for all mods that don't define their own captain icons
    if not _G["simplifiedIcons"] then
        _G["simplifiedIcons"] = {}
        local simplifiedIcons = _G["simplifiedIcons"]

        -- Populate vanilla captain classes as baseline
        simplifiedIcons[CaptainUtility.ClassType.None] = {path = "data/textures/icons/captain-noclass.png", color = ColorRGB(1, 1, 1)}
        simplifiedIcons[CaptainUtility.ClassType.Commodore] = {path = "data/textures/icons/captain-commodore.png", color = ColorRGB(0, 0.74, 0.74)}
        simplifiedIcons[CaptainUtility.ClassType.Smuggler] = {path = "data/textures/icons/captain-smuggler.png", color = ColorRGB(0.78, 0.03, 0.75)}
        simplifiedIcons[CaptainUtility.ClassType.Merchant] = {path = "data/textures/icons/captain-merchant.png", color = ColorRGB(0.5, 0.8, 0)}
        simplifiedIcons[CaptainUtility.ClassType.Miner] = {path = "data/textures/icons/captain-miner.png", color = ColorRGB(0.5, 0.8, 0)}
        simplifiedIcons[CaptainUtility.ClassType.Scavenger] = {path = "data/textures/icons/captain-scavenger.png", color = ColorRGB(0.1, 0.5, 1)}
        simplifiedIcons[CaptainUtility.ClassType.Explorer] = {path = "data/textures/icons/captain-explorer.png", color = ColorRGB(1, 0.88, 0.04)}
        simplifiedIcons[CaptainUtility.ClassType.Daredevil] = {path = "data/textures/icons/captain-daredevil.png", color = ColorRGB(0.9, 0.1, 0.1)}
        simplifiedIcons[CaptainUtility.ClassType.Scientist] = {path = "data/textures/icons/captain-scientist.png", color = ColorRGB(1, 0.47, 0)}
        simplifiedIcons[CaptainUtility.ClassType.Hunter] = {path = "data/textures/icons/captain-hunter.png", color = ColorRGB(1, 0.43, 0.77)}
    end

    local simplifiedIcons = _G["simplifiedIcons"]

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
            -- Handle Class 0 (no class) as special case - same pattern as working mod 3296627306
            if captain.primaryClass == 0 then
                table.insert(captainIcons, {path = "data/textures/icons/captain-noclass.png", color = ColorRGB(1, 1, 1)})
                captainTooltip = "Captain [no class"%_t
            else
                -- Handle other classes using global registry with fallback
                local primaryIcon = simplifiedIcons[captain.primaryClass]
                if not primaryIcon and classProperties[captain.primaryClass] then
                    -- Dynamic fallback: create icon entry for unknown modded class
                    primaryIcon = {
                        path = classProperties[captain.primaryClass].icon or "data/textures/icons/captain-noclass.png", 
                        color = ColorRGB(1, 1, 1)
                    }
                    -- Register it globally for future use
                    simplifiedIcons[captain.primaryClass] = primaryIcon
                end

                if primaryIcon then
                    table.insert(captainIcons, primaryIcon)
                    captainTooltip = "Captain ["%_t .. classProperties[captain.primaryClass].displayName % _t
                else
                    -- Ultimate fallback for completely unknown class
                    table.insert(captainIcons, {path = "data/textures/icons/captain-noclass.png", color = ColorRGB(1, 1, 1)})
                    captainTooltip = "Captain [unknown class"%_t
                end
            end

            -- Handle secondary class with same dynamic logic
            if captain.secondaryClass and captain.secondaryClass ~= 0 then
                local secondaryIcon = simplifiedIcons[captain.secondaryClass]
                if not secondaryIcon and classProperties[captain.secondaryClass] then
                    -- Dynamic fallback for secondary class
                    secondaryIcon = {
                        path = classProperties[captain.secondaryClass].icon or "data/textures/icons/captain-noclass.png", 
                        color = ColorRGB(1, 1, 1)
                    }
                    simplifiedIcons[captain.secondaryClass] = secondaryIcon
                end

                if secondaryIcon then
                    table.insert(captainIcons, secondaryIcon)
                    captainTooltip = captainTooltip .. ", " .. classProperties[captain.secondaryClass].displayName % _t
                end
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

            -- Bounds check for group column (was using hardcoded 11)
            local groupColumn = math.min(11, maxColumns)
            sectorOverview_crewList:setEntry(groupColumn, sectorOverview_crewList.rows - 1, entry.group, false, false, white, sectorOverview_crewList.width - 2 * self.iconColumnWidth)

            sectorOverview_crewList:addRow(entity.id.string)
            for i = 1, #icons do
                -- Bounds checking for all icon columns
                if i <= maxColumns then
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

    local scrollPosition = sectorOverview_missionList.scrollPosition
    sectorOverview_missionList:clear()

    local white = ColorRGB(1, 1, 1)
    local renderer = UIRenderer()
    
    -- Calculate maximum columns available (0-based indexing)
    local maxColumns = sectorOverview_missionList.columns - 1

    local stationsProcessed = 0
    local stationsWithMissions = 0

    for _, entry in pairs(stationList.entries) do
        local entity = entry.entity
        local color = renderer:getEntityTargeterColor(entity)
        stationsProcessed = stationsProcessed + 1

        local missions = {}
        local hasRiftScript = entity:hasScript("dlc/rift/entity/riftresearchcenter.lua")
        local hasBulletinScript = entity:hasScript("data/scripts/entity/bulletinboard.lua")

        if hasRiftScript and player.ownsIntoTheRiftDLC then
            _, missions = entity:invokeFunction("dlc/rift/entity/riftresearchcenter.lua", "getDisplayedBulletins")
            -- print("DEBUG: Rift research center missions: " .. (missions and #missions or "nil"))
        elseif hasBulletinScript then
            _, missions = entity:invokeFunction("data/scripts/entity/bulletinboard.lua", "getDisplayedBulletins")
            -- print("DEBUG: Bulletin board missions: " .. (missions and #missions or "nil"))
        else
            -- print("DEBUG: Station has no mission scripts")
            goto continue
        end

        if not missions then 
            -- print("DEBUG: No missions returned from station")
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


        if #tooltips > 0 then
            sectorOverview_missionList:addRow(entity.id.string)
            sectorOverview_missionList:setEntry(0, sectorOverview_missionList.rows - 1, entry.icon, false, false, white, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            sectorOverview_missionList:setEntry(1, sectorOverview_missionList.rows - 1, entry.name, false, false, color, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            
            -- Bounds check for group column (was using hardcoded 11)
            local groupColumn = math.min(11, maxColumns)
            sectorOverview_missionList:setEntry(groupColumn, sectorOverview_missionList.rows - 1, entry.group, false, false, white, sectorOverview_missionList.width - 2 * self.iconColumnWidth)
            sectorOverview_missionList:setEntryType(0, sectorOverview_missionList.rows - 1, ListBoxEntryType.PixelIcon)

            sectorOverview_missionList:addRow(entity.id.string)
            for i = 1, #icons do
                -- Bounds checking for mission icon columns
                if i <= maxColumns then
                    sectorOverview_missionList:setEntry(i, sectorOverview_missionList.rows - 1, icons[i], false, false, missions[i].iconColor or white, 0)
                    sectorOverview_missionList:setEntryType(i, sectorOverview_missionList.rows - 1, ListBoxEntryType.Icon)
                    sectorOverview_missionList:setEntryTooltip(i, sectorOverview_missionList.rows - 1, tooltips[i])
                end
            end
        end

        ::continue::
    end

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

    -- Resize settings resets
    SectorOverviewConfig.EnableResize = sectorOverview_configOptions.EnableResize[1]
    sectorOverview_enableResizeCheckBox:setCheckedNoCallback(SectorOverviewConfig.EnableResize)

    SectorOverviewConfig.ConstrainToScreen = sectorOverview_configOptions.ConstrainToScreen[1]
    sectorOverview_constrainToScreenCheckBox:setCheckedNoCallback(SectorOverviewConfig.ConstrainToScreen)

    SectorOverviewConfig.SnapToSize = sectorOverview_configOptions.SnapToSize[1]
    sectorOverview_snapToSizeCheckBox:setCheckedNoCallback(SectorOverviewConfig.SnapToSize)

    SectorOverviewConfig.MinWindowWidth = sectorOverview_configOptions.MinWindowWidth[1]
    sectorOverview_minWindowWidthBox.text = SectorOverviewConfig.MinWindowWidth

    SectorOverviewConfig.MinWindowHeight = sectorOverview_configOptions.MinWindowHeight[1]
    sectorOverview_minWindowHeightBox.text = SectorOverviewConfig.MinWindowHeight

    SectorOverviewConfig.MaxWindowWidth = sectorOverview_configOptions.MaxWindowWidth[1]
    sectorOverview_maxWindowWidthBox.text = SectorOverviewConfig.MaxWindowWidth

    SectorOverviewConfig.MaxWindowHeight = sectorOverview_configOptions.MaxWindowHeight[1]
    sectorOverview_maxWindowHeightBox.text = SectorOverviewConfig.MaxWindowHeight

    -- Update ResizableWindow configuration after reset
    if sectorOverview_tabbedWindow and sectorOverview_tabbedWindow._config then
        sectorOverview_tabbedWindow._config.resizable = SectorOverviewConfig.EnableResize
        sectorOverview_tabbedWindow._config.minSize = vec2(SectorOverviewConfig.MinWindowWidth, SectorOverviewConfig.MinWindowHeight)
        sectorOverview_tabbedWindow._config.maxSize = vec2(SectorOverviewConfig.MaxWindowWidth, SectorOverviewConfig.MaxWindowHeight)
        sectorOverview_tabbedWindow._config.constrainToScreen = SectorOverviewConfig.ConstrainToScreen
        sectorOverview_tabbedWindow._config.snapToSize = SectorOverviewConfig.SnapToSize
    end

    Azimuth.saveConfig("SectorOverview", SectorOverviewConfig, sectorOverview_configOptions)

    -- Apply window resize after reset
    self.updateWindowSize()
    
    -- Update tab visibility after reset
    self.sectorOverview_updateTabVisibility()

    invokeServerFunction("sectorOverview_setNotifyAboutEnemies", SectorOverviewConfig.NotifyAboutEnemies)
end

-- Base game override functions to prevent interference with custom components
function setupBaseGameOverrides()
    -- Store original functions if they exist
    if SectorShipOverview.refreshGoodsList then
        BaseRefreshGoodsList = SectorShipOverview.refreshGoodsList
    end
    if SectorShipOverview.show then
        BaseShow = SectorShipOverview.show
    end
    
    -- Override refreshGoodsList to prevent base game from operating on custom components
    if BaseRefreshGoodsList then
        SectorShipOverview.refreshGoodsList = function(...)
            -- Only call base refreshGoodsList if our custom goodsList is not present
            -- This prevents base game from trying to access column 13 on our custom components
            if not sectorOverview_goodsList or not customComponents[sectorOverview_goodsList] then
                return BaseRefreshGoodsList(...)
            end
            -- If custom goodsList exists, do nothing - we handle it ourselves
        end
    end
    
    -- Override show function to ensure safe integration
    if BaseShow then
        SectorShipOverview.show = function(...)
            -- Call base show function
            local result = BaseShow(...)
            
            -- Ensure our custom components are properly initialized after show
            if sectorOverview_goodsList and customComponents[sectorOverview_goodsList] then
                -- Refresh our custom goods list safely
                pcall(function()
                    SectorShipOverview.sectorOverview_refreshGoodsList()
                end)
            end
            
            return result
        end
    end
end

-- Safe component validation function
function isCustomComponent(component)
    return component and customComponents[component] == true
end

-- Enhanced bounds checking for ListBoxEx operations
function safeSetEntry(listBox, column, row, ...)
    if not listBox or not isCustomComponent(listBox) then
        -- Let base game handle its own components
        return
    end
    
    -- Bounds check for custom components
    if column >= 0 and column < listBox.columns and row >= 0 and row < listBox.rows then
        listBox:setEntry(column, row, ...)
    else
        print("Warning: Attempted to set entry at invalid position [" .. column .. "," .. row .. "] on ListBoxEx with " .. listBox.columns .. " columns and " .. listBox.rows .. " rows")
    end
end

-- Enhanced bounds checking for entry type operations
function safeSetEntryType(listBox, column, row, entryType)
    if not listBox or not isCustomComponent(listBox) then
        return
    end
    
    if column >= 0 and column < listBox.columns and row >= 0 and row < listBox.rows then
        listBox:setEntryType(column, row, entryType)
    else
        print("Warning: Attempted to set entry type at invalid position [" .. column .. "," .. row .. "] on ListBoxEx with " .. listBox.columns .. " columns and " .. listBox.rows .. " rows")
    end
end

-- Enhanced bounds checking for tooltip operations
function safeSetEntryTooltip(listBox, column, row, tooltip)
    if not listBox or not isCustomComponent(listBox) then
        return
    end
    
    if column >= 0 and column < listBox.columns and row >= 0 and row < listBox.rows then
        listBox:setEntryTooltip(column, row, tooltip)
    else
        print("Warning: Attempted to set entry tooltip at invalid position [" .. column .. "," .. row .. "] on ListBoxEx with " .. listBox.columns .. " columns and " .. listBox.rows .. " rows")
    end
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