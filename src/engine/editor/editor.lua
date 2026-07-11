local EDITOR_DEFAULT_WIDTH = 1280
local EDITOR_DEFAULT_HEIGHT = 800
local EDITOR_SESSION_VERSION = 1
local EDITOR_SESSION_DIRECTORY = "editor"

local function copyTable(source)
    local result = setmetatable({}, getmetatable(source))
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function gameTraceback(error_value)
    if type(error_value) == "table" then
        error_value = error_value.msg or error_value.critical or tostring(error_value)
    end
    return debug.traceback(tostring(error_value), 2)
end

---@class Editor
local Editor = {
    editor_mode = true,
    owns_window_input = true
}

local function fromPixels(value)
    return love.window.fromPixels and love.window.fromPixels(value) or value
end

local function toPixels(value)
    return love.window.toPixels and love.window.toPixels(value) or value
end

local function hasMap(id)
    return id and (Registry.getMap(id) or Registry.getMapData(id))
end

local function safeProjectId(id)
    return tostring(id or "unknown"):gsub("[^%w%._%-]", "_")
end

function Editor:init() end

function Editor:getSessionPath()
    return EDITOR_SESSION_DIRECTORY .. "/" .. safeProjectId(self.project_id) .. ".json"
end

function Editor:loadSession()
    local path = self:getSessionPath()
    if not love.filesystem.getInfo(path) then return nil end
    local success, result = pcall(function()
        return JSON.decode(love.filesystem.read(path))
    end)
    if not success or type(result) ~= "table" then
        local message = success and "expected a JSON object" or tostring(result)
        self:addWarning("Could not restore the editor session: " .. message, nil, "editor_session")
        return nil
    end
    if type(result.version) == "number" and result.version > EDITOR_SESSION_VERSION then
        self:addWarning("Editor session was created by a newer format and was not restored",
            nil, "editor_session")
        return nil
    end
    return result
end

function Editor:getNextDocumentPanelId()
    local index = 1
    while self.dockspace.panels["map_document:" .. index] do index = index + 1 end
    return "map_document:" .. index
end

function Editor:createMapDocument(id, panel_id)
    if not hasMap(id) then return nil end
    if type(panel_id) ~= "string" or not panel_id:match("^map_document:%d+$")
        or self.dockspace.panels[panel_id] then
        panel_id = self:getNextDocumentPanelId()
    end
    local document = EditorMapDocument(self, id)
    local map_view = EditorMapView(self, document)
    local panel = EditorPanel(panel_id, id, map_view, {
        minimum_width = SCREEN_WIDTH,
        minimum_height = SCREEN_HEIGHT + 28,
        preferred_width = SCREEN_WIDTH,
        preferred_height = SCREEN_HEIGHT + 28,
        on_remove = function()
            self:removeMapDocument(document)
        end,
        on_activate = function()
            if not self.suppress_panel_activation then
                self:activateMapDocument(document, { select_panel = false })
            end
        end
    })
    panel.map_document = document
    panel.map_view = map_view
    document.panel = panel
    document.map_view = map_view
    document.game_view = map_view
    document.game_view_state = nil
    table.insert(self.map_documents, document)
    self.dockspace:registerPanel(panel, "center")
    return document
end

function Editor:restoreDocumentView(document, state)
    if type(state) ~= "table" then return end
    local view = document.game_view
    if type(state.zoom) == "number" then
        view.view_zoom = MathUtils.clamp(state.zoom, view.minimum_zoom, view.maximum_zoom)
    end
    if type(state.canvas_x) == "number" and type(state.canvas_y) == "number" then
        view:setCanvasPosition(state.canvas_x, state.canvas_y)
    end
end

function Editor:restoreGameViewState(document, state)
    if type(state) ~= "table" then return end
    document.game_view_state = {
        canvas_x = type(state.canvas_x) == "number" and state.canvas_x or nil,
        canvas_y = type(state.canvas_y) == "number" and state.canvas_y or nil,
        zoom = type(state.zoom) == "number" and state.zoom or nil
    }
end

function Editor:captureGameViewState(document)
    if self.live_document == document and self.game_preview then
        return {
            canvas_x = self.game_preview.canvas_x,
            canvas_y = self.game_preview.canvas_y,
            zoom = self.game_preview.view_zoom
        }
    end
    return document.game_view_state and TableUtils.copy(document.game_view_state, true) or nil
end

function Editor:captureSession()
    local session = {
        version = EDITOR_SESSION_VERSION,
        project_id = self.project_id,
        tile_editing_mode = self.tile_editing_mode,
        tile_grid = self.show_tile_grid,
        standalone_preview_enabled = self:isStandaloneGamePreviewEnabled(),
        standalone_preview_map_id = self.standalone_preview_map_id,
        active_panel_id = self.active_document and self.active_document.panel.id,
        preferences = {
            custom_cursors = self.use_custom_cursors,
            deltarune_font = self.use_deltarune_font
        },
        documents = {},
        layout = self:captureLayout(),
        window = { width = love.graphics.getWidth(), height = love.graphics.getHeight() }
    }
    for _, document in ipairs(self.map_documents or {}) do
        local view = document.game_view
        local saved_document = {
            panel_id = document.panel.id,
            primary_map_id = document.primary_map_id,
            maps = {},
            view = {
                canvas_x = view.canvas_x,
                canvas_y = view.canvas_y,
                zoom = view.view_zoom
            },
            game_view = self:captureGameViewState(document)
        }
        local primary = document:getPrimaryMap()
        for _, entry in ipairs(document.maps) do
            if entry ~= primary and entry.explicit_companion then
                table.insert(saved_document.maps, { id = entry.id, x = entry.x, y = entry.y })
            end
        end
        table.insert(session.documents, saved_document)
    end
    return session
end

function Editor:saveSession()
    if not self.dockspace or not self.map_documents or not self.project_id then return false end
    local success, encoded = pcall(JSON.encode, self:captureSession())
    if not success then
        print("Could not encode editor session: " .. tostring(encoded))
        return false
    end
    love.filesystem.createDirectory(EDITOR_SESSION_DIRECTORY)
    local written, message = love.filesystem.write(self:getSessionPath(), encoded)
    if not written then
        print("Could not save editor session: " .. tostring(message))
        return false
    end
    return true
end

function Editor:setupWindow(session)
    local width, height, flags = love.window.getMode()
    local window_x, window_y, display = love.window.getPosition()
    local game_offset_x, game_offset_y = Kristal.getSideOffsets()
    local game_scale = Kristal.getGameScale()
    local game_center_x = window_x + fromPixels(game_offset_x + (SCREEN_WIDTH * game_scale / 2))
    local game_center_y = window_y + fromPixels(game_offset_y + (SCREEN_HEIGHT * game_scale / 2))
    self.previous_window = {
        width = width,
        height = height,
        x = window_x,
        y = window_y,
        display = display,
        flags = TableUtils.copy(flags, true)
    }
    self.previous_mouse_visible = love.mouse.isVisible()
    self.previous_mouse_cursor = love.mouse.getCursor()

    local desktop_width, desktop_height = love.window.getDesktopDimensions(flags.display or 1)
    local current_width = flags.fullscreen and 0 or love.graphics.getWidth()
    local current_height = flags.fullscreen and 0 or love.graphics.getHeight()
    local saved_width = session and type(session.window) == "table" and session.window.width
    local saved_height = session and type(session.window) == "table" and session.window.height
    local requested_width = type(saved_width) == "number" and saved_width or math.max(current_width, EDITOR_DEFAULT_WIDTH)
    local requested_height = type(saved_height) == "number" and saved_height or math.max(current_height, EDITOR_DEFAULT_HEIGHT)
    local editor_width = math.min(desktop_width, math.max(SCREEN_WIDTH + 570, requested_width))
    local editor_height = math.min(desktop_height,
        math.max(SCREEN_HEIGHT + EditorMenuBar.HEIGHT + EditorMessageBar.HEIGHT + 28, requested_height))
    local editor_flags = TableUtils.copy(flags, true)
    editor_flags.fullscreen = false
    editor_flags.resizable = true
    editor_flags.minwidth = math.min(editor_width, SCREEN_WIDTH + 570)
    editor_flags.minheight = math.min(editor_height,
        SCREEN_HEIGHT + EditorMenuBar.HEIGHT + EditorMessageBar.HEIGHT + 28)
    love.window.updateMode(fromPixels(editor_width), fromPixels(editor_height), editor_flags)
    self:centerWindow(display, desktop_width, desktop_height)
    Kristal.refreshWindowText()
    love.mouse.setVisible(true)
    love.window.setTitle((Mod and Mod.info.name or "Kristal") .. " - Editor")
    return game_center_x, game_center_y
end

function Editor:registerMenuBar()
    self.menu_bar:registerToggle("edit", "tile_editing", "Map Editing View (Tab)",
        function() return self.tile_editing_mode end,
        function(enabled) self:setTileEditingMode(enabled) end)
    self.menu_bar:registerToggle("view", "custom_cursors", "Use Custom Cursors",
        function() return self.use_custom_cursors end,
        function(enabled) self:setCustomCursorsEnabled(enabled) end)
    self.menu_bar:registerToggle("view", "deltarune_font", "Use Deltarune Font",
        function() return self.use_deltarune_font end,
        function(enabled) self:setDeltaruneFontEnabled(enabled) end)
    self.menu_bar:registerToggle("view", "tile_grid", "Tile Grid (G)",
        function() return self.show_tile_grid end,
        function(enabled) self.show_tile_grid = enabled == true end)
    self.menu_bar:registerItem("view", "reset_layout", "Reset to Default", {
        on_activate = function() self:resetPanelLayout() end
    })
    self.menu_bar:registerProvider("window", "panels", function()
        local items = {}
        for _, panel in ipairs(self.dockspace.panel_order) do
            local current_panel = panel
            if current_panel.recoverable then
                table.insert(items, {
                    id = current_panel.id,
                    label = current_panel.title,
                    get_checked = function() return current_panel.visible end,
                    on_activate = function()
                        self.dockspace:setPanelVisible(current_panel, not current_panel.visible)
                    end
                })
            end
        end
        return items
    end)
end

function Editor:setupMapDocuments(session)
    local restored_by_panel = {}
    local saved_documents = session and type(session.documents) == "table" and session.documents or {}
    for _, saved_document in ipairs(saved_documents) do
        if type(saved_document) == "table" and hasMap(saved_document.primary_map_id)
            and not self:findMapDocument(saved_document.primary_map_id) then
            local document = self:createMapDocument(saved_document.primary_map_id, saved_document.panel_id)
            if document then
                restored_by_panel[document.panel.id] = document
                local saved_maps = type(saved_document.maps) == "table" and saved_document.maps or {}
                for _, saved_map in ipairs(saved_maps) do
                    if type(saved_map) == "table" and saved_map.id ~= document.primary_map_id
                        and hasMap(saved_map.id) then
                        document:addMap(saved_map.id,
                            type(saved_map.x) == "number" and saved_map.x or 0,
                            type(saved_map.y) == "number" and saved_map.y or 0)
                    end
                end
                self:restoreDocumentView(document, saved_document.view)
                self:restoreGameViewState(document, saved_document.game_view)
            end
        end
    end

    local context_document = self:findMapDocument(self.map_id)
    if not context_document and hasMap(self.map_id) then
        context_document = self:createMapDocument(self.map_id)
    end
    if #self.map_documents == 0 then error("Editor session has no valid map document") end

    self.game_preview = EditorGameView(self, context_document or self.map_documents[1])
    self.game_view = self.game_preview
    self.live_document = nil
    self.standalone_preview_map_id = session and hasMap(session.standalone_preview_map_id)
        and session.standalone_preview_map_id
        or (context_document or self.map_documents[1]).primary_map_id
    self.standalone_preview_document = EditorMapDocument(self, self.standalone_preview_map_id)
    if session and session.game_preview_view and context_document and not context_document.game_view_state then
        self:restoreGameViewState(context_document, session.game_preview_view)
    end
    return context_document, restored_by_panel
end

function Editor:setupPanels(session)
    self.maps_panel = self.dockspace:registerPanel(EditorPanel("maps", "Maps", self.map_browser, {
        minimum_width = 180,
        preferred_width = 260,
        recoverable = true
    }), "left")
    self.layers_panel = self.dockspace:registerPanel(EditorPanel("layers", "Layers", self.layers_browser, {
        minimum_width = 220,
        minimum_height = 360,
        preferred_width = 300,
        recoverable = true
    }), "right")
    self.properties_panel = self.dockspace:registerPanel(EditorPanel(
        "properties", "Properties", self.properties_browser, {
            minimum_width = 220,
            minimum_height = 180,
            preferred_width = 300,
            preferred_height = 300,
            recoverable = true
        }), "right")
    self.dockspace:dockPanelSplit(self.properties_panel, self.layers_panel.stack, "bottom")
    self.game_preview_panel = self.dockspace:registerPanel(EditorPanel(
        "game_preview", "Game Preview", self.game_preview, {
            visible = true,
            minimum_width = 320,
            minimum_height = 240,
            preferred_width = SCREEN_WIDTH,
            preferred_height = SCREEN_HEIGHT + 28,
            recoverable = true,
            on_activate = function()
                if self.game_preview_panel.visible then self.dockspace:setFocus(self.game_preview) end
            end,
            on_visibility_changed = function(_, visible)
                self:setStandaloneGamePreviewEnabled(visible)
            end
        }), "center")
    EditorPlugins:createPanels(self)
    self.dockspace.sizes.left = 260
    self.dockspace.sizes.right = 300
    self.dockspace.minimum_center_width = SCREEN_WIDTH
    self.dockspace.minimum_center_height = SCREEN_HEIGHT + 28
    self.menu_bar:setBounds(0, 0, love.graphics.getWidth())
    self.message_bar:setBounds(0, love.graphics.getHeight() - EditorMessageBar.HEIGHT, love.graphics.getWidth())
    self.dockspace:setBounds(0, EditorMenuBar.HEIGHT, love.graphics.getWidth(),
        love.graphics.getHeight() - EditorMenuBar.HEIGHT - EditorMessageBar.HEIGHT)

    self.default_layout = self:captureLayout()
    if session and type(session.layout) == "table" then
        local had_properties_panel = session.layout.panels and session.layout.panels.properties
        local saved_layout = TableUtils.copy(session.layout, true)
        if saved_layout.panels and saved_layout.panels.game_preview then
            saved_layout.panels.game_preview.visible = session.standalone_preview_enabled ~= false
        end
        local restored, message = pcall(function() self:restoreLayout(saved_layout) end)
        if not restored then
            self:restoreLayout(self.default_layout)
            self:addWarning("Could not restore the editor panel layout: " .. tostring(message),
                nil, "editor_session")
        elseif not had_properties_panel then
            self.dockspace:dockPanelSplit(self.properties_panel, self.layers_panel.stack, "bottom")
        end
    end
end

function Editor:restoreEntryState(session, options, context_document, restored_by_panel, game_center_x, game_center_y)
    local active_document
    if options.restore_active_document and session then
        active_document = restored_by_panel[session.active_panel_id]
    end
    active_document = active_document or context_document or self.map_documents[1]
    local desired_tile_mode = options.game_preview ~= true
    self.suppress_panel_activation = false
    self:activateMapDocument(active_document, { select_panel = false, set_mode = false })
    if self.entry_transition and desired_tile_mode then
        self.pending_tile_editing_mode = true
        self:setTileEditingMode(false)
    else
        self:setTileEditingMode(desired_tile_mode)
    end
    if not options.restore_active_document then
        self:positionGameCanvasAtScreen(game_center_x, game_center_y)
    end
    if self.game_preview_panel.visible then self:setStandaloneGamePreviewEnabled(true) end
end

function Editor:enter(previous, options)
    options = options or {}
    self.source_state = options.source_state or previous
    self.entry_transition = options.entry_transition
    self.exit_transition = nil
    self.session_saved_for_exit = false
    self.pending_tile_editing_mode = nil
    self.tile_editing_mode = false
    self.show_tile_grid = false
    self.game_faulted = false
    self.game_fault_trace = nil
    self.game_preview_paused = false
    self.forwarded_mouse_buttons = {}
    self.object_selection_mouse_buttons = {}
    self.consumed_editor_keys = {}
    self.game_preview_snapshot = nil
    self.game_preview_snapshot_document = nil
    self.game_preview_snapshot_save_id = nil
    self.game_music_suspended_by_editor = false
    self.project_id = options.project_id or (Mod and Mod.info.id)
    self.map_id = options.map_id or (Game.world and Game.world.map and Game.world.map.id)
    self.message_bar = EditorMessageBar()
    local session = self:loadSession()
    local preferences = session and type(session.preferences) == "table" and session.preferences or {}
    self.show_tile_grid = session and session.tile_grid == true or false
    self.use_custom_cursors = preferences.custom_cursors ~= false
    self.use_deltarune_font = preferences.deltarune_font ~= false
    self.previous_lock_movement = Game.lock_movement
    self.game_preview_movement_lock = self.previous_lock_movement
    self.game_preview_lock_before_pause = nil
    Game.lock_movement = true

    local game_center_x, game_center_y = self:setupWindow(session)

    self.dockspace = EditorDockSpace()
    self.suppress_panel_activation = true
    self.map_documents = {}
    self.active_document = nil
    self.game_view = nil
    self.map_browser = EditorMapBrowser(self)
    self.layers_browser = EditorLayersPanel(self)
    self.properties_browser = EditorPropertiesPanel(self)
    self.menu_bar = EditorMenuBar(self)
    self.editor_cursor = EditorCursor()
    self.editor_cursor:setCustomEnabled(self.use_custom_cursors)

    local context_document, restored_by_panel = self:setupMapDocuments(session)
    EditorPlugins:initialize(self)
    self:registerMenuBar()
    EditorPlugins:applyMenuBar(self)
    self:setupPanels(session)
    self:restoreEntryState(session, options, context_document, restored_by_panel,
        game_center_x, game_center_y)
end

function Editor:leave()
    self:clearGameObjectSelection()
    EditorPlugins:shutdown(self)
    if not self.session_saved_for_exit then self:saveSession() end
    self.dockspace:setFocus(nil)
    local game_center_x, game_center_y = self:getGameCanvasScreenCenter()
    local window = self.previous_window
    if window then love.window.updateMode(window.width, window.height, window.flags) end
    Kristal.refreshWindowText()
    local game_offset_x, game_offset_y = Kristal.getSideOffsets()
    local game_scale = Kristal.getGameScale()
    local window_x = game_center_x - fromPixels(game_offset_x + (SCREEN_WIDTH * game_scale / 2))
    local window_y = game_center_y - fromPixels(game_offset_y + (SCREEN_HEIGHT * game_scale / 2))
    love.window.setPosition(MathUtils.round(window_x), MathUtils.round(window_y), window and window.display)
    Kristal.setDesiredWindowTitleAndIcon()
    if self.previous_mouse_cursor then
        love.mouse.setCursor(self.previous_mouse_cursor)
    else
        love.mouse.setCursor()
    end
    Kristal.updateCursor()
    love.mouse.setVisible(self.previous_mouse_visible)
    Game.lock_movement = self.previous_lock_movement
    self.entry_transition = nil
    self.exit_transition = nil
    self.source_state = nil
    self.dockspace = nil
    self.menu_bar = nil
    self.editor_cursor = nil
    self.previous_mouse_cursor = nil
    self.message_bar = nil
    self.map_documents = nil
    self.active_document = nil
    self.game_preview = nil
    self.game_view = nil
    self.game_panel = nil
    self.game_preview_panel = nil
    self.layers_browser = nil
    self.layers_panel = nil
    self.properties_browser = nil
    self.properties_panel = nil
    self.properties_target_owner = nil
    self.standalone_preview_document = nil
    self.standalone_preview_map_id = nil
    self.game_preview_paused = nil
    self.live_document = nil
    self.suppress_panel_activation = nil
    self.session_saved_for_exit = nil
    self.pending_tile_editing_mode = nil
    self.use_custom_cursors = nil
    self.use_deltarune_font = nil
    self.show_tile_grid = nil
    self.forwarded_mouse_buttons = nil
    self.object_selection_mouse_buttons = nil
    self.consumed_editor_keys = nil
    self.default_layout = nil
    self.game_preview_snapshot = nil
    self.game_preview_snapshot_document = nil
    self.game_preview_snapshot_save_id = nil
    self.game_music_suspended_by_editor = nil
    self.game_preview_movement_lock = nil
    self.game_preview_lock_before_pause = nil
end

function Editor:setPropertiesTarget(target, owner)
    self.properties_target_owner = owner
    if self.properties_browser then self.properties_browser:setTarget(target) end
end

function Editor:clearPropertiesTarget(owner)
    if owner and self.properties_target_owner ~= owner then return false end
    self.properties_target_owner = nil
    if self.properties_browser then self.properties_browser:setTarget(nil) end
    return true
end

function Editor:setCustomCursorsEnabled(enabled)
    self.use_custom_cursors = enabled ~= false
    if self.editor_cursor then self.editor_cursor:setCustomEnabled(self.use_custom_cursors) end
end

function Editor:setDeltaruneFontEnabled(enabled)
    self.use_deltarune_font = enabled ~= false
end

function Editor:addDiagnostic(severity, message, detail, source)
    return self.message_bar:add(severity, message, detail, source)
end

function Editor:addWarning(message, detail, source)
    return self.message_bar:addWarning(message, detail, source)
end

function Editor:addError(message, detail, source)
    return self.message_bar:addError(message, detail, source)
end

function Editor:clearDiagnostics(source)
    self.message_bar:clear(source)
end

function Editor:recordGameError(phase, trace)
    if self.game_faulted then return end
    self.game_faulted = true
    self.game_fault_trace = trace
    Game.lock_movement = true
    local summary = trace:match("([^\n]+)") or "Unknown game error"
    self:addError(string.format("Game preview %s failed; preview paused: %s", phase, summary), trace, "game")
    print(string.format("Editor caught a game preview %s error:\n%s", phase, trace))
end

function Editor:runGameCallback(phase, callback)
    if self.game_faulted then return false end
    local success, result = xpcall(callback, gameTraceback)
    if not success then
        self:recordGameError(phase, result)
        return false
    end
    return true, result
end

function Editor:runGameDraw(phase, callback)
    if self.game_faulted then return false end

    local original_canvas = love.graphics.getCanvas()
    local original_scale_x, original_scale_y = CURRENT_SCALE_X, CURRENT_SCALE_Y
    local draw_state = {
        canvas_stack = copyTable(Draw._canvas_stack),
        scissor_stack = copyTable(Draw._scissor_stack),
        shader_stack = copyTable(Draw._shader_stack),
        locked_canvas = copyTable(Draw._locked_canvas),
        locked_canvas_stack = copyTable(Draw._locked_canvas_stack)
    }
    local original_push, original_pop = love.graphics.push, love.graphics.pop
    local graphics_depth = 0

    original_push("all")
    graphics_depth = 1
    love.graphics.push = function(...)
        original_push(...)
        graphics_depth = graphics_depth + 1
    end
    love.graphics.pop = function(...)
        original_pop(...)
        graphics_depth = graphics_depth - 1
    end

    local success, result = xpcall(callback, gameTraceback)
    love.graphics.push, love.graphics.pop = original_push, original_pop

    local draw_stacks_balanced = #Draw._canvas_stack == #draw_state.canvas_stack
        and #Draw._shader_stack == #draw_state.shader_stack
        and #Draw._locked_canvas_stack == #draw_state.locked_canvas_stack
    if success and (graphics_depth ~= 1 or not draw_stacks_balanced) then
        success = false
        result = gameTraceback(string.format(
            "Game preview draw left graphics state unbalanced (graphics %d, canvas %d/%d, scissor %d/%d, shader %d/%d, locks %d/%d)",
            graphics_depth, #Draw._canvas_stack, #draw_state.canvas_stack,
            #Draw._scissor_stack, #draw_state.scissor_stack,
            #Draw._shader_stack, #draw_state.shader_stack,
            #Draw._locked_canvas_stack, #draw_state.locked_canvas_stack))
    end

    while graphics_depth > 0 do
        local popped = pcall(original_pop)
        if not popped then break end
        graphics_depth = graphics_depth - 1
    end

    if not success then
        Draw._canvas_stack = draw_state.canvas_stack
        Draw._scissor_stack = draw_state.scissor_stack
        Draw._shader_stack = draw_state.shader_stack
        Draw._locked_canvas = draw_state.locked_canvas
        Draw._locked_canvas_stack = draw_state.locked_canvas_stack
        Draw.setCanvas(original_canvas)
        CURRENT_SCALE_X, CURRENT_SCALE_Y = original_scale_x, original_scale_y
        self:recordGameError(phase, result)
        return false
    end
    return true, result
end

function Editor:getGameCanvasScreenCenter()
    local window_x, window_y = love.window.getPosition()
    local game_x, game_y = self.game_preview:getGlobalPosition()
    local canvas_center_x, canvas_center_y = self.game_preview:getCanvasDisplayCenter()
    return window_x + fromPixels(game_x + canvas_center_x),
        window_y + fromPixels(game_y + canvas_center_y)
end

function Editor:positionGameCanvasAtScreen(screen_x, screen_y)
    local window_x, window_y = love.window.getPosition()
    local game_x, game_y = self.game_preview:getGlobalPosition()
    local canvas_x = toPixels(screen_x - window_x) - game_x - SCREEN_WIDTH * self.game_preview.view_zoom / 2
    local canvas_y = toPixels(screen_y - window_y) - game_y - SCREEN_HEIGHT * self.game_preview.view_zoom / 2
    self.game_preview:setCanvasPosition(canvas_x, canvas_y)
end

function Editor:centerWindow(display, desktop_width, desktop_height)
    local window_width, window_height = love.window.getMode()
    local desktop_window_width = fromPixels(desktop_width)
    local desktop_window_height = fromPixels(desktop_height)
    love.window.setPosition(
        MathUtils.round((desktop_window_width - window_width) / 2),
        MathUtils.round((desktop_window_height - window_height) / 2),
        display
    )
end

function Editor:update()
    if self.live_document and not self.game_preview_paused and not self.exit_transition
        and self.source_state and self.source_state.update and not self.game_faulted then
        self:runGameCallback("update", function() self.source_state:update() end)
    end
    self.menu_bar:setBounds(0, 0, love.graphics.getWidth())
    self.message_bar:setBounds(0, love.graphics.getHeight() - EditorMessageBar.HEIGHT, love.graphics.getWidth())
    self.dockspace:setBounds(0, EditorMenuBar.HEIGHT, love.graphics.getWidth(),
        love.graphics.getHeight() - EditorMenuBar.HEIGHT - EditorMessageBar.HEIGHT)
    self.dockspace:update(DT)

    if self.entry_transition then
        self.entry_transition:update(DT)
        if self.entry_transition:isComplete() then
            self.entry_transition = nil
            if self.pending_tile_editing_mode then
                self.pending_tile_editing_mode = nil
                self:setTileEditingMode(true)
            end
        end
    elseif self.exit_transition then
        self.exit_transition:update(DT)
    end

end

function Editor:drawGame()
    if self.live_document and self.source_state and self.source_state.draw and not self.game_faulted then
        self:runGameDraw("draw", function() self.source_state:draw() end)
    end
    local transition = self.entry_transition or self.exit_transition
    if transition then transition:draw() end
end

function Editor:drawEditor(canvas)
    love.graphics.origin()
    love.graphics.clear(0.055, 0.055, 0.065, 1)
    self.game_preview:setCanvas(canvas)
    self.dockspace:draw()
    self.message_bar:draw()
    self.menu_bar:draw()
    local mouse_x, mouse_y = love.mouse.getPosition()
    self.editor_cursor:setType(self:getCursorType(mouse_x, mouse_y))
end

function Editor:getCursorType(x, y)
    if self.entry_transition or self.exit_transition then return "cannot" end
    if self.message_bar:containsPoint(x, y) then return "default" end
    local menu_cursor = self.menu_bar:getCursorType(x, y)
    if menu_cursor ~= "default" then return menu_cursor end
    return self.dockspace:getCursorType(x, y)
end

function Editor:setTileEditingMode(enabled)
    if enabled then
        if not self.active_document then return false end
        self.tile_editing_mode = true
        if self:isStandaloneGamePreviewEnabled() then
            local panel = self.active_document.panel
            panel:setContent(self.active_document.map_view)
            if panel.stack then panel.stack:setActivePanel(panel) end
            self.dockspace:setFocus(self.active_document.map_view)
            return true
        end
        self:detachGamePreview()
        self:suspendGamePreviewAudio()
        local panel = self.active_document.panel
        if panel and not panel.visible then
            self.dockspace:setPanelVisible(panel, true, panel.last_region or "center")
        end
        if panel and panel.stack then panel.stack:setActivePanel(panel) end
        self.dockspace:setFocus(self.active_document.map_view)
        return true
    end
    return self:showGamePreview()
end

function Editor:detachGamePreview()
    local document = self.live_document
    if not document then return false end
    if self.game_preview_paused then
        self.game_preview_movement_lock = self.game_preview_lock_before_pause == true
    else
        self.game_preview_movement_lock = Game.lock_movement
    end
    self.game_preview_lock_before_pause = nil
    self:clearGameObjectSelection()
    document.game_view_state = self:captureGameViewState(document)
    self:suspendGamePreviewAudio()
    if document.panel and document.panel.content == self.game_preview then
        document.panel:setContent(document.map_view)
    end
    self.live_document = nil
    self.game_panel = nil
    Game.lock_movement = true
    self.dockspace:layout()
    return true
end

function Editor:isStandaloneGamePreviewEnabled()
    return self.game_preview_panel and self.game_preview_panel.visible == true
end

function Editor:getGamePreviewOwnerPanel()
    if self:isStandaloneGamePreviewEnabled() then return self.game_preview_panel end
    return self.live_document and self.live_document.panel or nil
end

function Editor:setGamePreviewPaused(paused)
    if not self.live_document then return false end
    paused = paused == true
    if paused == self.game_preview_paused then return true end
    if paused then
        self.game_preview_lock_before_pause = Game.lock_movement
        self.game_preview_movement_lock = Game.lock_movement
    end
    self.game_preview_paused = paused
    self:clearForwardedGameMouse()
    if self.game_preview_paused then
        self:suspendGamePreviewAudio()
    else
        self:resumeGamePreviewAudio()
    end
    if self.game_preview_paused then
        Game.lock_movement = true
    else
        Game.lock_movement = self.game_preview_lock_before_pause == true
        self.game_preview_movement_lock = Game.lock_movement
        self.game_preview_lock_before_pause = nil
    end
    return true
end

function Editor:toggleGamePreviewPaused()
    return self:setGamePreviewPaused(not self.game_preview_paused)
end

function Editor:setStandaloneGamePreviewMap(id)
    if not self:isStandaloneGamePreviewEnabled() or not hasMap(id) then return false end
    if self.game_panel == self.game_preview_panel and self.live_document == self.standalone_preview_document
        and self.standalone_preview_map_id == id then
        self.dockspace:setFocus(self.game_preview)
        return true
    end
    local was_paused = self.game_preview_paused
    if self.live_document then self:detachGamePreview() end
    if not self:restoreGamePreviewSnapshot() then return false end
    self.standalone_preview_map_id = id
    self.standalone_preview_document = EditorMapDocument(self, id)
    self.game_preview:setDocument(self.standalone_preview_document)
    self.game_preview.canvas_positioned = false
    if id ~= self.map_id and not self:loadRuntimeMap(id) then return false end
    if not self:captureGamePreviewSnapshot(self.standalone_preview_document) then return false end
    self.game_preview_panel:setContent(self.game_preview)
    self.live_document = self.standalone_preview_document
    self.game_panel = self.game_preview_panel
    self:activateGameObjectSelection()
    self.game_preview_paused = was_paused
    if was_paused then
        self.game_preview_lock_before_pause = self.game_preview_movement_lock
        self:suspendGamePreviewAudio()
    else
        self:resumeGamePreviewAudio()
    end
    Game.lock_movement = was_paused and true or self.game_preview_movement_lock
    self.dockspace:layout()
    self.dockspace:setFocus(self.game_preview)
    return true
end

function Editor:setStandaloneGamePreviewEnabled(enabled)
    if enabled then
        local id = self.standalone_preview_map_id
            or (self.active_document and self.active_document.primary_map_id)
        if not id then return false end
        return self:setStandaloneGamePreviewMap(id)
    end
    if self.game_panel == self.game_preview_panel then self:detachGamePreview() end
    self.game_preview_paused = false
    if not self.tile_editing_mode and self.active_document then
        return self:showGamePreview({ document = self.active_document, ignore_standalone = true })
    end
    return true
end

function Editor:captureGamePreviewSnapshot(document)
    if self.game_preview_snapshot and self.game_preview_snapshot_document == document then return true end
    local success, snapshot = self:runGameCallback("snapshot", function()
        local player = Game.world and Game.world.player
        local position = player and { player.x, player.y } or nil
        local data = Game:save(position)
        if player then data.spawn_facing = player:getFacing() end
        return TableUtils.copy(data, true)
    end)
    if not success then return false end
    self.game_preview_snapshot = snapshot
    self.game_preview_snapshot_document = document
    self.game_preview_snapshot_save_id = Game.save_id
    return true
end

function Editor:restoreGamePreviewSnapshot()
    local snapshot = self.game_preview_snapshot
    if not snapshot then return true end
    self:clearForwardedGameMouse()
    local save_id = self.game_preview_snapshot_save_id
    self.game_preview_snapshot = nil
    self.game_preview_snapshot_document = nil
    self.game_preview_snapshot_save_id = nil
    local success = self:runGameCallback("reset", function()
        Game:load(TableUtils.copy(snapshot, true), save_id, false)
    end)
    if success then
        self.map_id = snapshot.room_id
        self.game_music_suspended_by_editor = false
    end
    return success
end

function Editor:getGamePreviewMusic()
    local success, music = pcall(function() return Game:getActiveMusic() end)
    if success then return music end
end

function Editor:suspendGamePreviewAudio()
    local music = self:getGamePreviewMusic()
    if music and music:isPlaying() then
        music:pause()
        self.game_music_suspended_by_editor = true
    end
end

function Editor:resumeGamePreviewAudio()
    if not self.game_music_suspended_by_editor then return end
    local music = self:getGamePreviewMusic()
    if music and music:canResume() then music:resume() end
    self.game_music_suspended_by_editor = false
end

function Editor:clearForwardedGameMouse()
    for button, forwarded in pairs(self.forwarded_mouse_buttons or {}) do
        if forwarded then Input.onMouseReleased(0, 0, button, false, 0) end
    end
    self.forwarded_mouse_buttons = {}
end

function Editor:applyGameViewState(document)
    local state = document.game_view_state
    if state and type(state.zoom) == "number" then
        self.game_preview.view_zoom = MathUtils.clamp(state.zoom,
            self.game_preview.minimum_zoom, self.game_preview.maximum_zoom)
    else
        self.game_preview.view_zoom = 1
    end
    if state and type(state.canvas_x) == "number" and type(state.canvas_y) == "number" then
        self.game_preview:setCanvasPosition(state.canvas_x, state.canvas_y)
    else
        self.game_preview.canvas_positioned = false
    end
end

function Editor:loadRuntimeMap(id)
    if not id or not Registry.getMap(id) and not Registry.getMapData(id) then return false end
    if not Game.world then return false end
    Game.state = "OVERWORLD"
    Game.world:loadMap(id)
    self.map_id = id
    return true
end

function Editor:openMap(id)
    local existing_document = self:findMapDocument(id)
    if existing_document and existing_document ~= self.active_document then
        return self:activateMapDocument(existing_document)
    end
    if not hasMap(id) then return false end
    if self.active_document then
        self.active_document:setPrimaryMap(id)
        if self.active_document.panel then self.active_document.panel.title = id end
        return self:activateMapDocument(self.active_document)
    end
    return false
end

function Editor:findMapDocument(id)
    for _, document in ipairs(self.map_documents) do
        if document.primary_map_id == id then return document end
    end
end

function Editor:activateMapDocument(document, options)
    options = options or {}
    if not document then return false end
    if document.panel and not document.panel.visible then
        self.dockspace:setPanelVisible(document.panel, true, document.panel.last_region or "center")
    end
    self.active_document = document
    if self.layers_browser then self.layers_browser:setDocument(document) end
    if options.select_panel ~= false and document.panel and document.panel.stack then
        document.panel.stack:setActivePanel(document.panel)
    end
    if options.set_mode ~= false and not self.tile_editing_mode
        and not self:isStandaloneGamePreviewEnabled() then
        return self:showGamePreview({ document = document, select_panel = false })
    end
    return true
end

function Editor:showGamePreview(options)
    options = options or {}
    if self:isStandaloneGamePreviewEnabled() and not options.ignore_standalone then
        if self.game_panel ~= self.game_preview_panel then
            return self:setStandaloneGamePreviewMap(self.standalone_preview_map_id
                or (self.active_document and self.active_document.primary_map_id))
        end
        self.dockspace:setFocus(self.game_preview)
        return true
    end
    local document = options.document or self.active_document
    if not document then return false end
    if self.live_document ~= document then
        self:detachGamePreview()
        if not self:restoreGamePreviewSnapshot() then return false end
        self:applyGameViewState(document)
    end
    self.active_document = document
    self.game_preview:setDocument(document)
    if document.primary_map_id ~= self.map_id and not self:loadRuntimeMap(document.primary_map_id) then
        return false
    end
    if not self:captureGamePreviewSnapshot(document) then return false end
    self.tile_editing_mode = false
    self.game_preview_paused = false
    self:resumeGamePreviewAudio()
    Game.lock_movement = self.game_preview_movement_lock
    local panel = document.panel
    if not panel.visible then
        self.dockspace:setPanelVisible(panel, true, panel.last_region or "center")
    end
    panel:setContent(self.game_preview)
    self.live_document = document
    self.game_panel = panel
    self:activateGameObjectSelection()
    self.dockspace:layout()
    if options.select_panel ~= false and panel.stack then panel.stack:setActivePanel(panel) end
    self.dockspace:setFocus(self.game_preview)
    return true
end

function Editor:openMapTab(id, dock_target)
    if not id or not Registry.getMap(id) and not Registry.getMapData(id) then return false end
    if dock_target and dock_target.standalone_game_preview then
        return self:setStandaloneGamePreviewMap(id)
    end
    local document = self:findMapDocument(id)
    if not document then
        document = self:createMapDocument(id)
        if not document then return false end
    end
    if dock_target and dock_target.stack then
        self.dockspace:dockPanel(document.panel, dock_target.stack)
    end
    return self:activateMapDocument(document)
end

function Editor:isMapTabDropTarget(x, y)
    return self:getMapPanelDropTarget(x, y) ~= nil
end

function Editor:getMapPanelDropTarget(x, y)
    if self:isStandaloneGamePreviewEnabled() then
        local rect = self.dockspace:getPanelRect(self.game_preview_panel)
        if self.dockspace:isPanelDisplayed(self.game_preview_panel)
            and rect and x >= rect.x and y >= rect.y
            and x < rect.x + rect.width and y < rect.y + rect.height then
            return { standalone_game_preview = true, rect = rect }
        end
    end
    return self.dockspace:getMapPanelDropTarget(x, y)
end

function Editor:addMapToView(id, x, y, document)
    document = document or self.active_document
    return document and document:addMap(id, x, y) or nil
end

function Editor:removeMapFromView(id, document)
    document = document or self.active_document
    return document and document:removeMap(id) or false
end

function Editor:removeMapDocument(document)
    local remove_index
    for index, candidate in ipairs(self.map_documents) do
        if candidate == document then remove_index = index break end
    end
    if not remove_index then return false end
    if self.live_document == document then self:detachGamePreview() end
    self.dockspace:unregisterPanel(document.panel)
    table.remove(self.map_documents, remove_index)
    if self.active_document == document then
        self.active_document = nil
        local replacement = self.map_documents[remove_index] or self.map_documents[remove_index - 1]
        if replacement then
            self:activateMapDocument(replacement)
        else
            self.game_panel = nil
            if self.layers_browser then self.layers_browser:setDocument(nil) end
            self.dockspace:setFocus(nil)
        end
    end
    return true
end

function Editor:isGamePreviewMounted()
    local owner = self:getGamePreviewOwnerPanel()
    return not self.game_faulted
        and (self:isStandaloneGamePreviewEnabled() or not self.tile_editing_mode)
        and self.live_document ~= nil
        and self.game_preview ~= nil
        and owner ~= nil
        and owner.content == self.game_preview
        and self.source_state ~= nil
end


function Editor:isGamePreviewInputActive()
    return not self.game_preview_paused and self:isGamePreviewMounted()
end

function Editor:canForwardGameKeyboardInput()
    if not self:isGamePreviewInputActive() then return false end
    local focused = self.dockspace.focused_control
    return not (focused and focused.accepts_text_input)
end

function Editor:getGamePreviewPosition(x, y, allow_outside)
    if not self:isGamePreviewMounted() then return nil end
    local owner = self:getGamePreviewOwnerPanel()
    if not self.dockspace:isPanelDisplayed(owner) then return nil end
    local view_x, view_y = self.game_preview:getGlobalPosition()
    local zoom = self.game_preview.view_zoom
    local game_x = (x - view_x - self.game_preview.canvas_x) / zoom
    local game_y = (y - view_y - self.game_preview.canvas_y) / zoom
    if not allow_outside
        and (game_x < 0 or game_y < 0 or game_x >= SCREEN_WIDTH or game_y >= SCREEN_HEIGHT) then
        return nil
    end
    return math.floor(game_x), math.floor(game_y)
end

function Editor:getGameInputPosition(x, y, allow_outside)
    if not self:isGamePreviewInputActive() then return nil end
    return self:getGamePreviewPosition(x, y, allow_outside)
end

function Editor:activateGameObjectSelection()
    local debug_system = Kristal.DebugSystem
    if not debug_system then return false end
    debug_system:setSelectionEnvironment(self,
        function() return Game.stage end,
        function() return self.object_selection_cursor_x or 0, self.object_selection_cursor_y or 0 end)
    local mouse_x, mouse_y = love.mouse.getPosition()
    self:updateGameObjectSelectionCursor(mouse_x, mouse_y)
    return true
end

function Editor:clearGameObjectSelection()
    local debug_system = Kristal.DebugSystem
    if not debug_system or debug_system.selection_environment_owner ~= self then return false end
    if debug_system.context then debug_system.context:close() end
    debug_system:unselectObject()
    self:clearPropertiesTarget(self)
    debug_system:clearSelectionEnvironment(self)
    self.object_selection_cursor_x = nil
    self.object_selection_cursor_y = nil
    self.object_selection_mouse_buttons = {}
    return true
end

function Editor:getGameObjectPropertiesTarget(object)
    local function numberField(label, key)
        return {
            label = label,
            get = function() return object[key] or 0 end,
            set = function(value)
                local number = tonumber(value)
                if not number then
                    self:addWarning(label .. " must be a number", nil, "object_property")
                    return false
                end
                object[key] = number
                if object.data then object.data[key] = number end
                self:clearDiagnostics("object_property")
                return true
            end
        }
    end
    local data = object.data
    if data then
        data.properties = data.properties or {}
    else
        object.editor_properties = object.editor_properties or {}
    end
    return {
        title = ClassUtils.getClassName(object) or "Game Object",
        fields = {
            numberField("X", "x"),
            numberField("Y", "y"),
            numberField("Width", "width"),
            numberField("Height", "height"),
            numberField("Layer", "layer")
        },
        properties = data and data.properties or object.editor_properties,
        on_changed = function()
            self:addWarning("Game object property changes affect only the current preview",
                nil, "object_property_preview")
        end
    }
end

function Editor:isGameObjectSelectionActive()
    return Kristal.DebugSystem
        and Kristal.DebugSystem.selection_environment_owner == self
        and self:isGamePreviewMounted()
end

function Editor:updateGameObjectSelectionCursor(x, y)
    if not self:isGameObjectSelectionActive() then return false end
    local game_x, game_y = self:getGamePreviewPosition(x, y, true)
    if not game_x then return false end
    self.object_selection_cursor_x = game_x
    self.object_selection_cursor_y = game_y
    return true
end

function Editor:getGameObjectAtCursor()
    if not self:isGameObjectSelectionActive() then return nil end
    local x, y = self.object_selection_cursor_x, self.object_selection_cursor_y
    if not x then return nil end
    return Kristal.DebugSystem:detectObject(x, y)
end

function Editor:handleGameObjectSelectionMousePressed(x, y, button, istouch, presses)
    if button ~= 1 and button ~= 2 or not self:isGameObjectSelectionActive() then return false end
    self:updateGameObjectSelectionCursor(x, y)
    local debug_system = Kristal.DebugSystem
    local game_x, game_y = self:getGamePreviewPosition(x, y, true)
    if not game_x then return false end

    if debug_system.context
        and debug_system.context:onMousePressed(game_x, game_y, button, istouch, presses) then
        self.object_selection_mouse_buttons[button] = true
        return true
    end

    local object = debug_system:detectObject(game_x, game_y)
    if object then
        debug_system:selectObject(object)
        self:setPropertiesTarget(self:getGameObjectPropertiesTarget(object), self)
        if button == 1 then
            debug_system.grabbing = true
            local screen_x, screen_y = object:getScreenPos()
            debug_system.grab_offset_x = game_x - screen_x
            debug_system.grab_offset_y = game_y - screen_y
        else
            debug_system:openObjectContext(object)
        end
    else
        debug_system:unselectObject()
        self:clearPropertiesTarget(self)
    end
    self.object_selection_mouse_buttons[button] = true
    return true
end

function Editor:handleGameObjectSelectionMouseReleased(x, y, button, istouch, presses)
    if button ~= 1 and button ~= 2 or not self:isGameObjectSelectionActive() then return false end
    if not self.object_selection_mouse_buttons[button] then return false end
    self.object_selection_mouse_buttons[button] = nil
    self:updateGameObjectSelectionCursor(x, y)
    local debug_system = Kristal.DebugSystem
    local game_x, game_y = self:getGamePreviewPosition(x, y, true)
    if game_x then debug_system:onMouseReleased(game_x, game_y, button, istouch, presses) end
    return true
end

function Editor:hasForwardedMouseButton()
    for _, forwarded in pairs(self.forwarded_mouse_buttons) do
        if forwarded then return true end
    end
    return false
end

function Editor:forwardGameKeyPressed(key, is_repeat)
    if not self:canForwardGameKeyboardInput() or not self.source_state.onKeyPressed then return false end
    self:runGameCallback("input", function() self.source_state:onKeyPressed(key, is_repeat) end)
    return true
end

function Editor:forwardGameKeyReleased(key)
    if not self:canForwardGameKeyboardInput() or not self.source_state.onKeyReleased then return false end
    self:runGameCallback("input", function() self.source_state:onKeyReleased(key) end)
    return true
end

function Editor:forwardGameTextInput(text)
    if not self:canForwardGameKeyboardInput() then return false end
    self:runGameCallback("text input", function()
        if self.source_state.onTextInput then self.source_state:onTextInput(text) end
        TextInput.onTextInput(text)
        Kristal.callEvent(KRISTAL_EVENT.onTextInput, text)
    end)
    return true
end

function Editor:forwardGameMousePressed(x, y, button, istouch, presses)
    local game_x, game_y = self:getGameInputPosition(x, y)
    if not game_x then return false end
    self.forwarded_mouse_buttons[button] = true
    self:runGameCallback("mouse input", function()
        Input.onMousePressed(game_x, game_y, button, istouch, presses)
        Kristal.callEvent(KRISTAL_EVENT.onMousePressed, game_x, game_y, button, istouch, presses)
    end)
    return true
end

function Editor:forwardGameMouseMoved(x, y, dx, dy, istouch)
    local game_x, game_y = self:getGameInputPosition(x, y, self:hasForwardedMouseButton())
    if not game_x then return false end
    local zoom = self.game_preview.view_zoom
    local game_dx, game_dy = MathUtils.round(dx / zoom), MathUtils.round(dy / zoom)
    self:runGameCallback("mouse input", function()
        Input.onMouseMoved(game_x, game_y, game_dx, game_dy, istouch)
        Kristal.callEvent(KRISTAL_EVENT.onMouseMoved, game_x, game_y, game_dx, game_dy, istouch)
    end)
    return true
end

function Editor:forwardGameMouseReleased(x, y, button, istouch, presses)
    if not self.forwarded_mouse_buttons[button] then return false end
    local game_x, game_y = self:getGameInputPosition(x, y, true)
    self.forwarded_mouse_buttons[button] = nil
    if not game_x then return false end
    self:runGameCallback("mouse input", function()
        Input.onMouseReleased(game_x, game_y, button, istouch, presses)
        Kristal.callEvent(KRISTAL_EVENT.onMouseReleased, game_x, game_y, button, istouch, presses)
    end)
    return true
end

function Editor:onKeyPressed(key, is_repeat)
    if self.entry_transition or self.exit_transition then return true end
    if self.menu_bar:onKeyPressed(key) then return true end
    if key == "space" and not is_repeat and self.live_document
        and not (self.dockspace.focused_control and self.dockspace.focused_control.accepts_text_input) then
        self.consumed_editor_keys[key] = true
        self:toggleGamePreviewPaused()
        return true
    end
    if key == "g" and not is_repeat
        and not (self.dockspace.focused_control and self.dockspace.focused_control.accepts_text_input) then
        self.consumed_editor_keys[key] = true
        self.show_tile_grid = not self.show_tile_grid
        return true
    end
    if Input.is("editor_view", key) and not is_repeat then
        self.consumed_editor_keys[key] = true
        Input.clear("editor_view")
        self:setTileEditingMode(not self.tile_editing_mode)
        return true
    end
    if Input.is("editor", key) and not is_repeat then
        self.consumed_editor_keys[key] = true
        Input.clear("editor")
        Kristal.exitEditor()
        return true
    end
    if self.dockspace:onKeyPressed(key, is_repeat) then return true end
    return self:forwardGameKeyPressed(key, is_repeat)
end

function Editor:beginExitTransition()
    if self.entry_transition or self.exit_transition then return false end
    self:saveSession()
    self.session_saved_for_exit = true
    if self.live_document then
        if self.game_preview_paused then
            self.game_preview_movement_lock = self.game_preview_lock_before_pause == true
        else
            self.game_preview_movement_lock = Game.lock_movement
        end
    end
    self:suspendGamePreviewAudio()
    Game.lock_movement = true
    self.exit_transition = EditorModeTransition("exit", function(transition)
        self:finishExitTransition(transition)
    end)
    return true
end

function Editor:finishExitTransition(transition)
    if Kristal.getState() ~= self then return end
    local snapshot = self.game_preview_snapshot and TableUtils.copy(self.game_preview_snapshot, true)
    local snapshot_save_id = self.game_preview_snapshot_save_id
    local resume_game_music = self.game_music_suspended_by_editor == true
    local game_lock_movement = self.game_preview_movement_lock
    self.game_preview_snapshot = nil
    self.game_preview_snapshot_document = nil
    self.game_preview_snapshot_save_id = nil
    self.game_music_suspended_by_editor = false
    self.exit_transition = nil
    Kristal.popState()
    Kristal.pushState("EditorTransition", "exit_tail", {
        transition = transition,
        game_snapshot = snapshot,
        game_snapshot_save_id = snapshot_save_id,
        resume_game_music = resume_game_music,
        game_lock_movement = game_lock_movement
    })
end

function Editor:onKeyReleased(key)
    if self.entry_transition or self.exit_transition then return true end
    if self.consumed_editor_keys[key] then
        self.consumed_editor_keys[key] = nil
        return true
    end
    if self.dockspace:onKeyReleased(key) then return true end
    return self:forwardGameKeyReleased(key)
end

function Editor:onTextInput(text)
    if self.entry_transition or self.exit_transition then return true end
    if self.dockspace:onTextInput(text) then return true end
    return self:forwardGameTextInput(text)
end

function Editor:onMousePressed(x, y, button, istouch, presses)
    if self.entry_transition or self.exit_transition then return true end
    if self.message_bar:containsPoint(x, y) then return true end
    if self.menu_bar:onMousePressed(x, y, button) then return true end
    if self.dockspace:onMousePressed(x, y, button, presses) then return true end
    if self:handleGameObjectSelectionMousePressed(x, y, button, istouch, presses) then return true end
    return self:forwardGameMousePressed(x, y, button, istouch, presses)
end

function Editor:onMouseMoved(x, y, dx, dy, istouch)
    if self.entry_transition or self.exit_transition then return true end
    self:updateGameObjectSelectionCursor(x, y)
    if self.dockspace:onMouseMoved(x, y, dx, dy) then return true end
    local debug_system = Kristal.DebugSystem
    if self:isGameObjectSelectionActive()
        and (debug_system.grabbing or debug_system.context and debug_system.context.grabbing) then
        return true
    end
    return self:forwardGameMouseMoved(x, y, dx, dy, istouch)
end

function Editor:onMouseReleased(x, y, button, istouch, presses)
    if self.entry_transition or self.exit_transition then return true end
    if self.dockspace:onMouseReleased(x, y, button, presses) then return true end
    if self:handleGameObjectSelectionMouseReleased(x, y, button, istouch, presses) then return true end
    return self:forwardGameMouseReleased(x, y, button, istouch, presses)
end

function Editor:onWheelMoved(x, y)
    if self.entry_transition or self.exit_transition then return true end
    local mouse_x, mouse_y = love.mouse.getPosition()
    if self.message_bar:containsPoint(mouse_x, mouse_y) then return true end
    return self.dockspace:onWheelMoved(x, y)
end

function Editor:captureLayout()
    return self.dockspace:captureLayout()
end

function Editor:resetPanelLayout()
    if not self.default_layout then return false end
    local layout = TableUtils.copy(self.default_layout, true)
    local center = layout.regions.center
    center.stacks = center.stacks or {}
    if not center.stacks[1] then
        center.stacks[1] = { id = "center", panels = {} }
    end
    local center_stack = center.stacks[1]
    layout.panels = layout.panels or {}
    for _, document in ipairs(self.map_documents or {}) do
        local panel = document.panel
        if not layout.panels[panel.id] then
            layout.panels[panel.id] = { visible = true, last_region = "center" }
            table.insert(center_stack.panels, panel.id)
        end
    end
    if self.active_document then center_stack.active = self.active_document.panel.id end
    self:restoreLayout(layout)
    return true
end

function Editor:restoreLayout(layout)
    self.dockspace:restoreLayout(layout)
end

return Editor
