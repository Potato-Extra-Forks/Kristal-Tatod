---@class EditorMapDocument : Class
---@overload fun(editor: table, map_id?: string): EditorMapDocument
local EditorMapDocument = Class()

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
    self.world = EditorWorld(map_id and ("session:" .. map_id) or nil)
    self.primary_map_id = self.world.primary_map_id
    self.maps = self.world.maps
    self.map_lookup = self.world.map_lookup
    self.editable_layers = {}
    self.selected_layers = {}
    self.next_layer_uid = 1
    self.next_object_uid = 1
    self.history_revision = 0
    self.saved_history_revision = 0
    if map_id then self:setPrimaryMap(map_id) end
end

function EditorMapDocument:captureHistoryState()
    local layers = TableUtils.copy(self.editable_layers, true)
    for _, map_layers in pairs(layers) do
        for _, layer in ipairs(map_layers) do layer._editor_property_set = nil end
    end
    local maps = {}
    for _, entry in ipairs(self.maps) do
        table.insert(maps, {
            id = entry.id, x = entry.x, y = entry.y,
            explicit_companion = entry.explicit_companion == true,
            primary = entry.id == self.primary_map_id
        })
    end
    return {
        world_id = self.world.id,
        primary_map_id = self.primary_map_id,
        maps = maps,
        editable_layers = layers,
        selected_layers = TableUtils.copy(self.selected_layers, true),
        next_layer_uid = self.next_layer_uid,
        next_object_uid = self.next_object_uid
    }
end

function EditorMapDocument:restoreHistoryState(state)
    if not state then return false end
    local world = EditorWorld(state.world_id)
    for _, saved in ipairs(state.maps or {}) do
        local entry = world:addMap(saved.id, saved.x, saved.y, {
            explicit_companion = saved.explicit_companion
        })
        if entry then
            entry.explicit_companion = saved.explicit_companion
            entry.primary = saved.primary == true
        end
    end
    world.primary_map_id = state.primary_map_id
    self.world = world
    self.primary_map_id = state.primary_map_id
    self.maps, self.map_lookup = world.maps, world.map_lookup
    self.editable_layers = TableUtils.copy(state.editable_layers or {}, true)
    for _, layers in pairs(self.editable_layers) do
        for _, layer in ipairs(layers) do setupLayerProperties(layer) end
    end
    self.selected_layers = TableUtils.copy(state.selected_layers or {}, true)
    self.next_layer_uid = state.next_layer_uid or 1
    self.next_object_uid = state.next_object_uid or 1
    for _, entry in ipairs(self.maps) do
        entry.preview, entry.preview_attempted = nil, false
    end
    return true
end

function EditorMapDocument:isDirty()
    return (self.history_revision or 0) ~= (self.saved_history_revision or 0)
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
    return self.world:hasMap(id)
end

function EditorMapDocument:addMap(id, x, y, options)
    options = options or {}
    local entry = self.world:addMap(id, x, y, options)
    if options.primary then self:setPrimaryMap(id) end
    return entry
end

function EditorMapDocument:setPrimaryMap(id)
    if not self.world:setPrimaryMap(id) then return false end
    self.primary_map_id = id
    return true
end

function EditorMapDocument:getPrimaryMap()
    return self.world:getPrimaryMap()
end

function EditorMapDocument:setMapPosition(id, x, y)
    return self.world:setMapPosition(id, x, y)
end

function EditorMapDocument:removeMap(id)
    return self.world:removeMap(id)
end

function EditorMapDocument:getObjectId(object)
    object.properties = object.properties or {}
    local id = object.properties.uid or object.id or object._editor_uid
    if id == nil then
        id = "editor_object_" .. tostring(self.next_object_uid)
        self.next_object_uid = self.next_object_uid + 1
        object._editor_uid = id
    end
    return id
end

function EditorMapDocument:getSelectedObjectLayer(id)
    id = id or self.primary_map_id
    local selected = self:getSelectedLayer(id)
    local fallback
    for _, layer in ipairs(self:getEditableLayers(id)) do
        local layer_type = Registry.getLayerType(layer._editor_type_id)
        if layer._editor_uid == selected and layer_type and layer_type.kind == "object" then return layer end
        if layer_type and layer_type.kind == "object" and (not fallback or layer._editor_type_id == "objects") then
            fallback = layer
        end
    end
    return selected == nil and fallback or nil
end

function EditorMapDocument:getMapAt(world_x, world_y)
    for index = #self.maps, 1, -1 do
        local entry = self.maps[index]
        if world_x >= entry.x and world_y >= entry.y
            and world_x <= entry.x + (entry.width or 0) and world_y <= entry.y + (entry.height or 0) then
            return entry
        end
    end
end

function EditorMapDocument:addEditorObject(event_id, map_id, world_x, world_y)
    local positioned_entry = self:getMapAt(world_x, world_y)
    map_id = map_id or (positioned_entry and positioned_entry.id) or self.primary_map_id
    local entry = self.map_lookup[map_id]
    local layer = self:getSelectedObjectLayer(map_id)
    if not entry or not layer then return nil, "Select an object layer before placing an event" end
    local free = Input.ctrl()
    local tile_width, tile_height = entry.tile_width or 40, entry.tile_height or 40
    local local_x = world_x - entry.x - (layer.offsetx or 0)
    local local_y = world_y - entry.y - (layer.offsety or 0)
    if not free then
        local_x = MathUtils.round(local_x / tile_width) * tile_width
        local_y = MathUtils.round(local_y / tile_height) * tile_height
    end
    local object = {
        type = event_id,
        name = event_id,
        x = local_x,
        y = local_y,
        width = 0,
        height = 0,
        visible = true,
        properties = {},
        __editor_property_types = {}
    }
    self:getObjectId(object)
    layer.objects = layer.objects or {}
    table.insert(layer.objects, object)
    self:invalidatePreview(map_id)
    return object, layer, map_id
end

function EditorMapDocument:addShapeObject(shape, map_id, world_x, world_y, width, height)
    local positioned_entry = self:getMapAt(world_x, world_y)
    map_id = map_id or (positioned_entry and positioned_entry.id) or self.primary_map_id
    local entry = self.map_lookup[map_id]
    local layer = self:getSelectedObjectLayer(map_id)
    if not entry or not layer then return nil, "Select an object layer before creating a shape" end
    local local_x = world_x - entry.x - (layer.offsetx or 0)
    local local_y = world_y - entry.y - (layer.offsety or 0)
    local object = {
        name = shape,
        shape = shape,
        x = local_x,
        y = local_y,
        width = width,
        height = height,
        visible = true,
        properties = {},
        __editor_property_types = {}
    }
    if shape == "line" then object.polyline = { { x = 0, y = 0 }, { x = width, y = height } } end
    self:getObjectId(object)
    layer.objects = layer.objects or {}
    table.insert(layer.objects, object)
    self:invalidatePreview(map_id)
    return object, layer, map_id
end

function EditorMapDocument:addPolygonObject(map_id, points)
    if not points or #points < 3 then return nil, "A polygon requires at least three points" end
    local positioned_entry = self:getMapAt(points[1].x, points[1].y)
    map_id = map_id or (positioned_entry and positioned_entry.id) or self.primary_map_id
    local entry = self.map_lookup[map_id]
    local layer = self:getSelectedObjectLayer(map_id)
    if not entry or not layer then return nil, "Select an object layer before creating a polygon" end
    local min_x, min_y, max_x, max_y = points[1].x, points[1].y, points[1].x, points[1].y
    for _, point in ipairs(points) do
        min_x, min_y = math.min(min_x, point.x), math.min(min_y, point.y)
        max_x, max_y = math.max(max_x, point.x), math.max(max_y, point.y)
    end
    local object = {
        name = "polygon",
        shape = "polygon",
        x = min_x - entry.x - (layer.offsetx or 0),
        y = min_y - entry.y - (layer.offsety or 0),
        width = max_x - min_x,
        height = max_y - min_y,
        polygon = {},
        visible = true,
        properties = {},
        __editor_property_types = {}
    }
    for _, point in ipairs(points) do
        table.insert(object.polygon, { x = point.x - min_x, y = point.y - min_y })
    end
    self:getObjectId(object)
    layer.objects = layer.objects or {}
    table.insert(layer.objects, object)
    self:invalidatePreview(map_id)
    return object, layer, map_id
end

function EditorMapDocument:removeEditorObject(selection)
    if not selection or selection.document ~= self then return false end
    for index, object in ipairs(selection.layer.objects or {}) do
        if object == selection.data then
            table.remove(selection.layer.objects, index)
            self:invalidatePreview(selection.map_id)
            return true
        end
    end
    return false
end

function EditorMapDocument:duplicateEditorObject(selection)
    if not selection or selection.document ~= self then return nil end
    local copy = TableUtils.copy(selection.data, true)
    copy.id, copy._editor_uid = nil, nil
    copy.x = (copy.x or 0) + (selection.entry.tile_width or 40)
    self:getObjectId(copy)
    table.insert(selection.layer.objects, copy)
    self:invalidatePreview(selection.map_id)
    return copy, selection.layer
end

function EditorMapDocument:getObjectSelection(map_id, layer, object)
    return {
        document = self,
        world = self.world,
        map_id = map_id,
        entry = self.map_lookup[map_id],
        layer = layer,
        data = object,
        object_id = self:getObjectId(object)
    }
end

function EditorMapDocument:findObjectAt(world_x, world_y)
    for entry_index = #self.maps, 1, -1 do
        local entry = self.maps[entry_index]
        local layers = self:getEditableLayers(entry.id)
        for layer_index = #layers, 1, -1 do
            local layer = layers[layer_index]
            local layer_type = Registry.getLayerType(layer._editor_type_id)
            if layer._editor_visible ~= false and layer_type and layer_type.kind == "object" then
                local x = world_x - entry.x - (layer.offsetx or 0)
                local y = world_y - entry.y - (layer.offsety or 0)
                for object_index = #(layer.objects or {}), 1, -1 do
                    local object = layer.objects[object_index]
                    local width, height = object.width or 0, object.height or 0
                    local dx, dy = x - (object.x or 0), y - (object.y or 0)
                    local rotation = -math.rad(object.rotation or 0)
                    local local_x = dx * math.cos(rotation) - dy * math.sin(rotation)
                    local local_y = dx * math.sin(rotation) + dy * math.cos(rotation)
                    local hit = width == 0 and height == 0
                        and math.abs(local_x) <= 10 and math.abs(local_y) <= 10
                        or local_x >= 0 and local_y >= 0 and local_x <= width and local_y <= height
                    if hit then return self:getObjectSelection(entry.id, layer, object) end
                end
            end
        end
    end
end

function EditorMapDocument:getObjectWorldCorners(selection)
    local x, y = self:getObjectWorldPosition(selection)
    local width, height = selection.data.width or 0, selection.data.height or 0
    local rotation = math.rad(selection.data.rotation or 0)
    local cosine, sine = math.cos(rotation), math.sin(rotation)
    local result = {}
    for _, point in ipairs({ { 0, 0 }, { width, 0 }, { width, height }, { 0, height } }) do
        table.insert(result, {
            x = x + point[1] * cosine - point[2] * sine,
            y = y + point[1] * sine + point[2] * cosine
        })
    end
    return result
end

function EditorMapDocument:getObjectWorldBounds(selection)
    local corners = self:getObjectWorldCorners(selection)
    local min_x, min_y, max_x, max_y = corners[1].x, corners[1].y, corners[1].x, corners[1].y
    for index = 2, #corners do
        local point = corners[index]
        min_x, min_y = math.min(min_x, point.x), math.min(min_y, point.y)
        max_x, max_y = math.max(max_x, point.x), math.max(max_y, point.y)
    end
    return min_x, min_y, max_x, max_y
end

function EditorMapDocument:findObjectsInRect(x1, y1, x2, y2)
    local min_x, min_y, max_x, max_y = math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
    local result = {}
    for _, entry in ipairs(self.maps) do
        for _, layer in ipairs(self:getEditableLayers(entry.id)) do
            local layer_type = Registry.getLayerType(layer._editor_type_id)
            if layer._editor_visible ~= false and layer_type and layer_type.kind == "object" then
                for _, object in ipairs(layer.objects or {}) do
                    if object.visible ~= false then
                        local selection = self:getObjectSelection(entry.id, layer, object)
                        local left, top, right, bottom = self:getObjectWorldBounds(selection)
                        if right >= min_x and bottom >= min_y and left <= max_x and top <= max_y then
                            table.insert(result, selection)
                        end
                    end
                end
            end
        end
    end
    return result
end

function EditorMapDocument:getObjectWorldPosition(selection)
    local data, layer, entry = selection.data, selection.layer, selection.entry
    return entry.x + (layer.offsetx or 0) + (data.x or 0),
        entry.y + (layer.offsety or 0) + (data.y or 0)
end

function EditorMapDocument:getObjectWorldCenter(selection)
    local x, y = self:getObjectWorldPosition(selection)
    local half_width, half_height = (selection.data.width or 0) / 2, (selection.data.height or 0) / 2
    local rotation = math.rad(selection.data.rotation or 0)
    return x + half_width * math.cos(rotation) - half_height * math.sin(rotation),
        y + half_width * math.sin(rotation) + half_height * math.cos(rotation)
end

function EditorMapDocument:createObjectReference(selection)
    return self.world:createReference(selection.map_id, selection.object_id)
end

function EditorMapDocument:resolveObjectReference(value)
    local reference = EditorObjectReference.from(value, self.primary_map_id)
    if reference.object_id == nil then return nil end
    local layers = self:getEditableLayers(reference.map_id)
    for _, layer in ipairs(layers) do
        for _, object in ipairs(layer.objects or {}) do
            if tostring(self:getObjectId(object)) == tostring(reference.object_id) then
                return self:getObjectSelection(reference.map_id, layer, object)
            end
        end
    end
end

function EditorMapDocument:addObjectFX(selection, fx_id)
    if not selection or selection.document ~= self or not Registry.getEditorDrawFX(fx_id) then return false end
    selection.data.__editor_fx = selection.data.__editor_fx or {}
    local fx = Registry.createEditorDrawFX(fx_id)
    table.insert(selection.data.__editor_fx, fx.data)
    return fx
end

function EditorMapDocument:getObjectReferenceValues(selection)
    local data = selection.data
    local event_id = data.type or data.class
    if event_id == nil or event_id == "" then event_id = data.name end
    local result = {}
    local success, event = pcall(Registry.createEditorEvent, event_id, data, { map_id = selection.map_id })
    if success and event then
        for _, definition in ipairs(event.property_set:getProperties()) do
            if definition.type == "object_reference" then
                local value = event.property_set.values[definition.id]
                if value ~= nil then table.insert(result, value) end
            end
        end
    end
    for name, type_id in pairs(data.__editor_property_types or {}) do
        if type_id == "object_reference" and data.properties[name] ~= nil then
            table.insert(result, data.properties[name])
        end
    end
    return result
end

function EditorMapDocument:getObjectLinks(selection)
    local links, seen = {}, {}
    local function add(candidate)
        if candidate and candidate.data ~= selection.data then
            local key = candidate.map_id .. ":" .. tostring(candidate.object_id)
            if not seen[key] then seen[key] = true table.insert(links, candidate) end
        end
    end
    for _, value in ipairs(self:getObjectReferenceValues(selection)) do add(self:resolveObjectReference(value)) end
    for _, entry in ipairs(self.maps) do
        for _, layer in ipairs(self:getEditableLayers(entry.id)) do
            for _, object in ipairs(layer.objects or {}) do
                if object ~= selection.data then
                    local candidate = self:getObjectSelection(entry.id, layer, object)
                    for _, value in ipairs(self:getObjectReferenceValues(candidate)) do
                        local reference = EditorObjectReference.from(value, entry.id)
                        if reference:matches(selection.map_id, selection.object_id) then add(candidate) end
                    end
                end
            end
        end
    end
    return links
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
            if layer_type and (layer_type.id == "objects" or layer_type.id == "controllers") then
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
        local darken = not self.editor or self.editor.darken_unselected_layers ~= false
        return true, (not darken or selected_uid == nil or selected_uid == uid) and 1 or 0.35
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
