--- ResizableWindow - Wrapper around AzimuthLib CustomTabbedWindow with mouse-driven resize support
-- Provides resizable window functionality using custom resize handles and mouse event handling
-- @usage local ResizableWindow = include("resizablewindow")
-- @usage local window = ResizableWindow(namespace, parent, rect, options)
-- @module ResizableWindow

local CustomTabbedWindow = include("azimuthlib-customtabbedwindow")

local ResizableWindow = {}

-- Global state for tracking all resizable windows and mouse events
local resizableWindows = {}
local resizeState = {
    active = false,
    window = nil,
    handle = nil,
    startPos = nil,
    startSize = nil,
    startWindowPos = nil,
    mode = "idle", -- idle|capturing|resizing|finalizing
    lastUpdateTime = 0,
    mouseCaptured = false,
    previewSize = nil,
    previewPos = nil
}

-- Performance and throttling configuration
local PerformanceConfig = {
    maxFPS = 60,                    -- Maximum update rate during resize
    minFrameTime = 1/60,           -- Minimum time between updates (16.67ms)
    mouseMoveThreshold = 2,        -- Minimum pixel movement to trigger update
    snapThreshold = 10,            -- Snap-to-size threshold in pixels
    debounceTime = 0.016,          -- Mouse movement debounce (16ms)
    hoverTransitionTime = 0.15     -- Hover effect transition time
}

-- Visual feedback configuration
local VisualConfig = {
    hoverColor = ColorARGB(0.4, 1, 1, 0),      -- Yellow on hover
    activeColor = ColorARGB(0.6, 1, 0.5, 0),   -- Orange while dragging
    defaultColor = ColorARGB(0.2, 0, 1, 0),    -- Green default
    previewColor = ColorARGB(0.2, 0, 0.8, 1),  -- Blue preview outline
    nearLimitColor = ColorARGB(0.3, 1, 0, 0),  -- Red when near size limits
    guideThickness = 2,
    pulseSpeed = 2.0
}

-- Configuration for resize handles
local HandleConfig = {
    size = 8,           -- Handle hit area size in pixels
    margin = 4,         -- Margin from window edge
    layer = 100,        -- High layer to stay above content
    thickness = 1       -- Visual thickness (when visible)
}

-- Validation helper for HandleTypes position functions
local function validateRect(rect, handleName)
    if not rect then
        print("ERROR: HandleTypes." .. handleName .. ".position - rect is nil")
        return false
    end
    if not rect.lower or not rect.upper then
        print("ERROR: HandleTypes." .. handleName .. ".position - rect missing lower/upper properties")
        return false
    end
    return true
end

-- Handle definitions with cursor types and resize logic
local HandleTypes = {
    topLeft = {
        cursor = "resize-nw",
        position = function(rect) 
            if not validateRect(rect, "topLeft") then return vec2(0, 0) end
            return vec2(rect.lower.x - HandleConfig.margin, rect.lower.y - HandleConfig.margin) 
        end,
        size = function() return vec2(HandleConfig.size, HandleConfig.size) end,
        resize = function(delta, startSize) return vec2(startSize.x - delta.x, startSize.y - delta.y) end,
        reposition = function(delta, startPos) return vec2(startPos.x + delta.x, startPos.y + delta.y) end
    },
    topRight = {
        cursor = "resize-ne", 
        position = function(rect) 
            if not validateRect(rect, "topRight") then return vec2(0, 0) end
            return vec2(rect.upper.x - HandleConfig.size + HandleConfig.margin, rect.lower.y - HandleConfig.margin) 
        end,
        size = function() return vec2(HandleConfig.size, HandleConfig.size) end,
        resize = function(delta, startSize) return vec2(startSize.x + delta.x, startSize.y - delta.y) end,
        reposition = function(delta, startPos) return vec2(startPos.x, startPos.y + delta.y) end
    },
    bottomLeft = {
        cursor = "resize-sw",
        position = function(rect) 
            if not validateRect(rect, "bottomLeft") then return vec2(0, 0) end
            return vec2(rect.lower.x - HandleConfig.margin, rect.upper.y - HandleConfig.size + HandleConfig.margin) 
        end,
        size = function() return vec2(HandleConfig.size, HandleConfig.size) end,
        resize = function(delta, startSize) return vec2(startSize.x - delta.x, startSize.y + delta.y) end,
        reposition = function(delta, startPos) return vec2(startPos.x + delta.x, startPos.y) end
    },
    bottomRight = {
        cursor = "resize-se",
        position = function(rect) 
            if not validateRect(rect, "bottomRight") then return vec2(0, 0) end
            return vec2(rect.upper.x - HandleConfig.size + HandleConfig.margin, rect.upper.y - HandleConfig.size + HandleConfig.margin) 
        end,
        size = function() return vec2(HandleConfig.size, HandleConfig.size) end,
        resize = function(delta, startSize) return vec2(startSize.x + delta.x, startSize.y + delta.y) end,
        reposition = function(delta, startPos) return startPos end
    },
    top = {
        cursor = "resize-n",
        position = function(rect) 
            if not validateRect(rect, "top") then return vec2(0, 0) end
            return vec2(rect.lower.x + HandleConfig.margin, rect.lower.y - HandleConfig.margin) 
        end,
        size = function(rect) 
            if not validateRect(rect, "top") then return vec2(HandleConfig.size, HandleConfig.size) end
            return vec2(rect.width - 2 * HandleConfig.margin, HandleConfig.size) 
        end,
        resize = function(delta, startSize) return vec2(startSize.x, startSize.y - delta.y) end,
        reposition = function(delta, startPos) return vec2(startPos.x, startPos.y + delta.y) end
    },
    bottom = {
        cursor = "resize-s",
        position = function(rect) 
            if not validateRect(rect, "bottom") then return vec2(0, 0) end
            return vec2(rect.lower.x + HandleConfig.margin, rect.upper.y - HandleConfig.size + HandleConfig.margin) 
        end,
        size = function(rect) 
            if not validateRect(rect, "bottom") then return vec2(HandleConfig.size, HandleConfig.size) end
            return vec2(rect.width - 2 * HandleConfig.margin, HandleConfig.size) 
        end,
        resize = function(delta, startSize) return vec2(startSize.x, startSize.y + delta.y) end,
        reposition = function(delta, startPos) return startPos end
    },
    left = {
        cursor = "resize-w",
        position = function(rect) 
            if not validateRect(rect, "left") then return vec2(0, 0) end
            return vec2(rect.lower.x - HandleConfig.margin, rect.lower.y + HandleConfig.margin) 
        end,
        size = function(rect) 
            if not validateRect(rect, "left") then return vec2(HandleConfig.size, HandleConfig.size) end
            return vec2(HandleConfig.size, rect.height - 2 * HandleConfig.margin) 
        end,
        resize = function(delta, startSize) return vec2(startSize.x - delta.x, startSize.y) end,
        reposition = function(delta, startPos) return vec2(startPos.x + delta.x, startPos.y) end
    },
    right = {
        cursor = "resize-e",
        position = function(rect) 
            if not validateRect(rect, "right") then return vec2(0, 0) end
            return vec2(rect.upper.x - HandleConfig.size + HandleConfig.margin, rect.lower.y + HandleConfig.margin) 
        end,
        size = function(rect) 
            if not validateRect(rect, "right") then return vec2(HandleConfig.size, HandleConfig.size) end
            return vec2(HandleConfig.size, rect.height - 2 * HandleConfig.margin) 
        end,
        resize = function(delta, startSize) return vec2(startSize.x + delta.x, startSize.y) end,
        reposition = function(delta, startPos) return startPos end
    }
}

--- Creates a new ResizableWindow instance
-- @tparam table namespace - Mod namespace for callback registration
-- @tparam UIContainer parent - Parent UI container
-- @tparam Rect rect - Initial window rectangle
-- @tparam table options - Configuration options
-- @treturn ResizableWindow - New resizable window instance
function ResizableWindow.new(namespace, parent, rect, options)
    options = options or {}
    
    -- Create the underlying CustomTabbedWindow
    local tabbedWindow = CustomTabbedWindow(namespace, parent, rect)
    
    -- Validate CustomTabbedWindow is ready (fail-fast pattern)
    if not tabbedWindow then
        error("ResizableWindow: CustomTabbedWindow creation failed")
    end
    
    -- Validate rect property is accessible safely (avoid AzimuthLib recursive property bug)
    local rect
    local rectSuccess, rectResult = pcall(function()
        return tabbedWindow._contentRect or tabbedWindow.rect
    end)
    
    if rectSuccess and rectResult then
        rect = rectResult
    else
        local errorMsg = "ResizableWindow: CustomTabbedWindow rect not available"
        if rectResult then
            errorMsg = errorMsg .. " - " .. tostring(rectResult)
        end
        errorMsg = errorMsg .. ". This indicates an AzimuthLib CustomTabbedWindow recursive property access bug."
        error(errorMsg)
    end
    
    -- Validate rect has required properties (fail-fast pattern)
    if not rect or not rect.lower or not rect.upper or not rect.width or not rect.height then
        error("ResizableWindow: Invalid rect properties")
    end

    -- Create the wrapper instance
    local instance = {
        _tabbedWindow = tabbedWindow,
        _namespace = namespace,
        _parent = parent,
        _resizeHandles = {},
        _config = {
            resizable = options.resizable ~= false,
            minSize = options.minSize or vec2(320, 360),
            maxSize = options.maxSize or vec2(1600, 1200),
            showHandles = options.showHandles or false, -- For debugging
            constrainToScreen = options.constrainToScreen ~= false,
            snapToSize = options.snapToSize ~= false,
            showPreview = options.showPreview ~= false,
            enableVisualGuides = options.enableVisualGuides ~= false
        },
        _hover = {
            handle = nil,
            tooltip = nil,
            startTime = 0,
            transitionProgress = 0
        },
        _preview = {
            outline = nil,
            guides = {},
            visible = false
        },
        _performance = {
            lastMousePos = nil,
            lastUpdateTime = 0,
            frameSkipCount = 0
        }
    }

    setmetatable(instance, ResizableWindow)

    -- Immediate synchronous initialization following AzimuthLib pattern
    if instance._config.resizable then
        instance:_initializeResizeHandles()
        instance:_initializePreviewSystem()
        instance:_registerForMouseEvents()
    end

    return instance
end

--- Initialize preview system for visual feedback during resize
function ResizableWindow:_initializePreviewSystem()
    if not self._config.showPreview then return end
    
    -- Create preview outline container
    local previewContainer = self._parent:createContainer(Rect(0, 0, 100, 100))
    previewContainer.layer = HandleConfig.layer + 1
    previewContainer.visible = false
    
    -- Create outline rectangles (top, right, bottom, left)
    local outline = {}
    for i = 1, 4 do
        local rect = previewContainer:createRect(Rect(0, 0, 1, 1), VisualConfig.previewColor)
        outline[i] = rect
    end
    
    self._preview.outline = {
        container = previewContainer,
        rects = outline
    }
    
    -- Initialize visual guides if enabled
    if self._config.enableVisualGuides then
        self:_initializeVisualGuides()
    end
end

--- Initialize visual guides for size constraints
function ResizableWindow:_initializeVisualGuides()
    -- Create guides for showing size constraints
    local guidesContainer = self._parent:createContainer(Rect(0, 0, 100, 100))
    guidesContainer.layer = HandleConfig.layer - 1
    guidesContainer.visible = false
    
    -- Size constraint indicators
    self._preview.guides = {
        container = guidesContainer,
        minSizeIndicator = nil,
        maxSizeIndicator = nil,
        snapIndicators = {}
    }
end

--- Safe rect access helper to avoid AzimuthLib CustomTabbedWindow recursive property bug
-- @treturn Rect|nil - Window rect or nil if access fails
function ResizableWindow:_getSafeRect()
    local success, result = pcall(function()
        -- Try _contentRect first (internal property), then fallback to rect property
        return self._tabbedWindow._contentRect or self._tabbedWindow.rect
    end)
    
    if success and result and result.lower and result.upper then
        return result
    else
        print("Warning: ResizableWindow - Safe rect access failed: " .. tostring(result))
        return nil
    end
end


--- Initialize resize handles for the window
function ResizableWindow:_initializeResizeHandles()
    -- Use safe rect access to avoid AzimuthLib recursive property bug
    local windowRect = self:_getSafeRect()
    if not windowRect then
        print("Error: ResizableWindow - Cannot initialize resize handles, window rect unavailable")
        return
    end
    
    -- Create resize handles for each position
    for handleName, handleDef in pairs(HandleTypes) do
        local handlePos = handleDef.position(windowRect)
        local handleSize = handleDef.size(windowRect) or handleDef.size()
        local handleRect = Rect(handlePos.x, handlePos.y, handlePos.x + handleSize.x, handlePos.y + handleSize.y)
        
        -- Create invisible container for the handle
        local handleContainer = self._parent:createContainer(handleRect)
        handleContainer.layer = HandleConfig.layer
        
        -- Create visual indicator (invisible by default, can be enabled for debugging)
        local handleVisual = handleContainer:createRect(Rect(0, 0, handleSize.x, handleSize.y), ColorARGB(0, 1, 1, 1))
        if self._config.showHandles then
            handleVisual.color = ColorARGB(0.3, 0, 1, 0) -- Semi-transparent green for debugging
        end
        
        -- Store handle information
        self._resizeHandles[handleName] = {
            container = handleContainer,
            visual = handleVisual,
            type = handleName,
            definition = handleDef,
            hovered = false,
            active = false,
            hoverStartTime = 0,
            lastVisualUpdate = 0
        }
    end
end

--- Register this window for global mouse event handling
function ResizableWindow:_registerForMouseEvents()
    -- Add to global registry
    resizableWindows[#resizableWindows + 1] = self
    
    -- Register global mouse callbacks in namespace if not already present
    if not self._namespace.resizableWindow_onMousePressed then
        self._namespace.resizableWindow_onMousePressed = onMousePressed
        self._namespace.resizableWindow_onMouseMove = onMouseMove  
        self._namespace.resizableWindow_onMouseReleased = onMouseReleased
    end
end

--- Update resize handle positions when window rect changes
function ResizableWindow:_updateResizeHandles()
    if not self._config.resizable or not self._resizeHandles then return end

    -- Use safe rect access to avoid AzimuthLib recursive property bug
    local windowRect = self:_getSafeRect()
    if not windowRect then
        print("Warning: ResizableWindow - Cannot update resize handles, window rect unavailable")
        return
    end

    for handleName, handle in pairs(self._resizeHandles) do
        -- Additional safety check for handle validity
        if not handle or not handle.definition or not handle.container then
            print("Warning: ResizableWindow - Invalid handle data for: " .. tostring(handleName))
            goto continue
        end
        
        local handleDef = handle.definition
        local newPos = handleDef.position(windowRect)
        local newSize = handleDef.size(windowRect) or handleDef.size()

        -- Validate position and size before applying
        if newPos and newSize and newPos.x and newPos.y and newSize.x and newSize.y then
            -- Update handle container position and size
            handle.container.rect = Rect(newPos.x, newPos.y, newPos.x + newSize.x, newPos.y + newSize.y)
            handle.visual.rect = Rect(0, 0, newSize.x, newSize.y)
        else
            print("Warning: ResizableWindow - Invalid position or size for handle: " .. tostring(handleName))
        end
        
        ::continue::
    end
end

--- Check if a point is within any resize handle
-- @tparam vec2 point - Point to test
-- @treturn string|nil - Handle name if point is within a handle, nil otherwise
function ResizableWindow:_getHandleAtPoint(point)
    if not self._config.resizable then return nil end
    
    for handleName, handle in pairs(self._resizeHandles) do
        local rect = handle.container.rect
        if point.x >= rect.lower.x and point.x <= rect.upper.x and 
           point.y >= rect.lower.y and point.y <= rect.upper.y then
            return handleName
        end
    end
    return nil
end

--- Apply size constraints to proposed dimensions with snap-to-size support
-- @tparam vec2 size - Proposed size
-- @treturn vec2 - Constrained size
-- @treturn table - Constraint info for visual feedback
function ResizableWindow:_applyConstraints(size)
    local constrained = vec2(size.x, size.y)
    local constraintInfo = {
        nearMinX = false,
        nearMinY = false,
        nearMaxX = false,
        nearMaxY = false,
        snappedX = false,
        snappedY = false
    }
    
    -- Snap-to-size functionality
    if self._config.snapToSize then
        local snapThreshold = PerformanceConfig.snapThreshold
        
        -- Snap to minimum size
        if math.abs(constrained.x - self._config.minSize.x) <= snapThreshold then
            constrained.x = self._config.minSize.x
            constraintInfo.snappedX = true
        end
        if math.abs(constrained.y - self._config.minSize.y) <= snapThreshold then
            constrained.y = self._config.minSize.y
            constraintInfo.snappedY = true
        end
        
        -- Snap to maximum size
        if math.abs(constrained.x - self._config.maxSize.x) <= snapThreshold then
            constrained.x = self._config.maxSize.x
            constraintInfo.snappedX = true
        end
        if math.abs(constrained.y - self._config.maxSize.y) <= snapThreshold then
            constrained.y = self._config.maxSize.y
            constraintInfo.snappedY = true
        end
        
        -- Snap to common aspect ratios or standard sizes
        local commonWidths = {400, 640, 800, 1024, 1280, 1600}
        local commonHeights = {300, 480, 600, 768, 960, 1200}
        
        for _, width in ipairs(commonWidths) do
            if math.abs(constrained.x - width) <= snapThreshold then
                constrained.x = width
                constraintInfo.snappedX = true
                break
            end
        end
        
        for _, height in ipairs(commonHeights) do
            if math.abs(constrained.y - height) <= snapThreshold then
                constrained.y = height
                constraintInfo.snappedY = true
                break
            end
        end
    end
    
    -- Check proximity to limits for visual feedback
    local proximityThreshold = PerformanceConfig.snapThreshold * 3
    constraintInfo.nearMinX = math.abs(constrained.x - self._config.minSize.x) <= proximityThreshold
    constraintInfo.nearMinY = math.abs(constrained.y - self._config.minSize.y) <= proximityThreshold
    constraintInfo.nearMaxX = math.abs(constrained.x - self._config.maxSize.x) <= proximityThreshold
    constraintInfo.nearMaxY = math.abs(constrained.y - self._config.maxSize.y) <= proximityThreshold
    
    -- Apply hard constraints
    constrained.x = math.max(constrained.x, self._config.minSize.x)
    constrained.y = math.max(constrained.y, self._config.minSize.y)
    constrained.x = math.min(constrained.x, self._config.maxSize.x)
    constrained.y = math.min(constrained.y, self._config.maxSize.y)
    
    -- Screen constraints if enabled
    if self._config.constrainToScreen then
        local resolution = getResolution()
        constrained.x = math.min(constrained.x, resolution.x * 0.9)
        constrained.y = math.min(constrained.y, resolution.y * 0.9)
    end
    
    return constrained, constraintInfo
end

--- Start resize operation with enhanced state management
-- @tparam string handleName - Name of the handle being dragged
-- @tparam vec2 mousePos - Current mouse position
function ResizableWindow:_startResize(handleName, mousePos)
    -- Validate window rect is accessible before starting resize
    local windowRect = self:_getSafeRect()
    if not windowRect then
        print("Error: ResizableWindow - Cannot start resize, window rect unavailable")
        return
    end
    
    -- Capture mouse to prevent loss of focus
    if Mouse and Mouse.capture then
        Mouse.capture(true)
        resizeState.mouseCaptured = true
    end
    
    resizeState.active = true
    resizeState.window = self
    resizeState.handle = handleName
    resizeState.startPos = mousePos
    resizeState.startSize = self._tabbedWindow.size
    resizeState.startWindowPos = self._tabbedWindow.position
    resizeState.mode = "capturing"
    resizeState.lastUpdateTime = appTimeSeconds()
    resizeState.previewSize = self._tabbedWindow.size
    resizeState.previewPos = self._tabbedWindow.position
    
    -- Mark handle as active and update visual state
    if self._resizeHandles[handleName] then
        self._resizeHandles[handleName].active = true
        self:_updateHandleVisuals(handleName, "active")
    end
    
    -- Show preview outline if enabled
    if self._config.showPreview and self._preview.outline then
        self:_showPreviewOutline(true)
    end
end

--- Update resize operation with performance optimization and visual feedback
-- @tparam vec2 mousePos - Current mouse position
function ResizableWindow:_updateResize(mousePos)
    if not resizeState.active or resizeState.window ~= self then return end
    
    local currentTime = appTimeSeconds()
    
    -- Performance throttling - limit update rate
    local timeSinceLastUpdate = currentTime - resizeState.lastUpdateTime
    if timeSinceLastUpdate < PerformanceConfig.minFrameTime then
        self._performance.frameSkipCount = self._performance.frameSkipCount + 1
        return
    end
    
    -- Check minimum mouse movement threshold
    if self._performance.lastMousePos then
        local mouseDelta = mousePos - self._performance.lastMousePos
        local moveDistance = math.sqrt(mouseDelta.x^2 + mouseDelta.y^2)
        if moveDistance < PerformanceConfig.mouseMoveThreshold then
            return
        end
    end
    
    local handleDef = HandleTypes[resizeState.handle]
    if not handleDef then return end
    
    local delta = mousePos - resizeState.startPos
    local newSize = handleDef.resize(delta, resizeState.startSize)
    local newPos = handleDef.reposition(delta, resizeState.startWindowPos)
    
    -- Apply constraints with feedback info
    local constrainedSize, constraintInfo = self:_applyConstraints(newSize)
    
    -- Store preview state
    resizeState.previewSize = constrainedSize
    resizeState.previewPos = newPos
    
    -- Update preview outline if enabled
    if self._config.showPreview and self._preview.outline then
        self:_updatePreviewOutline(newPos, constrainedSize, constraintInfo)
    end
    
    -- Update actual window (can be made optional for preview-only mode)
    self._tabbedWindow.size = constrainedSize
    self._tabbedWindow.position = newPos
    
    -- Update handles
    self:_updateResizeHandles()
    
    -- Update visual feedback based on constraints
    if constraintInfo.nearMinX or constraintInfo.nearMinY or 
       constraintInfo.nearMaxX or constraintInfo.nearMaxY then
        self:_updateHandleVisuals(resizeState.handle, "nearLimit")
    else
        self:_updateHandleVisuals(resizeState.handle, "active")
    end
    
    resizeState.mode = "resizing"
    resizeState.lastUpdateTime = currentTime
    self._performance.lastMousePos = mousePos
    self._performance.lastUpdateTime = currentTime
end

--- Finish resize operation with cleanup and callbacks
function ResizableWindow:_finishResize()
    if not resizeState.active or resizeState.window ~= self then return end
    
    resizeState.mode = "finalizing"
    
    -- Release mouse capture if we had it
    if resizeState.mouseCaptured then
        if Mouse and Mouse.capture then
            Mouse.capture(false)
        end
        resizeState.mouseCaptured = false
    end
    
    -- Hide preview outline
    if self._config.showPreview and self._preview.outline then
        self:_showPreviewOutline(false)
    end
    
    -- Reset handle visual states
    for handleName, handle in pairs(self._resizeHandles) do
        handle.active = false
        self:_updateHandleVisuals(handleName, "default")
    end
    
    -- Trigger layout update callback if present
    if self.onResized then
        self:onResized(self._tabbedWindow.size)
    end
    
    -- Log performance stats for debugging
    if self._performance.frameSkipCount > 0 then
        print(string.format("ResizableWindow: Skipped %d frames during resize for performance", 
                          self._performance.frameSkipCount))
    end
    
    -- Reset state
    resizeState.active = false
    resizeState.window = nil
    resizeState.handle = nil
    resizeState.startPos = nil
    resizeState.startSize = nil
    resizeState.startWindowPos = nil
    resizeState.mode = "idle"
    resizeState.previewSize = nil
    resizeState.previewPos = nil
    
    -- Reset performance counters
    self._performance.frameSkipCount = 0
    self._performance.lastMousePos = nil
end

--- Update handle visual appearance based on state
-- @tparam string handleName - Name of the handle to update
-- @tparam string state - Visual state: "default", "hover", "active", "nearLimit"
function ResizableWindow:_updateHandleVisuals(handleName, state)
    local handle = self._resizeHandles[handleName]
    if not handle or not self._config.showHandles then return end
    
    local currentTime = appTimeSeconds()
    local color
    
    if state == "hover" then
        -- Smooth transition effect for hover
        if not handle.hovered then
            handle.hoverStartTime = currentTime
            handle.hovered = true
        end
        local progress = math.min((currentTime - handle.hoverStartTime) / PerformanceConfig.hoverTransitionTime, 1.0)
        color = self:_interpolateColor(VisualConfig.defaultColor, VisualConfig.hoverColor, progress)
        
    elseif state == "active" then
        color = VisualConfig.activeColor
        
    elseif state == "nearLimit" then
        -- Pulsing effect when near size limits
        local pulse = math.sin(currentTime * VisualConfig.pulseSpeed) * 0.5 + 0.5
        color = self:_interpolateColor(VisualConfig.activeColor, VisualConfig.nearLimitColor, pulse)
        
    else -- default
        handle.hovered = false
        color = VisualConfig.defaultColor
    end
    
    handle.visual.color = color
    handle.lastVisualUpdate = currentTime
end

--- Interpolate between two colors
-- @tparam ColorARGB color1 - Starting color
-- @tparam ColorARGB color2 - Ending color  
-- @tparam number progress - Interpolation progress (0-1)
-- @treturn ColorARGB - Interpolated color
function ResizableWindow:_interpolateColor(color1, color2, progress)
    return ColorARGB(
        color1.a + (color2.a - color1.a) * progress,
        color1.r + (color2.r - color1.r) * progress,
        color1.g + (color2.g - color1.g) * progress,
        color1.b + (color2.b - color1.b) * progress
    )
end

--- Show or hide preview outline
-- @tparam boolean visible - Whether to show the outline
function ResizableWindow:_showPreviewOutline(visible)
    if not self._preview.outline then return end
    
    self._preview.outline.container.visible = visible
    self._preview.visible = visible
end

--- Update preview outline position and size with visual feedback
-- @tparam vec2 position - New position
-- @tparam vec2 size - New size
-- @tparam table constraintInfo - Constraint information for visual feedback
function ResizableWindow:_updatePreviewOutline(position, size, constraintInfo)
    if not self._preview.outline then return end
    
    local thickness = VisualConfig.guideThickness
    local rects = self._preview.outline.rects
    
    -- Update outline rectangles (top, right, bottom, left)
    rects[1].rect = Rect(position.x, position.y, position.x + size.x, position.y + thickness) -- top
    rects[2].rect = Rect(position.x + size.x - thickness, position.y, position.x + size.x, position.y + size.y) -- right  
    rects[3].rect = Rect(position.x, position.y + size.y - thickness, position.x + size.x, position.y + size.y) -- bottom
    rects[4].rect = Rect(position.x, position.y, position.x + thickness, position.y + size.y) -- left
    
    -- Update colors based on constraint info
    local color = VisualConfig.previewColor
    if constraintInfo.nearMinX or constraintInfo.nearMinY or constraintInfo.nearMaxX or constraintInfo.nearMaxY then
        color = VisualConfig.nearLimitColor
    end
    if constraintInfo.snappedX or constraintInfo.snappedY then
        color = VisualConfig.hoverColor -- Use hover color for snapped state
    end
    
    for _, rect in ipairs(rects) do
        rect.color = color
    end
end

--- Handle mouse capture loss scenarios
function ResizableWindow:_handleMouseCaptureLoss()
    if resizeState.active and resizeState.window == self then
        -- Gracefully finish the resize operation
        self:_finishResize()
    end
    
    -- Reset all hover states
    for _, handle in pairs(self._resizeHandles) do
        if handle.hovered then
            handle.hovered = false
            self:_updateHandleVisuals(handle.type, "default")
        end
    end
end

--- Cleanup method for when window is destroyed
function ResizableWindow:destroy()
    -- Remove from global registry
    for i, window in ipairs(resizableWindows) do
        if window == self then
            table.remove(resizableWindows, i)
            break
        end
    end
    
    -- Cancel any active resize
    if resizeState.active and resizeState.window == self then
        self:_finishResize()
    end
    
    -- Clean up preview elements
    if self._preview.outline and self._preview.outline.container then
        self._preview.outline.container:destroy()
    end
    
    if self._preview.guides and self._preview.guides.container then
        self._preview.guides.container:destroy()
    end
    
    -- Clean up handles
    for _, handle in pairs(self._resizeHandles) do
        if handle.container then
            handle.container:destroy()
        end
    end
    
    -- Destroy underlying window
    if self._tabbedWindow and self._tabbedWindow.destroy then
        self._tabbedWindow:destroy()
    end
end

--- Property forwarding to underlying CustomTabbedWindow
ResizableWindow.__index = function(self, key)
    -- Check for ResizableWindow-specific properties first
    local value = rawget(ResizableWindow, key)
    if value ~= nil then
        return value
    end
    
    -- Handle rect property safely to avoid AzimuthLib recursive access bug
    if key == "rect" then
        return self:_getSafeRect()
    end
    
    -- Forward to underlying tabbedWindow
    return self._tabbedWindow[key]
end

ResizableWindow.__newindex = function(self, key, value)
    -- Intercept rect changes to update handles
    if key == "rect" and self._config and self._config.resizable then
        -- Use safe assignment for rect property
        local success, error = pcall(function()
            self._tabbedWindow[key] = value
        end)
        if success then
            self:_updateResizeHandles()
        else
            print("Warning: ResizableWindow - Failed to set rect property: " .. tostring(error))
        end
    elseif key == "size" and self._config and self._config.resizable then
        self._tabbedWindow[key] = value
        self:_updateResizeHandles()
    elseif key == "position" and self._config and self._config.resizable then
        self._tabbedWindow[key] = value
        self:_updateResizeHandles()
    else
        -- Forward to underlying tabbedWindow
        self._tabbedWindow[key] = value
    end
end

-- Global mouse event handlers with enhanced robustness
function onMousePressed(x, y, button)
    if button ~= 1 then return end -- Only handle left mouse button
    
    local mousePos = vec2(x, y)
    
    -- Handle potential mouse capture loss from previous operations
    for _, window in ipairs(resizableWindows) do
        if resizeState.active and resizeState.window == window then
            window:_handleMouseCaptureLoss()
            break
        end
    end
    
    -- Check for resize handle clicks (prioritize frontmost windows)
    for i = #resizableWindows, 1, -1 do
        local window = resizableWindows[i]
        if window._config.resizable then
            local handle = window:_getHandleAtPoint(mousePos)
            if handle then
                window:_startResize(handle, mousePos)
                return true -- Indicate event was handled
            end
        end
    end
    
    return false
end

function onMouseMove(x, y)
    local mousePos = vec2(x, y)
    local currentTime = appTimeSeconds()
    
    -- Handle active resize with throttling
    if resizeState.active and resizeState.window then
        -- Additional safety check for rapid mouse movements
        local timeSinceLastUpdate = currentTime - (resizeState.lastUpdateTime or 0)
        if timeSinceLastUpdate >= PerformanceConfig.debounceTime then
            resizeState.window:_updateResize(mousePos)
        end
        return true -- Event handled
    end
    
    -- Handle hover effects with performance optimization
    local anyHoverChanged = false
    
    -- Process windows in reverse order (frontmost first)
    for i = #resizableWindows, 1, -1 do
        local window = resizableWindows[i]
        if window._config.resizable then
            local handle = window:_getHandleAtPoint(mousePos)
            
            -- Update hover state for all handles with enhanced visual feedback
            for handleName, handleData in pairs(window._resizeHandles) do
                local wasHovered = handleData.hovered
                local shouldHover = (handleName == handle)
                
                if shouldHover ~= wasHovered then
                    anyHoverChanged = true
                    
                    -- Update visual state with smooth transitions
                    if shouldHover then
                        window:_updateHandleVisuals(handleName, "hover")
                        -- Set cursor for resize direction if supported
                        if handleData.definition.cursor then
                            -- Could add cursor changing here if supported by Avorion
                        end
                    else
                        window:_updateHandleVisuals(handleName, "default")
                    end
                end
            end
            
            -- If we found a handle, we're done (don't check windows behind this one)
            if handle then
                break
            end
        end
    end
    
    return anyHoverChanged
end

function onMouseReleased(x, y, button)
    if button ~= 1 then return end -- Only handle left mouse button
    
    -- Handle resize completion with safety checks
    if resizeState.active and resizeState.window then
        local window = resizeState.window
        
        -- Ensure window still exists and is valid
        local stillValid = false
        for _, w in ipairs(resizableWindows) do
            if w == window then
                stillValid = true
                break
            end
        end
        
        if stillValid then
            window:_finishResize()
        else
            -- Window was destroyed during resize, clean up state
            resizeState.active = false
            resizeState.window = nil
            resizeState.handle = nil
            resizeState.startPos = nil
            resizeState.startSize = nil
            resizeState.startWindowPos = nil
            resizeState.mode = "idle"
            
            if resizeState.mouseCaptured and Mouse and Mouse.capture then
                Mouse.capture(false)
                resizeState.mouseCaptured = false
            end
        end
        
        return true -- Event handled
    end
    
    return false
end

--- Global cleanup function for emergency situations
function onResizableWindowEmergencyCleanup()
    -- Force cleanup of all resize state
    if resizeState.active then
        if resizeState.mouseCaptured and Mouse and Mouse.capture then
            Mouse.capture(false)
        end
        
        resizeState.active = false
        resizeState.window = nil
        resizeState.handle = nil
        resizeState.startPos = nil
        resizeState.startSize = nil
        resizeState.startWindowPos = nil
        resizeState.mode = "idle"
        resizeState.mouseCaptured = false
        resizeState.previewSize = nil
        resizeState.previewPos = nil
    end
    
    -- Reset all window hover states
    for _, window in ipairs(resizableWindows) do
        for _, handle in pairs(window._resizeHandles) do
            handle.hovered = false
            handle.active = false
            if window._config.showHandles then
                handle.visual.color = VisualConfig.defaultColor
            end
        end
        
        -- Hide any visible previews
        if window._preview.outline then
            window:_showPreviewOutline(false)
        end
    end
end

--- Factory function following AzimuthLib pattern
local function new(namespace, parent, rect, options)
    return ResizableWindow.new(namespace, parent, rect, options)
end

return setmetatable({new = new}, {__call = function(_, ...) return new(...) end})