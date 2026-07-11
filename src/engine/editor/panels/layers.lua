---@class EditorLayersPanel : EditorControl
---@overload fun(editor: table): EditorLayersPanel
local EditorLayersPanel, super = Class(EditorControl)

local function colorToHex(color)
    local function byte(value)
        return MathUtils.clamp(MathUtils.round((value or 1) * 255), 0, 255)
    end
    return string.format("#%02X%02X%02X%02X", byte(color[1]), byte(color[2]), byte(color[3]), byte(color[4]))
end

local function hexToColor(value)
    local hex = tostring(value or ""):gsub("^#", "")
    if #hex ~= 6 and #hex ~= 8 or not hex:match("^[%da-fA-F]+$") then return nil end
    if #hex == 6 then hex = hex .. "FF" end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        tonumber(hex:sub(7, 8), 16) / 255
    }
end

function EditorLayersPanel:init(editor)
    super.init(self, 0, 0, 300, 500)
    self.editor = editor
    self.document = nil
    self.map_id = nil
    self.selected_layer = nil
    self.updating_fields = false
    self.detail_y = 0

    self.new_button = self:addChild(EditorButton("New Layer", function() self:openNewLayerMenu() end))
    self.list = self:addChild(EditorItemList({
        row_height = 28,
        on_select = function(item) self:selectLayer(item and item.data) end,
        on_rename = function(item, _, new_name) self:renameLayer(item.data, new_name) end,
        on_drag_end = function(item, list, x, y) self:finishLayerDrag(item, list, y) end,
        on_context_menu = function(item, list, x, y) self:openLayerContextMenu(item, list, x, y) end,
        on_request_focus = function(control) self.editor.dockspace:setFocus(control) end
    }))
end

function EditorLayersPanel:setDocument(document)
    local map_id = document and document.primary_map_id
    if self.document == document and self.map_id == map_id then return end
    self.document = document
    self.map_id = map_id
    self.new_button.enabled = document ~= nil
    self.selected_layer = nil
    self:refreshList()
end

function EditorLayersPanel:warnVisualOnly()
    if self.warned_visual_only then return end
    self.warned_visual_only = true
    self.editor:addWarning("Layer changes are visual-only until the editor map format is implemented",
        nil, "layer_editing")
end

function EditorLayersPanel:getNewLayerItems()
    local items = {}
    for _, layer_type in ipairs(Registry.getLayerTypes()) do
        if layer_type.id ~= "default" then
            local type_id = layer_type.id
            table.insert(items, {
                label = layer_type.name,
                action = function() self:createLayer(type_id) end
            })
        end
    end
    return items
end

function EditorLayersPanel:openNewLayerMenu()
    if not self.document then return false end
    local x, y = self.new_button:getGlobalPosition()
    return self.editor.dockspace:openContextMenu(self:getNewLayerItems(), x, y + self.new_button.height,
        self.new_button)
end

function EditorLayersPanel:openLayerContextMenu(item, list, x, y)
    local items = {
        { label = "New Layer", children = self:getNewLayerItems() }
    }
    if item then
        local layer = item.data
        table.insert(items, { label = "Rename", action = function() list:beginRename(item) end })
        table.insert(items, {
            label = "Delete Layer",
            action = function()
                self:selectLayer(layer)
                self:deleteLayer()
            end
        })
    end
    local global_x, global_y = list:getGlobalPosition()
    self.editor.dockspace:openContextMenu(items, global_x + x, global_y + y, list)
end

function EditorLayersPanel:getLayers()
    return self.document and self.document:getEditableLayers() or {}
end

function EditorLayersPanel:getLayerType(layer)
    return layer and (Registry.getLayerType(layer._editor_type_id) or Registry.getLayerType("default"))
end

function EditorLayersPanel:getLayerColor(layer)
    return Registry.layer_types:getLayerColor(layer, self:getLayerType(layer))
end

function EditorLayersPanel:refreshList(selected_uid)
    selected_uid = selected_uid or (self.selected_layer and self.selected_layer._editor_uid)
    local items = {}
    for _, layer in ipairs(self:getLayers()) do
        local layer_type = self:getLayerType(layer)
        table.insert(items, {
            id = layer._editor_uid,
            label = layer.name or "Unnamed Layer",
            data = layer,
            icon = layer_type and layer_type.icon,
            color = self:getLayerColor(layer),
            right_icon = layer._editor_visible == false and "editor/ui/eye_closed" or "editor/ui/eye_open",
            right_action = function() self:toggleLayerVisibility(layer) end
        })
    end
    self.list:setItems(items)
    local selected_index
    for index, item in ipairs(self.list.filtered_items) do
        if item.id == selected_uid then selected_index = index break end
    end
    if not selected_index and #items > 0 then selected_index = 1 end
    if selected_index then
        self.list:select(selected_index)
        self:selectLayer(self.list:getSelectedItem().data)
    else
        self:selectLayer(nil)
    end
end

function EditorLayersPanel:selectLayer(layer)
    self.selected_layer = layer
    if self.document then
        self.document:setSelectedLayer(layer and layer._editor_uid or nil)
    end
    if layer then
        self.editor:setPropertiesTarget(self:getPropertiesTarget(layer), self)
    else
        self.editor:clearPropertiesTarget(self)
    end
end

function EditorLayersPanel:getPropertiesTarget(layer)
    local layer_type = self:getLayerType(layer)
    return {
        title = (layer.name or "Unnamed Layer") .. " (" .. (layer_type and layer_type.name or "Unknown") .. ")",
        properties = layer.properties,
        property_types = layer._editor_property_types,
        property_set = layer._editor_property_set,
        fields = {
            {
                id = "color",
                label = "Color",
                placeholder = "#RRGGBBAA",
                get = function() return colorToHex(self:getLayerColor(layer)) end,
                set = function(value) return self:setLayerColor(layer, value) end
            },
            {
                id = "depth",
                label = "Depth Override",
                placeholder = "Automatic",
                get = function() return layer._editor_depth_override or "" end,
                set = function(value, submitted) return self:setLayerDepth(layer, value, submitted) end
            }
        },
        on_changed = function() self:changed(false) end
    }
end

function EditorLayersPanel:toggleLayerVisibility(layer)
    if not self.document or not layer then return false end
    self.document:setEditableLayerVisible(layer._editor_uid, layer._editor_visible == false)
    self:refreshList(self.selected_layer and self.selected_layer._editor_uid)
    self:warnVisualOnly()
    return true
end

function EditorLayersPanel:changed(refresh_list)
    if not self.document or not self.selected_layer then return end
    self.document:invalidatePreview()
    self:warnVisualOnly()
    if refresh_list then self:refreshList(self.selected_layer._editor_uid) end
end

function EditorLayersPanel:renameLayer(layer, value)
    if not layer or value == "" then return false end
    layer.name = value
    if self.selected_layer == layer then
        self.editor:setPropertiesTarget(self:getPropertiesTarget(layer), self)
    end
    self:changed(false)
    return true
end

function EditorLayersPanel:setLayerColor(layer, value)
    if not layer then return false end
    local color = hexToColor(value)
    if color then
        layer.color = color
        self.editor:clearDiagnostics("layer_color")
        for _, item in ipairs(self.list.items) do
            if item.data == layer then item.color = self:getLayerColor(layer) end
        end
        return true
    else
        self.editor:addWarning("Layer color must use #RRGGBB or #RRGGBBAA", nil, "layer_color")
        return false
    end
end

function EditorLayersPanel:setLayerDepth(layer, value, submitted)
    if not layer then return false end
    local depth = value == "" and false or tonumber(value)
    if depth ~= nil then
        layer._editor_depth_override = depth or nil
        self.editor:clearDiagnostics("layer_depth")
        return true
    elseif submitted then
        self.editor:addWarning("Layer depth override must be a number or blank", nil, "layer_depth")
    end
    return false
end

function EditorLayersPanel:createLayer(type_id)
    if not self.document then return false end
    local layer = self.document:createEditableLayer(type_id)
    if not layer then return false end
    self:refreshList(layer._editor_uid)
    self:warnVisualOnly()
    return true
end

function EditorLayersPanel:deleteLayer()
    if not self.document or not self.selected_layer then return false end
    local layers = self:getLayers()
    local index = 1
    for candidate_index, layer in ipairs(layers) do
        if layer == self.selected_layer then index = candidate_index break end
    end
    self.document:removeEditableLayer(self.selected_layer._editor_uid)
    self.selected_layer = nil
    local next_layer = #layers > 0 and layers[MathUtils.clamp(index, 1, #layers)] or nil
    self:refreshList(next_layer and next_layer._editor_uid)
    self:warnVisualOnly()
    return true
end

function EditorLayersPanel:finishLayerDrag(item, list, y)
    if not self.document or not item then return end
    local target = MathUtils.clamp(list:getItemIndexAt(y), 1, #self:getLayers())
    if self.document:moveEditableLayer(item.id, target) then
        self:refreshList(item.id)
        self:warnVisualOnly()
    end
end

function EditorLayersPanel:update(dt)
    local padding = 8
    self.new_button:setBounds(padding, padding, math.max(0, self.width - padding * 2), 28)
    local list_height = math.max(0, self.height - 52)
    self.list:setBounds(padding, 44, math.max(0, self.width - padding * 2), list_height)
    super.update(self, dt)
end

function EditorLayersPanel:drawSelf()
    Draw.setColor(0.08, 0.08, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
end

return EditorLayersPanel
