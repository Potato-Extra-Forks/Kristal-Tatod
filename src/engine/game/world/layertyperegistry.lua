---@class LayerTypeRegistry : Class
---@overload fun(): LayerTypeRegistry
local LayerTypeRegistry = Class()

local DEFAULT_KINDS = {
    {
        id = "group",
        format = {
            "id",
            "name",
            "layers"
        }
    },
    {
        id = "tile",
        format = {
            "default",
            "tileset",
            "chunks",
        },
        extra_format = {
            ["chunks"] = {
                "x",
                "y",
                "tile_data"
            }
        }
    },
    {
        id = "object",
        format = {
            "default",
            "draw_order",
            "objects"
        }
    },
    {
        id = "image",
        format = {
            "default",
            "image",
            "image_width",
            "image_height",
            "repeat_x",
            "repeat_y",
            "transparent_color"
        }
    }
}

local DEFAULT_TYPES = {
    { id = "default",        name = "Unknown",         kind = "object", icon = "editor/ui/layer/default",        color = { 0.8, 0.8, 0.82, 1 } },
    { id = "tile",           name = "Tiles",           kind = "tile",   icon = "editor/ui/layer/tile",           color = { 0.8, 0.8, 0.82, 1 } },
    { id = "image",          name = "Image",           kind = "image",  icon = "editor/ui/layer/image",          color = { 0.8, 0.8, 0.82, 1 } },
    { id = "objects",        name = "Objects",         kind = "object", icon = "editor/ui/layer/objects",        color = { 0, 1, 1, 1 } },
    { id = "controllers",    name = "Controllers",     kind = "object", icon = "editor/ui/layer/controllers",    color = { 0.72, 0.48, 1, 1 } },
    { id = "markers",        name = "Markers",         kind = "object", icon = "editor/ui/layer/markers",        color = { 1, 0.82, 0.16, 1 } },
    { id = "collision",      name = "Collision",       kind = "object", icon = "editor/ui/layer/collision",      color = { 0, 0, 1, 1 } },
    { id = "enemycollision", name = "Enemy Collision", kind = "object", icon = "editor/ui/layer/enemycollision", color = { 0, 1, 1, 1 } },
    { id = "blockcollision", name = "Block Collision", kind = "object", icon = "editor/ui/layer/blockcollision", color = { 1, 0.35, 0, 1 } },
    { id = "paths",          name = "Paths",           kind = "object", icon = "editor/ui/layer/paths",          color = { 1, 0.35, 0.85, 1 } },
    { id = "battleareas",    name = "Battle Areas",    kind = "object", icon = "editor/ui/layer/battleareas",    color = { 1, 0.25, 0.25, 1 } },
    { id = "battleborder",   name = "Battle Border",   kind = "tile",   icon = "editor/ui/layer/default",        color = { 0.75, 0.85, 1, 1 } },
}

function LayerTypeRegistry:init()
    LayerTypeRegistry.kinds = {}
    self.types = {}
    self.order = {}
    for _, definition in ipairs(DEFAULT_KINDS) do
        table.insert(self.kinds, definition)
    end
    for _, definition in ipairs(DEFAULT_TYPES) do
        self:register(definition.id, definition)
    end
end

---@param id string
---@param definition table
function LayerTypeRegistry:register(id, definition)
    assert(type(id) == "string" and id ~= "", "Layer type requires a non-empty id")
    assert(type(definition) == "table", "Layer type definition must be a table")
    local entry = TableUtils.copy(definition, true)
    entry.id = id
    entry.name = entry.name or id
    entry.icon = entry.icon or "editor/ui/layer/default"
    entry.color = entry.color or { 1, 1, 1, 1 }
    if not self.types[id] then table.insert(self.order, id) end
    self.types[id] = entry
    return entry
end

function LayerTypeRegistry:get(id)
    return self.types[id]
end

function LayerTypeRegistry:getAll()
    local result = {}
    for _, id in ipairs(self.order) do table.insert(result, self.types[id]) end
    return result
end

local function isLegacyType(layer, id)
    if layer.class ~= nil and layer.class ~= "" then return layer.class == id end
    return StringUtils.startsWith((layer.name or ""):lower(), id)
end

--- Resolves old Tiled layer naming/class conventions into an explicit editor
--- layer type. This is compatibility logic, not the new format representation.
function LayerTypeRegistry:getLegacyTiledType(layer)
    if layer.type == "tilelayer" or layer.type == "imagelayer" then
        if isLegacyType(layer, "battleborder") then return self.types.battleborder end
        return self.types[layer.type == "tilelayer" and "tile" or "image"]
    elseif layer.type == "objectgroup" then
        local ids = { "objects", "controllers", "markers", "collision", "enemycollision",
            "blockcollision", "paths", "battleareas" }
        for _, id in ipairs(ids) do
            if isLegacyType(layer, id) then return self.types[id] end
        end
    end
    return self.types.default
end

function LayerTypeRegistry:getLayerColor(layer, layer_type)
    local color = layer and layer.color
    if type(color) == "table" then
        local divisor = math.max(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 0) > 1 and 255 or 1
        return { (color[1] or 255) / divisor, (color[2] or 255) / divisor,
            (color[3] or 255) / divisor, (color[4] or divisor) / divisor }
    end
    layer_type = type(layer_type) == "table" and layer_type or self:get(layer_type)
    return TableUtils.copy(layer_type and layer_type.color or { 1, 1, 1, 1 })
end

return LayerTypeRegistry
