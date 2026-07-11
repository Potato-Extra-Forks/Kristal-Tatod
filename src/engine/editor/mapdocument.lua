---@class EditorMapDocument : Class
---@overload fun(editor: table, map_id?: string): EditorMapDocument
local EditorMapDocument = Class()

local function removeEntry(document, entry)
    for index, candidate in ipairs(document.maps) do
        if candidate == entry then
            table.remove(document.maps, index)
            break
        end
    end
    document.map_lookup[entry.id] = nil
end

local function flattenLayers(layers, result, parent)
    result = result or {}
    parent = parent or {
        offsetx = 0,
        offsety = 0,
        parallaxx = 1,
        parallaxy = 1,
        properties = {}
    }
    for _, source in ipairs(layers or {}) do
        local layer = TableUtils.copy(source, true)
        layer.properties = TableUtils.mergeMany(parent.properties, layer.properties or {})
        layer.offsetx = (layer.offsetx or 0) + parent.offsetx
        layer.offsety = (layer.offsety or 0) + parent.offsety
        layer.parallaxx = (layer.parallaxx or 1) * parent.parallaxx
        layer.parallaxy = (layer.parallaxy or 1) * parent.parallaxy
        if layer.type == "group" then
            flattenLayers(layer.layers, result, layer)
        else
            table.insert(result, layer)
        end
    end
    return result
end

local function setupLayerProperties(layer)
    layer.properties = layer.properties or {}
    layer._editor_property_types = layer._editor_property_types or {}
    local properties = EditorPropertySet(layer.properties, layer._editor_property_types)
    properties:registerProperty("thin", "boolean")
    if layer._editor_type_id == "objects" then properties:registerProperty("spawn", "boolean") end
    if layer._editor_type_id == "image" then
        properties:registerProperty("speedx", "number", { name = "Speed X" })
        properties:registerProperty("speedy", "number", { name = "Speed Y" })
        properties:registerProperty("wrapx", "boolean", { name = "Wrap X" })
        properties:registerProperty("wrapy", "boolean", { name = "Wrap Y" })
        properties:registerProperty("fitscreen", "boolean", { name = "Fit Screen" })
        properties:registerProperty("scalex", "number", { name = "Scale X", default = 1 })
        properties:registerProperty("scaley", "number", { name = "Scale Y", default = 1 })
    end
    layer._editor_property_set = properties
end

function EditorMapDocument:init(editor, map_id)
    self.editor = editor
    self.primary_map_id = nil
    self.maps = {}
    self.map_lookup = {}
    self.editable_layers = {}
    self.selected_layers = {}
    self.next_layer_uid = 1
    if map_id then self:setPrimaryMap(map_id) end
end

function EditorMapDocument:getEditableLayers(id)
    id = id or self.primary_map_id
    if not id then return {} end
    if not self.editable_layers[id] then
        local data = Registry.getMapData(id)
        local reader_class = Registry.getMapReader(id)
        local layers = flattenLayers(data and data.layers or {})
        for _, layer in ipairs(layers) do
            layer._editor_uid = self.next_layer_uid
            self.next_layer_uid = self.next_layer_uid + 1
            layer.properties = layer.properties or {}
            local layer_type = reader_class and reader_class.LEGACY_FORMAT
                and Registry.layer_types:getLegacyTiledType(layer)
                or Registry.getLayerType(layer._editor_type_id or "default")
            layer._editor_type_id = layer_type and layer_type.id or "default"
            layer._editor_visible = layer.visible ~= false
            setupLayerProperties(layer)
        end
        self.editable_layers[id] = layers
    end
    return self.editable_layers[id]
end

function EditorMapDocument:setSelectedLayer(uid, id)
    id = id or self.primary_map_id
    if not id then return false end
    self.selected_layers[id] = uid
    return true
end

function EditorMapDocument:getSelectedLayer(id)
    return self.selected_layers[id or self.primary_map_id]
end

function EditorMapDocument:setEditableLayerVisible(uid, visible, id)
    id = id or self.primary_map_id
    for _, layer in ipairs(self:getEditableLayers(id)) do
        if layer._editor_uid == uid then
            layer._editor_visible = visible ~= false
            return true
        end
    end
    return false
end

function EditorMapDocument:invalidatePreview(id)
    local entry = self.map_lookup[id or self.primary_map_id]
    if not entry then return false end
    entry.preview = nil
    entry.preview_attempted = false
    return true
end

function EditorMapDocument:createEditableLayer(type_id, id)
    id = id or self.primary_map_id
    local data = Registry.getMapData(id)
    if not data then return nil end
    local layers = self:getEditableLayers(id)
    local used, index = {}, 1
    for _, layer in ipairs(layers) do used[(layer.name or ""):lower()] = true end
    local layer_type = Registry.getLayerType(type_id or "tile") or Registry.getLayerType("default")
    local name = "New " .. (layer_type and layer_type.name or "Layer")
    while used[name:lower()] do
        index = index + 1
        name = "New " .. (layer_type and layer_type.name or "Layer") .. " " .. index
    end
    local kind = layer_type and layer_type.kind or "object"
    local layer = {
        _editor_uid = self.next_layer_uid,
        _editor_type_id = layer_type and layer_type.id or "default",
        type = kind == "tile" and "tilelayer" or (kind == "image" and "imagelayer" or "objectgroup"),
        name = name,
        width = data.width or 16,
        height = data.height or 12,
        visible = true,
        _editor_visible = true,
        opacity = 1,
        offsetx = 0,
        offsety = 0,
        parallaxx = 1,
        parallaxy = 1,
        properties = {},
        _editor_property_types = {},
        color = TableUtils.copy(layer_type and layer_type.color or { 0.8, 0.8, 0.82, 1 }, true)
    }
    self.next_layer_uid = self.next_layer_uid + 1
    if kind == "tile" then
        layer.encoding = "lua"
        layer.data = {}
        for tile = 1, layer.width * layer.height do layer.data[tile] = 0 end
    elseif kind == "object" then
        layer.objects = {}
    end
    table.insert(layers, layer)
    setupLayerProperties(layer)
    self:invalidatePreview(id)
    return layer
end

function EditorMapDocument:removeEditableLayer(uid, id)
    id = id or self.primary_map_id
    local layers = self:getEditableLayers(id)
    for index, layer in ipairs(layers) do
        if layer._editor_uid == uid then
            table.remove(layers, index)
            self:invalidatePreview(id)
            return layer
        end
    end
end

function EditorMapDocument:moveEditableLayer(uid, target_index, id)
    id = id or self.primary_map_id
    local layers = self:getEditableLayers(id)
    local source_index
    for index, layer in ipairs(layers) do
        if layer._editor_uid == uid then source_index = index break end
    end
    if not source_index then return false end
    target_index = MathUtils.clamp(target_index, 1, #layers)
    if source_index == target_index then return false end
    local layer = table.remove(layers, source_index)
    table.insert(layers, MathUtils.clamp(target_index, 1, #layers + 1), layer)
    self:invalidatePreview(id)
    return true
end

function EditorMapDocument:hasMap(id)
    return self.map_lookup[id] ~= nil
end

function EditorMapDocument:addMap(id, x, y, options)
    options = options or {}
    local explicit_companion = options.explicit_companion ~= false
    if not id or not Registry.getMap(id) and not Registry.getMapData(id) then return nil end
    local entry = self.map_lookup[id]
    if entry then
        if x ~= nil then entry.x = x end
        if y ~= nil then entry.y = y end
        if explicit_companion then entry.explicit_companion = true end
    else
        local data = Registry.getMapData(id)
        entry = {
            id = id,
            x = x or 0,
            y = y or 0,
            width = data and (data.width or 16) * (data.tilewidth or 40),
            height = data and (data.height or 12) * (data.tileheight or 40),
            tile_width = data and data.tilewidth or 40,
            tile_height = data and data.tileheight or 40,
            explicit_companion = explicit_companion,
            preview = nil,
            preview_attempted = false
        }
        self.map_lookup[id] = entry
        table.insert(self.maps, entry)
    end
    if options.primary then self:setPrimaryMap(id) end
    return entry
end

function EditorMapDocument:setPrimaryMap(id)
    local entry = self:addMap(id, nil, nil, { explicit_companion = false })
    if not entry then return false end
    local previous = self.primary_map_id and self.map_lookup[self.primary_map_id]
    if previous and previous ~= entry then
        previous.primary = false
        if not previous.explicit_companion then removeEntry(self, previous) end
    end
    self.primary_map_id = id
    entry.primary = true
    return true
end

function EditorMapDocument:getPrimaryMap()
    return self.primary_map_id and self.map_lookup[self.primary_map_id] or nil
end

function EditorMapDocument:setMapPosition(id, x, y)
    local entry = self.map_lookup[id]
    if not entry then return false end
    entry.x, entry.y = x or entry.x, y or entry.y
    return true
end

function EditorMapDocument:removeMap(id)
    if id == self.primary_map_id then return false end
    local entry = self.map_lookup[id]
    if not entry then return false end
    removeEntry(self, entry)
    return true
end

function EditorMapDocument:createPreview(entry)
    local data = Registry.getMapData(entry.id)
    if not data then return nil, "no registered map data is available" end

    local root = Object()
    local map = Map(root, data)
    map.id = entry.id
    local depth = map.depth_per_layer
    local editor_events = {}
    local editor_overlays = {}
    local drawable_layers = {}
    local layer_lookup = {}
    local layer_registry = Registry.layer_types
    local reader_class = Registry.getMapReader(entry.id)
    for _, layer in ipairs(self:getEditableLayers(entry.id)) do
        layer_lookup[layer._editor_uid] = layer
        local layer_depth = layer._editor_depth_override or depth
        map.layers[layer.name] = layer_depth
        if layer.type == "tilelayer" then
            map:loadTiles(layer, layer_depth)
            local drawable = map.tile_layers[#map.tile_layers]
            drawable.visible = true
            drawable_layers[drawable] = layer._editor_uid
        elseif layer.type == "imagelayer" and layer.image then
            map:loadImage(layer, layer_depth)
            local drawable = map.image_layers[layer.name]
            drawable.visible = true
            drawable_layers[drawable] = layer._editor_uid
        elseif layer.type == "objectgroup" then
            local layer_type = layer_registry:get(layer._editor_type_id)
                or (reader_class and reader_class.LEGACY_FORMAT and layer_registry:getLegacyTiledType(layer))
            if layer_type and layer_type.id == "objects" then
                local layer_color = layer_registry:getLayerColor(layer, layer_type)
                for _, object in ipairs(layer.objects or {}) do
                    local event_id = object.type or object.class
                    if event_id == nil or event_id == "" then event_id = object.name end
                    table.insert(editor_events, Registry.createEditorEvent(event_id, object, {
                        depth = layer_depth,
                        layer_uid = layer._editor_uid,
                        layer = layer,
                        layer_type = layer_type,
                        layer_color = layer_color,
                        offset_x = layer.offsetx or 0,
                        offset_y = layer.offsety or 0,
                        map_id = entry.id,
                        map_data = data
                    }))
                end
            elseif layer_type then
                table.insert(editor_overlays, EditorLayerOverlay(layer, layer_type, layer_depth))
            end
        end
        if not layer.properties.thin then depth = depth + map.depth_per_layer end
    end
    root:updateChildList()
    entry.width = map.width * map.tile_width
    entry.height = map.height * map.tile_height
    entry.tile_width = map.tile_width
    entry.tile_height = map.tile_height
    return {
        root = root,
        map = map,
        editor_events = editor_events,
        editor_overlays = editor_overlays,
        drawable_layers = drawable_layers,
        layer_lookup = layer_lookup
    }
end

function EditorMapDocument:getPreview(entry)
    if entry.preview_attempted then return entry.preview end
    entry.preview_attempted = true
    local success, preview, reason = pcall(function()
        local result, failure = self:createPreview(entry)
        return result, failure
    end)
    if success then
        entry.preview = preview
        reason = reason or (not preview and "preview creation failed")
    else
        reason = preview
    end
    if not entry.preview and self.editor then
        self.editor:addWarning(string.format("Could not preview map '%s': %s", entry.id, reason),
            nil, "map_preview:" .. entry.id)
    end
    return entry.preview
end

function EditorMapDocument:drawPreview(entry)
    local preview = self:getPreview(entry)
    if not preview then return false end
    local map = preview.map
    Draw.setColor(map.bg_color or { 0, 0, 0, 0 })
    love.graphics.rectangle("fill", 0, 0, entry.width, entry.height)
    Draw.setColor(1, 1, 1, 1)
    local drawables = {}
    local selected_uid = self:getSelectedLayer(entry.id)
    local function layerState(uid)
        local layer = uid and preview.layer_lookup[uid]
        if layer and layer._editor_visible == false then return false, 0 end
        return true, (selected_uid == nil or selected_uid == uid) and 1 or 0.35
    end
    for index, child in ipairs(preview.root.children) do
        local uid = preview.drawable_layers[child]
        local layer_visible, alpha = layerState(uid)
        if child.visible and child.parent == preview.root and layer_visible then
            table.insert(drawables, {
                layer = child.layer or 0, index = index, value = child, object = true, alpha = alpha
            })
        end
    end
    local offset = #drawables
    for index, event in ipairs(preview.editor_events or {}) do
        local layer_visible, alpha = layerState(event.layer_uid)
        if event.visible and layer_visible then
            table.insert(drawables, { layer = event.layer or 0, index = offset + index, value = event, alpha = alpha })
        end
    end
    offset = offset + #(preview.editor_events or {})
    for index, overlay in ipairs(preview.editor_overlays or {}) do
        local layer_visible, alpha = layerState(overlay.layer_uid)
        if overlay.visible and layer_visible then
            table.insert(drawables, {
                layer = overlay.layer or 0, index = offset + index, value = overlay, alpha = alpha
            })
        end
    end
    table.sort(drawables, function(a, b)
        if a.layer == b.layer then return a.index < b.index end
        return a.layer < b.layer
    end)
    for _, drawable in ipairs(drawables) do
        if drawable.object then
            local old_alpha = drawable.value.alpha
            drawable.value.alpha = (old_alpha or 1) * drawable.alpha
            drawable.value:fullDraw()
            drawable.value.alpha = old_alpha
        else
            drawable.value:draw(drawable.alpha)
        end
    end
    for _, event in ipairs(preview.editor_events or {}) do
        local layer_visible, alpha = layerState(event.layer_uid)
        if event.visible and layer_visible then event:drawBounds(alpha) end
    end
    Draw.setColor(1, 1, 1, 1)
    return true
end

return EditorMapDocument
