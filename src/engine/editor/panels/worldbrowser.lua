---@class EditorWorldBrowser : EditorControl
---@overload fun(editor: table): EditorWorldBrowser
local EditorWorldBrowser, super = Class(EditorControl)

function EditorWorldBrowser:init(editor)
    super.init(self, 0, 0, 260, 320)
    self.editor = editor
    self.search = self:addChild(EditorSearchBar({
        placeholder = "Search worlds...",
        on_changed = function(value) self.list:setFilter(value) end
    }))
    self.new_button = self:addChild(EditorButton("New World", function() self:createWorld() end))
    self.list = self:addChild(EditorItemList({
        on_select = function(item) self:selectWorld(item and item.data) end,
        on_activate = function(item) if item then editor:openWorld(item.data) end end,
        on_rename = function(item, _, name) self:renameWorld(item.data, name) end,
        on_context_menu = function(item, list, x, y) self:openContextMenu(item, list, x, y) end,
        on_request_focus = function(control) editor.dockspace:setFocus(control) end
    }))
    self:refresh()
end

function EditorWorldBrowser:refresh(selected_id)
    local items = {}
    for id, world in pairs(Registry.editor_worlds or {}) do
        table.insert(items, {
            id = id, label = world.name or id, data = world,
            icon = "editor/ui/layer/default"
        })
    end
    table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
    self.list:setItems(items)
    for index, item in ipairs(self.list.filtered_items) do
        if item.id == (selected_id or self.editor.active_world_id) then
            self.list:select(index)
            break
        end
    end
end

function EditorWorldBrowser:selectWorld(world)
    self.editor.active_editor_world = world
    self.editor.active_world_id = world and world.id or nil
    if not world then
        self.editor:clearPropertiesTarget(self)
        return
    end
    world.properties = world.properties or {}
    world.__editor_property_types = world.__editor_property_types or {}
    local property_set = EditorPropertySet(world.properties, world.__editor_property_types)
    local document = self.editor:findWorldDocument(world.id)
    self.editor:setPropertiesTarget({
        title = "World: " .. (world.name or world.id),
        history_owner = document,
        property_set = property_set,
        properties = world.properties,
        property_types = world.__editor_property_types,
        fields = {
            { label = "Name", get = function() return world.name or world.id end,
                set = function(value) world.name = value return true end },
            { label = "ID", readonly = true, get = function() return world.id end,
                set = function() return false end },
            { label = "Maps", readonly = true, get = function() return #(world.maps or {}) end,
                set = function() return false end }
        },
        on_changed = function() self:refresh(world.id) end
    }, self)
end

function EditorWorldBrowser:createWorld()
    local index, id = 1, "new_world"
    while Registry.getEditorWorld(id) do
        index = index + 1
        id = "new_world_" .. index
    end
    local world = EditorWorld(id)
    world.name = "New World"
    world.virtual = true
    local document = self.editor.active_document
    if document and document.primary_map_id then
        world:addMap(document.primary_map_id, 0, 0, { explicit_companion = true })
    end
    Registry.registerEditorWorld(id, world)
    self:refresh(id)
    self:selectWorld(world)
    local item = self.list:getSelectedItem()
    if item then self.list:beginRename(item) end
    return world
end

function EditorWorldBrowser:renameWorld(world, name)
    if not world then return false end
    local document = self.editor:findWorldDocument(world.id)
    local function rename()
        world.name = name
        if document then
            document.world.name = name
            document.panel.title = name .. (document:isDirty() and " *" or "")
        end
        return true
    end
    if document then self.editor:performHistoryEdit("Rename World", document, rename) else rename() end
    self:refresh(world.id)
    self:selectWorld(world)
    return true
end

function EditorWorldBrowser:openContextMenu(item, list, x, y)
    local items = { { label = "New World", action = function() self:createWorld() end } }
    if item then
        table.insert(items, { label = "Open", action = function() self.editor:openWorld(item.data) end })
        table.insert(items, { label = "Save", action = function() self.editor:saveWorldToProject(item.data) end })
        table.insert(items, { label = "Rename", action = function() list:beginRename(item) end })
        if item.data.virtual then
            table.insert(items, { label = "Remove", action = function()
                Registry.editor_worlds[item.data.id] = nil
                self:refresh()
            end })
        end
    end
    local gx, gy = list:getGlobalPosition()
    self.editor.dockspace:openContextMenu(items, gx + x, gy + y, list)
end

function EditorWorldBrowser:update(dt)
    self.search:setBounds(8, 8, math.max(0, self.width - 16), 28)
    self.new_button:setBounds(8, 44, math.max(0, self.width - 16), 28)
    self.list:setBounds(8, 80, math.max(0, self.width - 16), math.max(0, self.height - 88))
    super.update(self, dt)
end

function EditorWorldBrowser:drawSelf()
    Draw.setColor(0.08, 0.08, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
end

return EditorWorldBrowser
