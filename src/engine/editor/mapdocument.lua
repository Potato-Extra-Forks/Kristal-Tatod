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

local function flattenVisualLayers(layers, result, parent)
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
            flattenVisualLayers(layer.layers, result, layer)
        elseif layer.type == "tilelayer" or layer.type == "imagelayer" then
            table.insert(result, layer)
        end
    end
    return result
end

function EditorMapDocument:init(editor, map_id)
    self.editor = editor
    self.primary_map_id = nil
    self.maps = {}
    self.map_lookup = {}
    if map_id then self:setPrimaryMap(map_id) end
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
    for _, layer in ipairs(flattenVisualLayers(data.layers)) do
        map.layers[layer.name] = depth
        if layer.type == "tilelayer" then
            map:loadTiles(layer, depth)
        else
            map:loadImage(layer, depth)
        end
        if not layer.properties.thin then depth = depth + map.depth_per_layer end
    end
    root:updateChildList()
    entry.width = map.width * map.tile_width
    entry.height = map.height * map.tile_height
    entry.tile_width = map.tile_width
    entry.tile_height = map.tile_height
    return { root = root, map = map }
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
    for _, child in ipairs(preview.root.children) do
        if child.visible and child.parent == preview.root then child:fullDraw() end
    end
    return true
end

return EditorMapDocument
