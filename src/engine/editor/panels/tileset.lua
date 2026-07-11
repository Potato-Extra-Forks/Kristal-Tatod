---@class EditorTilesetPanel : EditorControl
---@overload fun(editor: table): EditorTilesetPanel
local EditorTilesetPanel, super = Class(EditorControl)

local MODES = {
    { id = "tileset", name = "Tileset" }, { id = "tile", name = "Tile" },
    { id = "terrain", name = "Terrain" }, { id = "collision", name = "Collision" },
    { id = "animation", name = "Animation" }
}

function EditorTilesetPanel:init(editor)
    super.init(self, 0, 0, 440, 420)
    self.editor = editor
    self.document = nil
    self.tile = nil
    self.mode = "tileset"
    self.mode_buttons = {}
    for _, mode in ipairs(MODES) do
        local id = mode.id
        local button = self:addChild(EditorButton(mode.name, function() self:setMode(id) end))
        table.insert(self.mode_buttons, button)
    end
    self.add_button = self:addChild(EditorButton("Add", function() self:addItem() end))
    self.tile_grid = self:addChild(EditorTilePalette(editor, {
        show_tools = false,
        on_selection = function()
            if self.mode == "tileset" then self:setMode("tile") end
        end
    }))
    self.list = self:addChild(EditorItemList({
        on_select = function(item) self:selectItem(item and item.data) end,
        on_drag_end = function(item, list, _, y) self:reorderItem(item, list:getItemIndexAt(y)) end,
        on_context_menu = function(item, list, x, y) self:openItemContext(item, list, x, y) end,
        on_request_focus = function(control) editor.dockspace:setFocus(control) end
    }))
    self.properties = self:addChild(EditorPropertiesPanel(editor))
end

function EditorTilesetPanel:setDocument(document)
    self.document = document
    self.tile_grid:setTilesetDocument(document)
    self.tile = document and document:getTile(0) or nil
    self:setMode("tileset")
end

function EditorTilesetPanel:setTile(tile)
    self.tile = tile
    self.tile_grid:setSelectedTile(tile)
    if self.mode ~= "tileset" then self:rebuild() end
end

function EditorTilesetPanel:setMode(mode)
    self.mode = mode
    self:rebuild()
end

function EditorTilesetPanel:getItems()
    if not self.document then return {} end
    if self.mode == "terrain" then return self.document:getTerrainSets() end
    if self.mode == "collision" then return self.document:getCollisionShapes(self.tile) end
    if self.mode == "animation" then return self.document:getAnimationFrames(self.tile) end
    return {}
end

function EditorTilesetPanel:refreshList(selected)
    local items = {}
    for index, value in ipairs(self:getItems()) do
        local label
        if self.mode == "terrain" then label = value.name or ("Terrain Set " .. index)
        elseif self.mode == "collision" then label = string.format("%s %d", StringUtils.titleCase(value.shape or "rectangle"), index)
        else label = string.format("Tile %s  -  %sms", tostring(value.tileid or 0), tostring(value.duration or 100)) end
        table.insert(items, { id = index, label = label, data = value })
    end
    self.list:setItems(items)
    if #items > 0 then
        local selected_index = 1
        for index, item in ipairs(self.list.filtered_items) do if item.data == selected then selected_index = index break end end
        self.list:select(selected_index)
        self:selectItem(self.list:getSelectedItem().data)
    else
        self.properties:setTarget(nil)
    end
end

function EditorTilesetPanel:rebuild()
    local list_mode = self.mode == "terrain" or self.mode == "collision" or self.mode == "animation"
    self.list.visible, self.add_button.visible = list_mode, list_mode
    self.properties.visible = true
    if not self.document then self.properties:setTarget(nil) return end
    if self.mode == "tileset" then
        self.properties:setTarget(self.document:getPropertiesTarget())
    elseif self.mode == "tile" then
        self.properties:setTarget(self.document:getTilePropertiesTarget(self.tile))
    else
        self:refreshList()
    end
end

function EditorTilesetPanel:addItem()
    if not self.document then return false end
    self.editor:beginHistoryTransaction("Add Tileset Item", self.document)
    local item
    if self.mode == "terrain" then item = self.document:addTerrainSet()
    elseif self.mode == "collision" then item = self.document:addCollisionShape(self.tile)
    elseif self.mode == "animation" then item = self.document:addAnimationFrame(self.tile) end
    if item then
        self.editor:markHistoryChanged()
        self.editor:commitHistoryTransaction()
        self:refreshList(item)
        self.editor:warnTilesetVisualOnly()
        return true
    end
    self.editor:cancelHistoryTransaction()
    return false
end

function EditorTilesetPanel:getItemTarget(item)
    if not item then return nil end
    item.properties = item.properties or {}
    item.__editor_property_types = item.__editor_property_types or {}
    local set = EditorPropertySet(item.properties, item.__editor_property_types)
    local function field(label, key, numeric)
        return { label = label, get = function() return item[key] or (numeric and 0 or "") end,
            set = function(value)
                if numeric then value = tonumber(value) if not value then return false end end
                item[key] = value return true
            end }
    end
    local fields, title = {}, "Tileset Item"
    if self.mode == "terrain" then
        title = item.name or "Terrain Set"
        fields = { field("Name", "name"), field("Type", "type") }
    elseif self.mode == "collision" then
        title = "Tile Collision Shape"
        fields = { field("Shape", "shape"), field("X", "x", true), field("Y", "y", true),
            field("Width", "width", true), field("Height", "height", true) }
    elseif self.mode == "animation" then
        title = "Animation Frame"
        fields = { field("Tile ID", "tileid", true), field("Duration (ms)", "duration", true) }
    end
    return { title = title, fields = fields, property_set = set, properties = item.properties,
        history_owner = self.document,
        property_types = item.__editor_property_types,
        on_changed = function() self.editor:warnTilesetVisualOnly() self:refreshList(item) end }
end

function EditorTilesetPanel:selectItem(item)
    self.selected_item = item
    self.properties:setTarget(self:getItemTarget(item))
end

function EditorTilesetPanel:removeItem(item)
    if not item then return false end
    self.editor:beginHistoryTransaction("Remove Tileset Item", self.document)
    TableUtils.removeValue(self:getItems(), item)
    self.editor:markHistoryChanged()
    self.editor:commitHistoryTransaction()
    self:refreshList()
    self.editor:warnTilesetVisualOnly()
    return true
end

function EditorTilesetPanel:reorderItem(item, target)
    if not item then return end
    local items = self:getItems()
    local source
    for index, value in ipairs(items) do if value == item.data then source = index break end end
    if not source then return end
    self.editor:beginHistoryTransaction("Reorder Tileset Item", self.document)
    local value = table.remove(items, source)
    table.insert(items, MathUtils.clamp(target, 1, #items + 1), value)
    self.editor:markHistoryChanged()
    self.editor:commitHistoryTransaction()
    self:refreshList(value)
    self.editor:warnTilesetVisualOnly()
end

function EditorTilesetPanel:openItemContext(item, list, x, y)
    local items = { { label = "Add", action = function() self:addItem() end } }
    if item then table.insert(items, { label = "Delete", action = function() self:removeItem(item.data) end }) end
    local gx, gy = list:getGlobalPosition()
    self.editor.dockspace:openContextMenu(items, gx + x, gy + y, list)
end

function EditorTilesetPanel:update(dt)
    local button_width = math.max(64, math.floor((self.width - 16) / #self.mode_buttons))
    local x = 8
    for _, button in ipairs(self.mode_buttons) do
        button:setBounds(x, 8, button_width - 4, 28)
        button.focused = self.mode == button.label:lower()
        x = x + button_width
    end
    local content_y = 44
    local atlas_width = MathUtils.clamp(math.floor(self.width * 0.44), 180, math.max(180, self.width - 220))
    local right_x = atlas_width + 4
    local right_width = math.max(0, self.width - right_x)
    self.tile_grid:setBounds(4, content_y, math.max(0, atlas_width - 4), math.max(0, self.height - content_y - 4))
    if self.list.visible then
        local list_height = math.max(100, math.floor((self.height - content_y) * 0.38))
        self.add_button:setBounds(right_x + 4, content_y, math.max(0, right_width - 12), 28)
        self.list:setBounds(right_x + 4, content_y + 36,
            math.max(0, right_width - 12), math.max(0, list_height - 36))
        self.properties:setBounds(right_x, content_y + list_height,
            right_width, math.max(0, self.height - content_y - list_height))
    else
        self.properties:setBounds(right_x, content_y, right_width, math.max(0, self.height - content_y))
    end
    super.update(self, dt)
end

function EditorTilesetPanel:drawSelf()
    Draw.setColor(0.08, 0.08, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    Draw.setColor(0.30, 0.30, 0.34, 1)
    local atlas_width = MathUtils.clamp(math.floor(self.width * 0.44), 180, math.max(180, self.width - 220))
    love.graphics.line(atlas_width + 0.5, 44, atlas_width + 0.5, self.height)
end

return EditorTilesetPanel
