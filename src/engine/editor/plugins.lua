---@class EditorPlugins
local EditorPlugins = {
    directory = "editor/plugins",
    debug_directory = "plugins",
    plugins = {},
    plugin_order = {},
    controls = {},
    panel_definitions = {},
    menu_definitions = {},
    event_initializers = {},
    editor = nil
}

local NIL_RESULT = {}
local PluginMethods = {}

local function tracebackError(value)
    return debug.traceback(tostring(value), 2)
end

local function normalizeScriptPath(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("%.lua$", "")
    return path:gsub("%.", "/"):gsub("^/+", "")
end

local function namespaced(plugin, kind, id)
    return string.format("plugin:%s:%s:%s", plugin.id, kind, id)
end

function PluginMethods:require(path, ...)
    path = normalizeScriptPath(path)
    local cached = self.loaded_scripts[path]
    if cached ~= nil then return cached ~= NIL_RESULT and cached or nil end
    local chunk = self.info.script_chunks[path] or self.info.script_chunks[path .. "/init"]
    if not chunk then error(string.format("Plugin '%s' has no script '%s'", self.id, path), 2) end
    if self.loading_scripts[path] then
        error(string.format("Plugin '%s' has a circular require for '%s'", self.id, path), 2)
    end

    self.loading_scripts[path] = true
    local previous_plugin = rawget(_G, "Plugin")
    _G.Plugin = self
    local arguments = { ... }
    local success, result
    HookSystem.withOwner(self, function()
        success, result = xpcall(function() return chunk(unpack(arguments)) end, tracebackError)
    end)
    _G.Plugin = previous_plugin
    self.loading_scripts[path] = nil
    if not success then error(result, 2) end
    self.loaded_scripts[path] = result == nil and NIL_RESULT or result
    return result
end

function PluginMethods:loadHooks()
    local paths = {}
    for path in pairs(self.info.script_chunks) do
        if StringUtils.startsWith(path, "scripts/hooks/") then table.insert(paths, path) end
    end
    table.sort(paths)
    for _, path in ipairs(paths) do self:require(path) end
end

function PluginMethods:registerControl(id, control)
    assert(type(id) == "string" and id ~= "", "Plugin controls require an id")
    assert(not self.controls[id], "Duplicate plugin control id: " .. id)
    if type(control) == "string" then control = self:require(control) end
    assert(isClass(control), "Plugin controls must be an EditorControl class")
    assert(control:includes(EditorControl), "Plugin controls must include EditorControl")
    self.controls[id] = control
    EditorPlugins.controls[namespaced(self, "control", id)] = control
    return control
end

function PluginMethods:getControl(id)
    return self.controls[id]
end

function PluginMethods:registerSettingsPage(id, title, options)
    assert(type(id) == "string" and id ~= "", "Plugin settings pages require an id")
    assert(not self.settings_pages[id], "Duplicate plugin settings page id: " .. id)
    local page_id = namespaced(self, "settings_page", id)
    options = TableUtils.copy(options or {}, true)
    options.owner = self
    local page = EditorPlugins.editor.settings:registerPage(page_id, title or id, options)
    self.settings_pages[id] = page
    return page
end

function PluginMethods:registerSetting(page, id, definition)
    if type(id) == "table" and definition == nil then
        definition, id, page = id, page, nil
    end
    assert(type(id) == "string" and id ~= "", "Plugin settings require an id")
    if page == nil then
        page = self.settings_pages.default or self:registerSettingsPage("default", self.info.name or self.id)
    elseif type(page) == "string" then
        page = self.settings_pages[page] or self:registerSettingsPage(page, page)
    end
    assert(type(page) == "table" and page.id, "Plugin settings require a settings page")
    local setting_id = namespaced(self, "setting", id)
    definition = TableUtils.copy(definition or {}, true)
    definition.owner = self
    return EditorPlugins.editor.settings:registerSetting(page.id, setting_id, definition)
end

function PluginMethods:registerPropertyType(id, definition)
    local type_id = namespaced(self, "property_type", id)
    Registry.registerEditorPropertyType(type_id, definition)
    return type_id
end

function PluginMethods:registerEditorEventProperty(event_id, id, property_type, options)
    return self:registerEditorEventInitializer(event_id, function(event)
        event:registerProperty(id, property_type, options)
    end)
end

function PluginMethods:registerEditorEventInitializer(event_id, initializer)
    assert(type(initializer) == "function", "EditorEvent initializers must be functions")
    EditorPlugins.event_initializers[event_id] = EditorPlugins.event_initializers[event_id] or {}
    table.insert(EditorPlugins.event_initializers[event_id], initializer)
    return initializer
end

function PluginMethods:registerEditorEvent(id, event)
    if type(event) == "string" then event = self:require(event) end
    Registry.registerEditorEvent(id, event)
    return event
end

function PluginMethods:registerEditorDrawFX(id, definition)
    return Registry.registerEditorDrawFX(namespaced(self, "draw_fx", id), definition)
end

function PluginMethods:registerPanel(id, title, content_factory, options)
    assert(type(id) == "string" and id ~= "", "Plugin panels require an id")
    assert(not self.panels[id], "Duplicate plugin panel id: " .. id)
    assert(type(content_factory) == "function", "Plugin panels require a content factory")
    options = TableUtils.copy(options or {}, true)
    local definition = {
        plugin = self,
        id = id,
        panel_id = namespaced(self, "panel", id),
        title = title or id,
        content_factory = content_factory,
        options = options,
        region = options.region or "right"
    }
    self.panels[id] = definition
    table.insert(EditorPlugins.panel_definitions, definition)
    return definition
end

function PluginMethods:registerMenuItem(menu_id, id, label, options)
    assert(type(menu_id) == "string" and menu_id ~= "", "Plugin menu items require a menu id")
    assert(type(id) == "string" and id ~= "", "Plugin menu items require an id")
    local definition = {
        kind = "item", plugin = self, menu_id = menu_id,
        id = namespaced(self, "menu", id), label = label or id, options = options or {}
    }
    table.insert(EditorPlugins.menu_definitions, definition)
    return definition
end

function PluginMethods:registerMenuToggle(menu_id, id, label, get_checked, set_checked)
    assert(type(get_checked) == "function" and type(set_checked) == "function",
        "Plugin menu toggles require getter and setter callbacks")
    local definition = {
        kind = "toggle", plugin = self, menu_id = menu_id,
        id = namespaced(self, "menu", id), label = label or id,
        get_checked = get_checked, set_checked = set_checked
    }
    table.insert(EditorPlugins.menu_definitions, definition)
    return definition
end

function PluginMethods:registerMenuProvider(menu_id, id, provider)
    assert(type(provider) == "function", "Plugin menu providers require a callback")
    local definition = {
        kind = "provider", plugin = self, menu_id = menu_id,
        id = namespaced(self, "menu", id), provider = provider
    }
    table.insert(EditorPlugins.menu_definitions, definition)
    return definition
end

function EditorPlugins:reset()
    self.plugins = {}
    self.plugin_order = {}
    self.controls = {}
    self.panel_definitions = {}
    self.menu_definitions = {}
    self.event_initializers = {}
end

function EditorPlugins:initializeEditorEvent(event)
    for _, initializer in ipairs(self.event_initializers[event.id] or {}) do initializer(event) end
end

function EditorPlugins:clearPluginHooks(plugin)
    HookSystem.clearOwnedHooks(function(owner)
        return owner == plugin or plugin == nil and owner.__editor_plugin == true
    end)
end

function EditorPlugins:report(editor, message, detail)
    editor:addWarning(message, detail, "editor_plugin")
    print(message .. (detail and ("\n" .. detail) or ""))
end

function EditorPlugins:loadPlugin(editor, directory, folder, source)
    local path = directory .. "/" .. folder
    local info_path = path .. "/plugin.json"
    if not love.filesystem.getInfo(info_path, "file") then return nil end

    local success, info = pcall(function() return JSON.decode(love.filesystem.read(info_path)) end)
    if not success or type(info) ~= "table" then
        self:report(editor, "Could not load editor plugin metadata: " .. folder,
            success and "plugin.json must contain a JSON object" or tostring(info))
        return nil
    end
    if type(info.id) ~= "string" or info.id == "" then
        self:report(editor, "Could not load editor plugin: " .. folder, "plugin.json requires a non-empty id")
        return nil
    end
    if self.plugins[info.id] then
        if source == "user" and self.plugins[info.id].info.source == "debug" then return nil end
        self:report(editor, "Duplicate editor plugin id: " .. info.id, path)
        return nil
    end

    info.path = path
    info.source = source
    info.script_chunks = {}
    for _, script_path in ipairs(FileSystemUtils.getFilesRecursive(path, ".lua")) do
        local chunk, load_error = love.filesystem.load(path .. "/" .. script_path .. ".lua")
        if not chunk then
            self:report(editor, string.format("Could not load script '%s' from editor plugin '%s'",
                script_path, info.id), load_error)
            return nil
        end
        info.script_chunks[script_path] = chunk
    end

    local plugin = setmetatable({
        id = info.id, info = info, controls = {}, panels = {},
        settings_pages = {},
        loaded_scripts = {}, loading_scripts = {}, __editor_plugin = true
    }, { __index = PluginMethods })
    self.plugins[plugin.id] = plugin
    table.insert(self.plugin_order, plugin)

    if info.script_chunks.plugin then
        local loaded, result = xpcall(function() return plugin:require("plugin") end, tracebackError)
        if not loaded then
            self:clearPluginHooks(plugin)
            editor.settings:removeOwner(plugin)
            self.plugins[plugin.id] = nil
            TableUtils.removeValue(self.plugin_order, plugin)
            self:report(editor, "Could not initialize editor plugin script: " .. plugin.id, result)
            return nil
        end
        if type(result) == "table" and result ~= plugin then
            for key, value in pairs(result) do plugin[key] = value end
        end
    end
    return plugin
end

function EditorPlugins:scanDirectory(editor, directory, source)
    if not love.filesystem.getInfo(directory, "directory") then return end
    local folders = love.filesystem.getDirectoryItems(directory)
    table.sort(folders)
    for _, folder in ipairs(folders) do
        local info = love.filesystem.getInfo(directory .. "/" .. folder)
        if info and info.type == "directory" then self:loadPlugin(editor, directory, folder, source) end
    end
end

function EditorPlugins:initialize(editor)
    self:clearPluginHooks()
    self:reset()
    self.editor = editor
    love.filesystem.createDirectory(self.directory)
    self:scanDirectory(editor, self.debug_directory, "debug")
    self:scanDirectory(editor, self.directory, "user")

    for _, plugin in ipairs(self.plugin_order) do
        local hooks_loaded, hooks_message = xpcall(function() plugin:loadHooks() end, tracebackError)
        if not hooks_loaded then
            plugin.disabled = true
            self:clearPluginHooks(plugin)
            self:report(editor, "Editor plugin hooks failed: " .. plugin.id, hooks_message)
        end
        local init = plugin.init or plugin.onInit
        if init and not plugin.disabled then
            local panel_count = #self.panel_definitions
            local menu_count = #self.menu_definitions
            local success, message = xpcall(function()
                HookSystem.withOwner(plugin, function() init(plugin, editor) end)
            end, tracebackError)
            if not success then
                self:clearPluginHooks(plugin)
                while #self.panel_definitions > panel_count do table.remove(self.panel_definitions) end
                while #self.menu_definitions > menu_count do table.remove(self.menu_definitions) end
                for id in pairs(plugin.controls) do
                    self.controls[namespaced(plugin, "control", id)] = nil
                end
                plugin.controls = {}
                plugin.panels = {}
                editor.settings:removeOwner(plugin)
                plugin.settings_pages = {}
                self:report(editor, "Editor plugin init failed: " .. plugin.id, message)
            end
        end
    end
end

function EditorPlugins:applyMenuBar(editor)
    for _, definition in ipairs(self.menu_definitions) do
        local success, message = xpcall(function()
            if definition.kind == "toggle" then
                editor.menu_bar:registerToggle(definition.menu_id, definition.id, definition.label,
                    definition.get_checked, definition.set_checked)
            elseif definition.kind == "provider" then
                editor.menu_bar:registerProvider(definition.menu_id, definition.id, definition.provider)
            else
                editor.menu_bar:registerItem(definition.menu_id, definition.id, definition.label,
                    definition.options)
            end
        end, tracebackError)
        if not success then
            self:report(editor, "Could not register menu extension from plugin: " .. definition.plugin.id, message)
        end
    end
end

function EditorPlugins:createPanels(editor)
    for _, definition in ipairs(self.panel_definitions) do
        local success, content = xpcall(function()
            return definition.content_factory(editor, definition.plugin)
        end, tracebackError)
        if success and isClass(content) and content:includes(EditorControl) then
            local options = TableUtils.copy(definition.options, true)
            options.region = nil
            if options.recoverable == nil then options.recoverable = true end
            local panel = EditorPanel(definition.panel_id, definition.title, content, options)
            panel.editor_plugin = definition.plugin
            panel.editor_plugin_id = definition.id
            editor.dockspace:registerPanel(panel, definition.region)
            definition.panel = panel
        else
            self:report(editor, "Could not create panel from editor plugin: " .. definition.plugin.id,
                success and ("Panel '" .. definition.id .. "' did not return an EditorControl") or content)
        end
    end
end

function EditorPlugins:getPlugin(id)
    return self.plugins[id]
end

function EditorPlugins:require(plugin_id, path, ...)
    local plugin = assert(self.plugins[plugin_id], "Unknown editor plugin: " .. tostring(plugin_id))
    return plugin:require(path, ...)
end

function EditorPlugins:getPlugins()
    return self.plugin_order
end

function EditorPlugins:shutdown(editor)
    self:clearPluginHooks()
    if self.editor == editor then self.editor = nil end
end

return EditorPlugins
