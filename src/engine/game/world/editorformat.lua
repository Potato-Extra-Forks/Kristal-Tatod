-- Native editor map, tileset, and world JSON format.

local EditorFormat = {}

EditorFormat.MAP_FORMAT_VERSION = 1
EditorFormat.TILESET_FORMAT_VERSION = 1
EditorFormat.WORLD_FORMAT_VERSION = 1
EditorFormat.TILED_MAP_CONVERSION_VERSION = 1
EditorFormat.TILED_TILESET_CONVERSION_VERSION = 1
EditorFormat.MAP_EXTENSION = ".json"
EditorFormat.TILESET_EXTENSION = ".json"
EditorFormat.WORLD_EXTENSION = ".json"
EditorFormat.WORLD_DIRECTORY = "world/worlds"

EditorFormat.TILE_FLIP_HORIZONTAL = 0x80000000
EditorFormat.TILE_FLIP_VERTICAL = 0x40000000
EditorFormat.TILE_ROTATE = 0x20000000
EditorFormat.TILE_ID_MASK = 0x1FFFFFFF
EditorFormat.CHUNK_SIZE = 16

function EditorFormat.slugId(value, fallback)
    local id = tostring(value or ""):lower()
    id = id:gsub("[^%w_ ]", "_"):gsub("%s+", "_"):gsub("_+", "_")
    id = id:gsub("^_+", ""):gsub("_+$", "")
    return id ~= "" and id or (fallback or "unnamed")
end

function EditorFormat.uniqueSlug(value, used, fallback)
    local base = EditorFormat.slugId(value, fallback)
    local id, index = base, 2
    while used[id] do
        id = base .. "_" .. index
        index = index + 1
    end
    used[id] = true
    return id
end

local function nextNumericId(preferred, used, state)
    preferred = tonumber(preferred)
    if preferred and preferred >= 1 and preferred % 1 == 0 and not used[preferred] then
        used[preferred] = true
        state.next_id = math.max(state.next_id, preferred + 1)
        return preferred
    end
    while used[state.next_id] do state.next_id = state.next_id + 1 end
    local id = state.next_id
    used[id] = true
    state.next_id = state.next_id + 1
    return id
end

function EditorFormat.packTile(tile_id, flip_x, flip_y, rotated)
    if tile_id == nil then return 0 end
    local payload = tile_id + 1
    assert(payload > 0 and payload <= EditorFormat.TILE_ID_MASK, "Tile id is outside the packed range")
    local packed = payload
    if flip_x then packed = bit.bor(packed, EditorFormat.TILE_FLIP_HORIZONTAL) end
    if flip_y then packed = bit.bor(packed, EditorFormat.TILE_FLIP_VERTICAL) end
    if rotated then packed = bit.bor(packed, EditorFormat.TILE_ROTATE) end
    if packed < 0 then packed = packed + 0x100000000 end
    return packed
end

function EditorFormat.unpackTile(packed)
    packed = tonumber(packed) or 0
    if packed == 0 then return nil, false, false, false end
    local signed = bit.tobit(packed)
    local payload = bit.band(signed, EditorFormat.TILE_ID_MASK)
    if payload == 0 then return nil, false, false, false end
    return payload - 1,
        bit.band(signed, EditorFormat.TILE_FLIP_HORIZONTAL) ~= 0,
        bit.band(signed, EditorFormat.TILE_FLIP_VERTICAL) ~= 0,
        bit.band(signed, EditorFormat.TILE_ROTATE) ~= 0
end

function EditorFormat.remapTileId(tile_id, old_columns, old_rows, new_columns, new_rows)
    old_columns, new_columns = tonumber(old_columns), tonumber(new_columns)
    if not old_columns or old_columns <= 0 or not new_columns or new_columns <= 0 then return tile_id end
    local x = tile_id % old_columns
    local y = math.floor(tile_id / old_columns)
    if old_rows and old_rows > 0 and y >= old_rows then return nil end
    if x >= new_columns then return nil end
    if new_rows and new_rows > 0 and y >= new_rows then return nil end
    return x + y * new_columns
end

EditorFormat.ORDERING = {
    map = {
        "version",
        "kristal_version",
        "id",
        "name",
        "width",
        "height",
        "grid_width",
        "grid_height",
        "background_color",
        "parallax_origin_x",
        "parallax_origin_y",
        "layers",
        "properties"
    },
    tileset = {
        "version",
        "kristal_version",
        "id",
        "name",
        "image",
        "image_width",
        "image_height",
        "tile_width",
        "tile_height",
        "tile_count",
        "tile_rows",
        "tile_columns",
        "spacing",
        "margin",
        "alignment",
        "render_size",
        "fill_mode",
        "tile_offset_x",
        "tile_offset_y",
        "transparent_color",
        "transform_rules",
        "tiles",
        "terrains",
        "properties"
    },
    tile = {
        "id",
        "type",
        "x",
        "y",
        "width",
        "height",
        "probability",
        "collision",
        "frames",
        "properties",
    },
    layer = {
        "id",
        "name",
        "color",
        "x",
        "y",
        "type",
        "kind",
        "depth",
        "alpha",
        "visible",
        "parallax_x",
        "parallax_y",
        "tile_width_override",
        "tile_height_override",
        "properties"
        --- extra kind specific info here
    },
    transform_rules = {
        "can_vflip",
        "can_hflip",
        "can_rotate",
        "prefer_untransformed",
    },
    world = {
        "version",
        "kristal_version",
        "id",
        "name",
        "maps",
        "properties"
    },
    world_map = {
        "map",
        "x",
        "y"
    },
    terrain = {
        "id",
        "name",
        "tile_icon",
        "type",
        "terrain_variants",
        "terrain_tiles",
        "properties",
    },
    object = {
        "id",
        "name",
        "type",
        "x",
        "y",
        "width",
        "height",
        "rotation",
        "shape",
        "scale_x",
        "scale_y",
        "origin_x",
        "origin_y",
        "alpha",
        "visible",
        "fx",
        "tileset", --- For tile objects
        "tile_id", --- --^
        "properties"
    },
    shape = {
        "type",
        "shape_data" --- table value- points for polygons, bounds for boxes, radius for circles etc
    },
    terrain_variant = {
        "id",
        "name",
        "color",
        "tile_icon",
        "probability",
        "properties"
    },
    terrain_tile = {
        "tile_id",
        "edges" -- 8 size table
    },
    frame = {
        "tile_id",
        "duration"
    },
    fx = {
        "type",
        "properties"
    },
    property = {
        "name",
        "type",
        "value"
    }
}

--- shape_data stuff. x/y is offset from object position. points and such are in local coordinates around shape center.
EditorFormat.SHAPE_DATA_TYPES = {
    point = {
        "x",
        "y"
    },
    line = {
        "x",
        "y",
        "points",
        "thickness"
    },
    rectangle = {
        "x",
        "y",
        "bounds",
        "rotation"
    },
    ellipse = {
        "x",
        "y",
        "radius",
        "radius_x", -- collapses into just one 'radius' value for a circle
        "radius_y", -- ^^^
        "rotation"
    },
    polygon = {
        "x",
        "y",
        "points",
        "rotation"
    }
}

local ARRAY_CHILDREN = {
    layers = "layer",
    properties = "property",
    objects = "object",
    chunks = "chunk",
    tiles = "tile",
    terrains = "terrain",
    terrain_variants = "terrain_variant",
    terrain_tiles = "terrain_tile",
    frames = "frame",
    fx = "fx",
    maps = "world_map",
    collision = "object"
}

local SERIALIZATION_METADATA = {
    full_path = true,
    __map_reader = true,
    __tileset_reader = true,
    __editor_property_types = true,
    __editor_property_order = true,
    _editor_property_types = true,
    _editor_property_order = true,
    _editor_property_set = true
}

local function isArray(value)
    if rawget(value, 1) ~= nil or next(value) == nil then
        local count = 0
        for key in pairs(value) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
            count = count + 1
        end
        return count == #value
    end
    return false
end

local function getOrdering(schema, value)
    if schema == "layer" then
        return Registry.layer_types:getKindFormat(value.kind or "object", EditorFormat.ORDERING.layer)
    elseif schema and StringUtils.startsWith(schema, "shape_data:") then
        return EditorFormat.SHAPE_DATA_TYPES[schema:sub(12)]
    elseif schema == "chunk" then
        local tile_kind = Registry.getLayerKind("tile")
        return tile_kind and tile_kind.extra_format and tile_kind.extra_format.chunks
    end
    return EditorFormat.ORDERING[schema]
end

local function getChildSchema(schema, key, value)
    local child = ARRAY_CHILDREN[key]
    if child then return "array:" .. child end
    if schema == "chunk" and key == "tile_data" then
        return "compact_array:" .. EditorFormat.CHUNK_SIZE
    end
    if key == "shape" then return "shape" end
    if key == "shape_data" then return "shape_data:" .. tostring(schema == "shape" and value.type or "") end
    if key == "transform_rules" then return "transform_rules" end
end

local function shouldSerialize(key, value)
    if type(key) ~= "string" or SERIALIZATION_METADATA[key] then return false end
    if StringUtils.startsWith(key, "_editor") then return false end
    return type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread"
end

local function encodeJSONValue(value, schema, options, depth, seen)
    local value_type = type(value)
    if value_type ~= "table" then
        local success, encoded = pcall(JSON.encode, value)
        if not success then return nil, encoded end
        return encoded
    end
    if seen[value] then return nil, "Cannot encode a circular JSON table" end
    seen[value] = true

    local pretty = options.pretty ~= false
    local indent = options.indent
    if type(indent) == "number" then indent = string.rep(" ", math.max(0, indent)) end
    indent = indent or "  "
    local newline = pretty and "\n" or ""
    local separator = pretty and ": " or ":"
    local padding = pretty and string.rep(indent, depth) or ""
    local child_padding = pretty and string.rep(indent, depth + 1) or ""
    local array_schema = schema and schema:match("^array:(.+)$")
    local compact_width = schema and tonumber(schema:match("^compact_array:(%d+)$"))
    local array = array_schema ~= nil or compact_width ~= nil or schema == nil and isArray(value)
    local parts = {}

    if array then
        for index = 1, #value do
            local encoded, reason = encodeJSONValue(value[index], array_schema, options, depth + 1, seen)
            if not encoded then seen[value] = nil return nil, reason end
            parts[index] = encoded
        end
        seen[value] = nil
        if #parts == 0 then return "[]" end
        if compact_width and pretty then
            local rows = {}
            for first = 1, #parts, compact_width do
                local row = {}
                for index = first, math.min(first + compact_width - 1, #parts) do
                    table.insert(row, parts[index])
                end
                table.insert(rows, child_padding .. table.concat(row, ", "))
            end
            return "[" .. newline .. table.concat(rows, "," .. newline) .. newline .. padding .. "]"
        end
        for index, encoded in ipairs(parts) do parts[index] = child_padding .. encoded end
        return "[" .. newline .. table.concat(parts, "," .. newline) .. newline .. padding .. "]"
    end

    local keys, included = {}, {}
    for _, key in ipairs(getOrdering(schema, value) or {}) do
        if value[key] ~= nil and shouldSerialize(key, value[key]) and not included[key] then
            table.insert(keys, key)
            included[key] = true
        end
    end
    local remaining = {}
    for key, child_value in pairs(value) do
        if not included[key] and shouldSerialize(key, child_value) then table.insert(remaining, key) end
    end
    table.sort(remaining)
    for _, key in ipairs(remaining) do table.insert(keys, key) end

    for _, key in ipairs(keys) do
        local child_schema = getChildSchema(schema, key, value)
        local encoded, reason = encodeJSONValue(value[key], child_schema, options, depth + 1, seen)
        if not encoded then seen[value] = nil return nil, reason end
        table.insert(parts, child_padding .. JSON.encode(key) .. separator .. encoded)
    end
    seen[value] = nil
    if #parts == 0 then return "{}" end
    return "{" .. newline .. table.concat(parts, "," .. newline) .. newline .. padding .. "}"
end

function EditorFormat.encodeJSON(data, schema, options)
    return encodeJSONValue(data, schema, options or {}, 0, {})
end

function EditorFormat.decodeJSON(source, path)
    if type(source) ~= "string" then return nil, "JSON source must be a string" end
    local success, data = pcall(JSON.decode, source)
    if not success then return nil, string.format("Could not decode %s: %s", path or "JSON", data) end
    if type(data) ~= "table" then return nil, string.format("%s must contain a JSON object", path or "File") end
    return data
end

local function copySerializable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        if (type(key) == "number" or shouldSerialize(key, child)) and type(child) ~= "function" then
            result[key] = copySerializable(child, seen)
        end
    end
    return result
end

local function clearFields(value, fields)
    for _, field in ipairs(fields) do value[field] = nil end
    return value
end

local function decodeOwnerProperties(owner, context)
    local entries = owner.properties or {}
    if type(entries[1]) ~= "table" or entries[1].name == nil then
        owner.properties = entries
        owner.__editor_property_types = owner.__editor_property_types or {}
        return true
    end
    local set, reason = EditorPropertySet.fromEntries(entries, context)
    if not set then return false, reason end
    owner.properties = set.values
    owner.__editor_property_types = set.types
    owner.__editor_property_order = TableUtils.copy(set.order)
    return true
end

local function encodeOwnerProperties(owner, context)
    local properties = owner.properties or {}
    if type(properties[1]) == "table" and properties[1].name ~= nil then
        return copySerializable(properties)
    end
    local set = owner._editor_property_set or owner.property_set
        or EditorPropertySet(properties, owner.__editor_property_types or owner._editor_property_types,
            owner.__editor_property_order or owner._editor_property_order)
    return Registry.editor_properties:encodePropertySet(set, context)
end

local function decodeShape(shape)
    if type(shape) ~= "table" then return shape end
    return shape.type or "rectangle", copySerializable(shape.shape_data or {})
end

local function encodeShape(object)
    if type(object.shape) == "table" then return copySerializable(object.shape) end
    local shape_type = object.shape or (object.point and "point") or (object.ellipse and "ellipse")
        or (object.polygon and "polygon") or (object.polyline and "line") or "rectangle"
    local shape_data = copySerializable(object.shape_data or {})
    if shape_type == "polygon" and shape_data.points == nil then shape_data.points = copySerializable(object.polygon or {}) end
    if shape_type == "line" and shape_data.points == nil then shape_data.points = copySerializable(object.polyline or {}) end
    return { type = shape_type, shape_data = shape_data }
end

local decodeObject, encodeObject, decodeLayer, encodeLayer

decodeObject = function(object, context)
    object = copySerializable(object)
    local shape, shape_data = decodeShape(object.shape)
    object.shape, object.shape_data = shape, shape_data
    if shape == "polygon" then object.polygon = copySerializable(shape_data.points or {}) end
    if shape == "line" then object.polyline = copySerializable(shape_data.points or {}) end
    local success, reason = decodeOwnerProperties(object, context)
    if not success then return nil, reason end
    for _, fx in ipairs(object.fx or {}) do
        fx.id = fx.id or fx.type
        local fx_success, fx_reason = decodeOwnerProperties(fx, context)
        if not fx_success then return nil, fx_reason end
    end
    object.__editor_fx = object.fx
    return object
end

encodeObject = function(object, context)
    local result = copySerializable(object)
    clearFields(result, { "class", "point", "ellipse", "polygon", "polyline", "shape_data", "__editor_fx" })
    result.type = object.type or object.class
    context.object_ids = context.object_ids or {}
    context.object_id_state = context.object_id_state or { next_id = 1 }
    result.id = nextNumericId(object.id, context.object_ids, context.object_id_state)
    result.shape = encodeShape(object)
    result.properties = nil
    local properties, reason = encodeOwnerProperties(object, context)
    if not properties then return nil, reason end
    result.properties = properties
    result.fx = {}
    for _, source_fx in ipairs(object.__editor_fx or object.fx or {}) do
        local fx = copySerializable(source_fx)
        fx.type = fx.type or fx.id
        fx.id = nil
        fx.properties = nil
        fx.properties, reason = encodeOwnerProperties(source_fx, context)
        if not fx.properties then return nil, reason end
        table.insert(result.fx, fx)
    end
    if #result.fx == 0 then result.fx = nil end
    return result
end

local function getLayerKind(layer)
    local kind = layer._editor_kind_id or layer.kind
    if kind then return kind end
    local layer_type = Registry.getLayerType(layer._editor_type_id or layer.type)
    return layer_type and layer_type.kind or "object"
end

decodeLayer = function(source, context)
    local semantic_type = source.type or "default"
    local registered_type = Registry.getLayerType(semantic_type)
    local kind = source.kind or (registered_type and registered_type.kind) or "object"
    local layer, reason = Registry.layer_types:decodeKind(kind, source, context)
    if not layer then return nil, reason end
    layer._editor_type_id = semantic_type
    layer._editor_kind_id = kind
    layer._editor_depth_override = layer.depth
    layer._editor_visible = layer.visible ~= false
    layer.offsetx = layer.x or 0
    layer.offsety = layer.y or 0
    layer.opacity = layer.alpha == nil and 1 or layer.alpha
    layer.parallaxx = layer.parallax_x or 1
    layer.parallaxy = layer.parallax_y or 1
    layer.repeatx = layer.repeat_x
    layer.repeaty = layer.repeat_y
    layer.type = kind == "tile" and "tilelayer" or kind == "image" and "imagelayer"
        or kind == "group" and "group" or "objectgroup"
    local success
    success, reason = decodeOwnerProperties(layer, context)
    if not success then return nil, reason end
    if kind == "group" then
        local children = {}
        for _, child in ipairs(layer.layers or {}) do
            local decoded
            decoded, reason = decodeLayer(child, context)
            if not decoded then return nil, reason end
            table.insert(children, decoded)
        end
        layer.layers = children
    elseif kind == "object" then
        local objects = {}
        for _, object in ipairs(layer.objects or {}) do
            local decoded
            decoded, reason = decodeObject(object, context)
            if not decoded then return nil, reason end
            table.insert(objects, decoded)
        end
        layer.objects = objects
    end
    return layer
end

encodeLayer = function(source, context)
    local kind = getLayerKind(source)
    if kind == "tile" and not source.chunks and type(source.data) == "table" and #source.data > 0 then
        return nil, "Legacy tile data must be converted to per-tileset packed chunks before saving"
    end
    local candidate, reason = Registry.layer_types:encodeKind(kind, source, context)
    if not candidate then return nil, reason end
    local result = copySerializable(candidate)
    clearFields(result, {
        "class", "offsetx", "offsety", "opacity", "parallaxx", "parallaxy", "repeatx", "repeaty",
        "draworder", "imagewidth", "imageheight", "transparentcolor", "tintcolor", "width", "height",
        "data", "encoding",
        "_editor_uid", "_editor_visible", "_editor_depth_override", "_editor_type_id", "_editor_kind_id"
    })
    result.type = source._editor_type_id or source.type or "default"
    if result.type == "tilelayer" or result.type == "imagelayer" or result.type == "objectgroup" or result.type == "group" then
        result.type = source._editor_type_id or "default"
    end
    result.kind = kind
    context.layer_ids = context.layer_ids or {}
    result.id = EditorFormat.uniqueSlug(source.name or source.id, context.layer_ids, "layer")
    result.x = source.x or source.offsetx
    result.y = source.y or source.offsety
    result.depth = source._editor_depth_override or source.depth
    result.alpha = source.alpha or source.opacity
    result.visible = source._editor_visible == nil and source.visible or source._editor_visible
    result.parallax_x = source.parallax_x or source.parallaxx
    result.parallax_y = source.parallax_y or source.parallaxy
    result.draw_order = source.draw_order or source.draworder
    result.repeat_x = source.repeat_x == nil and source.repeatx or source.repeat_x
    result.repeat_y = source.repeat_y == nil and source.repeaty or source.repeat_y
    result.image_width = source.image_width or source.imagewidth
    result.image_height = source.image_height or source.imageheight
    result.transparent_color = source.transparent_color or source.transparentcolor
    result.properties = nil
    result.properties, reason = encodeOwnerProperties(source, context)
    if not result.properties then return nil, reason end
    if kind == "group" then
        result.layers = {}
        for _, child in ipairs(source.layers or {}) do
            local encoded
            encoded, reason = encodeLayer(child, context)
            if not encoded then return nil, reason end
            table.insert(result.layers, encoded)
        end
    elseif kind == "object" then
        result.objects = {}
        for _, object in ipairs(source.objects or {}) do
            local encoded
            encoded, reason = encodeObject(object, context)
            if not encoded then return nil, reason end
            table.insert(result.objects, encoded)
        end
    end
    return result
end

local function decodeTile(tile, context)
    tile = copySerializable(tile)
    local success, reason = decodeOwnerProperties(tile, context)
    if not success then return nil, reason end
    if tile.frames and not tile.animation then
        tile.animation = {}
        for _, frame in ipairs(tile.frames) do
            table.insert(tile.animation, { tileid = frame.tile_id, duration = frame.duration })
        end
    end
    if tile.collision and not tile.objectgroup then
        tile.objectgroup = { objects = {} }
        for _, shape in ipairs(tile.collision) do
            local decoded, decode_reason = decodeObject(shape, context)
            if not decoded then return nil, decode_reason end
            table.insert(tile.objectgroup.objects, decoded)
        end
    end
    return tile
end

local function encodeTile(tile, context)
    local result = copySerializable(tile)
    clearFields(result, {
        "class", "image", "imagewidth", "imageheight", "animation", "objectgroup", "terrain",
        "__editor_property_types", "__editor_property_order"
    })
    result.type = tile.type or tile.class
    result.properties = nil
    local reason
    result.properties, reason = encodeOwnerProperties(tile, context)
    if not result.properties then return nil, reason end
    result.frames = nil
    if tile.animation or tile.frames then
        result.frames = {}
        for _, frame in ipairs(tile.animation or tile.frames) do
            table.insert(result.frames, { tile_id = frame.tile_id or frame.tileid, duration = frame.duration })
        end
    end
    result.collision = nil
    local collision = tile.objectgroup and tile.objectgroup.objects or tile.collision
    if collision then
        result.collision = {}
        local collision_context = { tileset = context.tileset, object_ids = {}, object_id_state = { next_id = 1 } }
        for _, shape in ipairs(collision) do
            local encoded
            encoded, reason = encodeObject(shape, collision_context)
            if not encoded then return nil, reason end
            table.insert(result.collision, encoded)
        end
    end
    return result
end

-- SECTION : Discovery

local function getContentDirectories(relative_path)
    local result = {}
    local function add(path)
        if love.filesystem.getInfo(path, "directory") then table.insert(result, path) end
    end
    add(relative_path)
    add("scripts/" .. relative_path)
    if Mod then
        for _, library in Kristal.iterLibraries() do
            if library.info and library.info.path then add(library.info.path .. "/scripts/" .. relative_path) end
        end
        add(Mod.info.path .. "/scripts/" .. relative_path)
    end
    return result
end

local function discoverJSON(relative_path, extension, decoder, callback)
    for _, directory in ipairs(getContentDirectories(relative_path)) do
        for _, relative in ipairs(FileSystemUtils.getFilesRecursive(directory, extension)) do
            local path = directory .. "/" .. relative .. extension
            local source, read_error = love.filesystem.read(path)
            if not source then error(string.format("Could not read '%s': %s", path, tostring(read_error)), 2) end
            local data, reason = decoder(source, path)
            if not data then error(reason, 2) end
            callback(data, relative, path)
        end
    end
end

---@param registry Registry
function EditorFormat.registerMaps(registry)
    discoverJSON(registry.paths.maps, EditorFormat.MAP_EXTENSION, EditorFormat.decodeMap,
        function(data, relative, path)
            data.id = data.id or relative
            data.full_path = path
            registry.registerMapData(data.id, data, EditorMapReader)
        end)
    return true
end

---@param registry Registry
function EditorFormat.registerTilesets(registry)
    discoverJSON(registry.paths.tilesets, EditorFormat.TILESET_EXTENSION, EditorFormat.decodeTileset,
        function(data, relative, path)
            data.id = data.id or relative
            data.full_path = path
            data.__tileset_reader = EditorTilesetReader
            registry.registerTileset(data.id, Tileset(data, path, FileSystemUtils.getDirname(path)))
        end)
    return true
end

function EditorFormat.registerWorlds(registry)
    discoverJSON(EditorFormat.WORLD_DIRECTORY, EditorFormat.WORLD_EXTENSION, EditorFormat.decodeWorld,
        function(data, relative)
            data.id = data.id or relative
            local world = EditorWorld(data.id)
            world.name = data.name or data.id
            world.data = data
            world.properties = data.properties or {}
            world.__editor_property_types = data.__editor_property_types or {}
            for _, map in ipairs(data.maps or {}) do
                world:addMap(map.map, map.x, map.y, { explicit_companion = true })
            end
            registry.registerEditorWorld(data.id, world)
        end)
    return true
end

-- SECTION : Encode/Decode

---@return table? data
---@return string? error
function EditorFormat.decodeMap(source, path, options)
    local data, reason = EditorFormat.decodeJSON(source, path)
    if not data then return nil, reason end
    data, reason = EditorFormat.migrateMap(data)
    if not data then return nil, reason end
    local valid, diagnostics = EditorFormat.validateMap(data, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    local success
    success, reason = decodeOwnerProperties(data, { owner = data, path = path })
    if not success then return nil, reason end
    local layers = {}
    for _, layer in ipairs(data.layers or {}) do
        local decoded
        decoded, reason = decodeLayer(layer, { map = data, path = path })
        if not decoded then return nil, reason end
        table.insert(layers, decoded)
    end
    data.layers = layers
    data.tilewidth = data.grid_width
    data.tileheight = data.grid_height
    data.backgroundcolor = data.background_color
    data.__map_reader = EditorMapReader
    return data
end

---@return string? encoded
---@return string? error
function EditorFormat.encodeMap(data, options)
    options = options or {}
    local result = copySerializable(data)
    clearFields(result, {
        "tilewidth", "tileheight", "backgroundcolor", "parallaxoriginx", "parallaxoriginy", "tilesets",
        "orientation", "renderorder", "infinite", "nextlayerid", "nextobjectid", "tiledversion",
        "luaversion", "compressionlevel", "class", "__map_reader", "full_path"
    })
    result.version = EditorFormat.MAP_FORMAT_VERSION
    result.kristal_version = result.kristal_version or tostring(Kristal.Version)
    result.grid_width = data.grid_width or data.tilewidth
    result.grid_height = data.grid_height or data.tileheight
    result.background_color = data.background_color or data.backgroundcolor
    result.parallax_origin_x = data.parallax_origin_x or data.parallaxoriginx
    result.parallax_origin_y = data.parallax_origin_y or data.parallaxoriginy
    result.properties = nil
    local reason
    result.properties, reason = encodeOwnerProperties(data, { owner = data })
    if not result.properties then return nil, reason end
    result.layers = {}
    local context = { map = result, layer_ids = {}, object_ids = {}, object_id_state = { next_id = 1 } }
    for _, layer in ipairs(data.layers or {}) do
        local encoded
        encoded, reason = encodeLayer(layer, context)
        if not encoded then return nil, reason end
        table.insert(result.layers, encoded)
    end
    local valid, diagnostics = EditorFormat.validateMap(result, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    return EditorFormat.encodeJSON(result, "map", options)
end

---@return table? data
---@return string? error
function EditorFormat.decodeTileset(source, path, options)
    local data, reason = EditorFormat.decodeJSON(source, path)
    if not data then return nil, reason end
    data, reason = EditorFormat.migrateTileset(data)
    if not data then return nil, reason end
    local valid, diagnostics = EditorFormat.validateTileset(data, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    local success
    success, reason = decodeOwnerProperties(data, { owner = data, path = path })
    if not success then return nil, reason end
    local tiles = {}
    for _, tile in ipairs(data.tiles or {}) do
        local decoded
        decoded, reason = decodeTile(tile, { tileset = data, path = path })
        if not decoded then return nil, reason end
        table.insert(tiles, decoded)
    end
    data.tiles = tiles
    for _, terrain in ipairs(data.terrains or {}) do
        success, reason = decodeOwnerProperties(terrain, { tileset = data, path = path })
        if not success then return nil, reason end
        for _, variant in ipairs(terrain.terrain_variants or {}) do
            success, reason = decodeOwnerProperties(variant, { tileset = data, path = path })
            if not success then return nil, reason end
        end
    end
    data.tilewidth = data.tile_width
    data.tileheight = data.tile_height
    data.tilecount = data.tile_count
    data.columns = data.tile_columns
    data.margin = data.margin or 0
    data.spacing = data.spacing or 0
    data.objectalignment = data.alignment
    data.tilerendersize = data.render_size
    data.fillmode = data.fill_mode
    data.tileoffset = { x = data.tile_offset_x or 0, y = data.tile_offset_y or 0 }
    data.__tileset_reader = EditorTilesetReader
    return data
end

---@return string? encoded
---@return string? error
function EditorFormat.encodeTileset(data, options)
    options = options or {}
    local result = copySerializable(data)
    clearFields(result, {
        "tilewidth", "tileheight", "tilecount", "columns", "objectalignment", "tilerendersize",
        "fillmode", "tileoffset", "imagewidth", "imageheight", "transparentcolor", "grid",
        "wangsets", "transformations", "tiledversion", "class", "__tileset_reader", "full_path"
    })
    result.version = EditorFormat.TILESET_FORMAT_VERSION
    result.kristal_version = result.kristal_version or tostring(Kristal.Version)
    result.tile_width = data.tile_width or data.tilewidth
    result.tile_height = data.tile_height or data.tileheight
    result.tile_count = data.tile_count or data.tilecount
    result.tile_columns = data.tile_columns or data.columns
    result.tile_rows = data.tile_rows or (result.tile_columns and result.tile_columns > 0
        and math.ceil((result.tile_count or 0) / result.tile_columns) or 0)
    result.alignment = data.alignment or data.objectalignment
    result.render_size = data.render_size or data.tilerendersize
    result.fill_mode = data.fill_mode or data.fillmode
    result.tile_offset_x = data.tile_offset_x or data.tileoffset and data.tileoffset.x
    result.tile_offset_y = data.tile_offset_y or data.tileoffset and data.tileoffset.y
    result.image_width = data.image_width or data.imagewidth
    result.image_height = data.image_height or data.imageheight
    result.transparent_color = data.transparent_color or data.transparentcolor
    if not result.transform_rules and data.transformations then
        result.transform_rules = {
            can_hflip = data.transformations.hflip,
            can_vflip = data.transformations.vflip,
            can_rotate = data.transformations.rotate,
            prefer_untransformed = data.transformations.preferuntransformed
        }
    end
    result.properties = nil
    local reason
    result.properties, reason = encodeOwnerProperties(data, { owner = data })
    if not result.properties then return nil, reason end
    result.tiles = {}
    for _, tile in ipairs(data.tiles or {}) do
        local encoded
        encoded, reason = encodeTile(tile, { tileset = result })
        if not encoded then return nil, reason end
        table.insert(result.tiles, encoded)
    end
    result.terrains = {}
    local terrain_ids = {}
    for _, terrain in ipairs(data.terrains or {}) do
        local encoded = copySerializable(terrain)
        encoded.id = EditorFormat.uniqueSlug(terrain.name or terrain.id, terrain_ids, "terrain")
        encoded.properties = nil
        encoded.properties, reason = encodeOwnerProperties(terrain, { tileset = result })
        if not encoded.properties then return nil, reason end
        encoded.terrain_variants = {}
        local variant_ids, variant_state = {}, { next_id = 1 }
        for _, variant in ipairs(terrain.terrain_variants or {}) do
            local encoded_variant = copySerializable(variant)
            encoded_variant.id = nextNumericId(variant.id, variant_ids, variant_state)
            encoded_variant.properties = nil
            encoded_variant.properties, reason = encodeOwnerProperties(variant, { tileset = result })
            if not encoded_variant.properties then return nil, reason end
            table.insert(encoded.terrain_variants, encoded_variant)
        end
        table.insert(result.terrains, encoded)
    end
    local valid, diagnostics = EditorFormat.validateTileset(result, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    return EditorFormat.encodeJSON(result, "tileset", options)
end

function EditorFormat.decodeWorld(source, path, options)
    local data, reason = EditorFormat.decodeJSON(source, path)
    if not data then return nil, reason end
    data, reason = EditorFormat.migrateWorld(data)
    if not data then return nil, reason end
    local valid, diagnostics = EditorFormat.validateWorld(data, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    local success
    success, reason = decodeOwnerProperties(data, { owner = data, path = path })
    if not success then return nil, reason end
    return data
end

function EditorFormat.encodeWorld(data, options)
    options = options or {}
    local result = copySerializable(data)
    result.version = EditorFormat.WORLD_FORMAT_VERSION
    result.kristal_version = result.kristal_version or tostring(Kristal.Version)
    result.properties = nil
    local reason
    result.properties, reason = encodeOwnerProperties(data, { owner = data })
    if not result.properties then return nil, reason end
    local valid, diagnostics = EditorFormat.validateWorld(result, options)
    if not valid then return nil, table.concat(diagnostics, "; ") end
    return EditorFormat.encodeJSON(result, "world", options)
end

-- SECTION : Editor document input 

---Returns the current map-editor inputs used to build native data.
---@param document EditorMapDocument
---@param map_id? string
---@return table? context
---@return string? error
function EditorFormat.getMapContext(document, map_id)
    map_id = map_id or document.primary_map_id
    if not map_id then return nil, "Map document has no primary map" end
    local entry = document.map_lookup and document.map_lookup[map_id]
    local source_data = Registry.getMapData(map_id)
    return {
        id = map_id,
        document = document,
        source_data = source_data,
        layers = document:getEditableLayers(map_id),
        world = document.world,
        world_entry = entry,
        -- Width/height remain grid counts, matching Map and legacy Tiled data.
        -- These are the reference cell dimensions; tile layers may override them.
        grid_width = source_data and (source_data.grid_width or source_data.tilewidth),
        grid_height = source_data and (source_data.grid_height or source_data.tileheight)
    }
end

---Returns the tileset editor's current working state.
---@param document EditorTilesetDocument
---@return table context
function EditorFormat.getTilesetContext(document)
    return {
        id = document.id,
        document = document,
        data = document.data,
        runtime_tileset = document.tileset
    }
end

---@return table? data
---@return string? error
function EditorFormat.buildMapData(document, map_id, options)
    local context, reason = EditorFormat.getMapContext(document, map_id)
    if not context then return nil, reason end
    local data = TableUtils.copy(context.source_data or {}, true)
    data.id = context.id
    data.width = data.width or 16
    data.height = data.height or 12
    data.grid_width = context.grid_width or data.grid_width or data.tilewidth or 40
    data.grid_height = context.grid_height or data.grid_height or data.tileheight or 40
    data.layers = context.layers
    local reader_class = Registry.getMapReader(context.id)
    if reader_class and reader_class.LEGACY_FORMAT then
        return EditorFormat.convertTiledMap(data, options)
    end
    return data
end

---@return table? data
---@return string? error
function EditorFormat.buildTilesetData(document, options)
    local context = EditorFormat.getTilesetContext(document)
    local data = TableUtils.copy(context.data or {}, true)
    data.id = context.id
    local reader = context.runtime_tileset and context.runtime_tileset.reader
    if document.virtual or reader and reader.LEGACY_FORMAT then
        return EditorFormat.convertTiledTileset(data, options)
    end
    return data
end

function EditorFormat.buildWorldData(world, options)
    local data = TableUtils.copy(world.data or {}, true)
    data.id = world.id or data.id
    data.name = world.name or data.name
    data.properties = world.properties or data.properties or {}
    data.__editor_property_types = world.__editor_property_types or data.__editor_property_types
    data.maps = {}
    for _, entry in ipairs(world.maps or {}) do
        table.insert(data.maps, { map = entry.id, x = entry.x or 0, y = entry.y or 0 })
    end
    return data
end

-- SECTION : Legacy conversion

local function getTiledTilesetId(reference, map_data)
    if reference.name and Registry.getTileset(reference.name) then return reference.name end
    local filename = reference.exportfilename or reference.filename
    if filename then
        local base_dir = map_data.full_path and FileSystemUtils.getDirname(map_data.full_path) or ""
        local success, id = TiledUtils.relativePathToAssetId("scripts/world/tilesets", filename, base_dir)
        if success and Registry.getTileset(id) then return id end
    end
    return reference.name
end

local function getTiledTilesetReferences(map_data)
    local references = {}
    for _, source in ipairs(map_data.tilesets or {}) do
        local id = getTiledTilesetId(source, map_data)
        local tileset = id and Registry.getTileset(id)
        table.insert(references, {
            id = id,
            first_gid = source.firstgid or 1,
            columns = tileset and tileset.columns or source.columns,
            rows = tileset and math.ceil(tileset.tile_count / math.max(1, tileset.columns))
                or source.columns and math.ceil((source.tilecount or 0) / math.max(1, source.columns)),
            count = tileset and tileset.id_count or source.tilecount
        })
    end
    table.sort(references, function(a, b) return a.first_gid < b.first_gid end)
    return references
end

local function resolveTiledGid(gid, references)
    local tile_gid, flip_x, flip_y, rotated = TiledUtils.parseTileGid(gid)
    if tile_gid == 0 then return nil end
    local reference
    for _, candidate in ipairs(references) do
        if candidate.first_gid <= tile_gid then reference = candidate else break end
    end
    if not reference or not reference.id then return nil, "Could not resolve Tiled GID " .. tostring(tile_gid) end
    local tile_id = tile_gid - reference.first_gid
    if reference.count and tile_id >= reference.count then
        return nil, string.format("Tiled GID %d is outside tileset '%s'", tile_gid, reference.id)
    end
    return reference, EditorFormat.packTile(tile_id, flip_x, flip_y, rotated)
end

local function iterateTiledLayerTiles(layer, callback)
    if layer.chunks then
        for _, chunk in ipairs(layer.chunks) do
            local width = chunk.width or EditorFormat.CHUNK_SIZE
            for index, gid in ipairs(chunk.data or {}) do
                callback((chunk.x or 0) + ((index - 1) % width),
                    (chunk.y or 0) + math.floor((index - 1) / width), gid)
            end
        end
        return
    end
    local width = layer.width or 0
    for index, gid in ipairs(layer.data or {}) do
        callback((layer.x or 0) + ((index - 1) % width),
            (layer.y or 0) + math.floor((index - 1) / width), gid)
    end
end

local function convertTiledTileLayer(layer, references)
    local splits, split_order = {}, {}
    local function getSplit(reference)
        local split = splits[reference.id]
        if split then return split end
        split = TableUtils.copy(layer, true)
        clearFields(split, { "data", "encoding", "chunks", "width", "height" })
        split._editor_type_id = Registry.layer_types:getLegacyTiledType(layer).id
        split._editor_kind_id = "tile"
        split.kind = "tile"
        split.x = layer.offsetx or 0
        split.y = layer.offsety or 0
        split.tileset = reference.id
        split.tileset_columns = reference.columns
        split.tileset_rows = reference.rows
        split.chunks = {}
        split._chunks_by_position = {}
        splits[reference.id] = split
        table.insert(split_order, split)
        return split
    end
    local function setTile(split, x, y, packed)
        local size = EditorFormat.CHUNK_SIZE
        local chunk_x = math.floor(x / size) * size
        local chunk_y = math.floor(y / size) * size
        local key = chunk_x .. ":" .. chunk_y
        local chunk = split._chunks_by_position[key]
        if not chunk then
            chunk = { x = chunk_x, y = chunk_y, tile_data = {} }
            for index = 1, size * size do chunk.tile_data[index] = 0 end
            split._chunks_by_position[key] = chunk
            table.insert(split.chunks, chunk)
        end
        chunk.tile_data[(x - chunk_x) + (y - chunk_y) * size + 1] = packed
    end

    local conversion_error
    iterateTiledLayerTiles(layer, function(x, y, gid)
        if conversion_error or gid == 0 then return end
        local reference, packed = resolveTiledGid(gid, references)
        if not reference then conversion_error = packed return end
        setTile(getSplit(reference), x, y, packed)
    end)
    if conversion_error then return nil, conversion_error end
    if #split_order == 0 and references[1] then getSplit(references[1]) end
    if #split_order == 0 then return nil, "Tile layer has no resolvable tileset" end

    for index, split in ipairs(split_order) do
        split._chunks_by_position = nil
        table.sort(split.chunks, function(a, b) return a.y == b.y and a.x < b.x or a.y < b.y end)
        if #split_order > 1 then
            split.name = index == 1 and layer.name or string.format("%s [%s]", layer.name or "Tiles", split.tileset)
            split.id = index == 1 and layer.id or tostring(layer.id or "layer") .. ":" .. split.tileset
            split.properties = TableUtils.copy(layer.properties or {}, true)
            if index < #split_order then split.properties.thin = true end
        end
    end
    return split_order
end

---@return table? data
---@return string? error
function EditorFormat.convertTiledMap(data, options)
    local converted = TableUtils.copy(data, true)
    converted.version = EditorFormat.TILED_MAP_CONVERSION_VERSION
    converted.kristal_version = tostring(Kristal.Version)
    converted.grid_width = data.tilewidth or 40
    converted.grid_height = data.tileheight or 40
    converted.background_color = data.backgroundcolor
    converted.name = converted.name or converted.properties and converted.properties.name
    if converted.properties then
        converted.properties.name = nil
        converted.properties.keep_music = converted.properties.keep_music or converted.properties.keepmusic
        converted.properties.keepmusic = nil
    end
    converted.tilewidth, converted.tileheight, converted.backgroundcolor = nil, nil, nil
    local references = getTiledTilesetReferences(data)
    local function convertLayers(layers)
        local result = {}
        for _, layer in ipairs(layers or {}) do
            if layer.type == "group" then
                layer._editor_type_id = "folder"
                layer._editor_kind_id = "group"
                layer.kind = "group"
                layer.x = layer.offsetx or 0
                layer.y = layer.offsety or 0
                layer.layers = convertLayers(layer.layers)
                table.insert(result, layer)
            elseif layer.type == "tilelayer" then
                local split_layers, reason = convertTiledTileLayer(layer, references)
                if not split_layers then return nil, reason end
                for _, split in ipairs(split_layers) do table.insert(result, split) end
            else
                local layer_type = Registry.layer_types:getLegacyTiledType(layer)
                layer._editor_type_id = layer_type.id
                layer._editor_kind_id = layer_type.kind
                layer.kind = layer_type.kind
                layer.x = layer.offsetx or 0
                layer.y = layer.offsety or 0
                table.insert(result, layer)
            end
        end
        return result
    end
    local converted_layers, reason = convertLayers(converted.layers)
    if not converted_layers then return nil, reason end
    converted.layers = converted_layers
    return EditorFormat.migrateMap(converted)
end

---@return table? data
---@return string? error
function EditorFormat.convertTiledTileset(data, options)
    local converted = TableUtils.copy(data, true)
    converted.version = EditorFormat.TILED_TILESET_CONVERSION_VERSION
    converted.kristal_version = tostring(Kristal.Version)
    converted.tile_width = data.tilewidth
    converted.tile_height = data.tileheight
    converted.tile_count = data.tilecount
    converted.tile_columns = data.columns
    converted.tile_rows = data.columns and data.columns > 0 and math.ceil((data.tilecount or 0) / data.columns) or 0
    converted.alignment = data.objectalignment
    converted.render_size = data.tilerendersize
    converted.fill_mode = data.fillmode
    converted.tile_offset_x = data.tileoffset and data.tileoffset.x
    converted.tile_offset_y = data.tileoffset and data.tileoffset.y
    if data.transformations then
        converted.transform_rules = {
            can_hflip = data.transformations.hflip,
            can_vflip = data.transformations.vflip,
            can_rotate = data.transformations.rotate,
            prefer_untransformed = data.transformations.preferuntransformed
        }
    end
    if not data.image and (data.tilecount or 0) > 0 then
        local images = {}
        for _, tile in ipairs(data.tiles or {}) do
            if tile.image then images[tile.id + 1] = tile.image end
        end
        if next(images) then
            for index = 1, data.tilecount do
                if images[index] == nil then
                    return nil, "Multi-image legacy tilesets require one image for every tile id"
                end
            end
            converted.image = images
        end
    end
    converted.terrains = {}
    for terrain_index, wangset in ipairs(data.wangsets or {}) do
        local terrain = {
            id = wangset.id or terrain_index,
            name = wangset.name,
            tile_icon = wangset.tile and wangset.tile >= 0 and wangset.tile or nil,
            type = wangset.type or "mixed",
            properties = TableUtils.copy(wangset.properties or {}, true),
            __editor_property_types = TableUtils.copy(wangset.__editor_property_types or {}, true),
            terrain_variants = {},
            terrain_tiles = {}
        }
        for variant_index, color in ipairs(wangset.wangcolors or wangset.colors or {}) do
            table.insert(terrain.terrain_variants, {
                id = variant_index,
                name = color.name,
                color = color.color,
                tile_icon = color.tile and color.tile >= 0 and color.tile or nil,
                probability = color.probability,
                properties = TableUtils.copy(color.properties or {}, true),
                __editor_property_types = TableUtils.copy(color.__editor_property_types or {}, true)
            })
        end
        for _, wangtile in ipairs(wangset.wangtiles or {}) do
            table.insert(terrain.terrain_tiles, {
                tile_id = wangtile.tileid,
                edges = TableUtils.copy(wangtile.wangid or {}, true)
            })
        end
        table.insert(converted.terrains, terrain)
    end
    return EditorFormat.migrateTileset(converted)
end

local function checkVersion(data, label, current_version)
    local version = tonumber(data.version)
    if not version then return nil, label .. " is missing a numeric format version" end
    if version > current_version then
        return nil, string.format("%s format version %s is newer than supported version %s",
            label, version, current_version)
    end
    if version < current_version then
        return nil, string.format("No migration is registered for %s format version %s", label:lower(), version)
    end
    return data
end

function EditorFormat.migrateMap(data)
    return checkVersion(data, "Map", EditorFormat.MAP_FORMAT_VERSION)
end

function EditorFormat.migrateTileset(data)
    return checkVersion(data, "Tileset", EditorFormat.TILESET_FORMAT_VERSION)
end

function EditorFormat.migrateWorld(data)
    return checkVersion(data, "World", EditorFormat.WORLD_FORMAT_VERSION)
end

-- SECTION : Validation

---@return boolean? valid
---@return table|string? diagnostics
function EditorFormat.validateMap(data, options)
    local diagnostics = {}
    if type(data.width) ~= "number" or data.width < 0 then table.insert(diagnostics, "Map width must be non-negative") end
    if type(data.height) ~= "number" or data.height < 0 then table.insert(diagnostics, "Map height must be non-negative") end
    if type(data.grid_width) ~= "number" or data.grid_width <= 0 then table.insert(diagnostics, "Map grid_width must be positive") end
    if type(data.grid_height) ~= "number" or data.grid_height <= 0 then table.insert(diagnostics, "Map grid_height must be positive") end
    if type(data.layers) ~= "table" then table.insert(diagnostics, "Map layers must be an array") end
    if data.properties ~= nil and type(data.properties) ~= "table" then table.insert(diagnostics, "Map properties must be an array") end
    local layer_ids, object_ids = {}, {}
    local function validateObjects(objects, path)
        for index, object in ipairs(objects or {}) do
            local object_path = string.format("%s.objects[%d]", path, index)
            if type(object.id) ~= "number" or object.id < 1 or object.id % 1 ~= 0 then
                table.insert(diagnostics, object_path .. ".id must be a positive integer")
            elseif object_ids[object.id] then
                table.insert(diagnostics, object_path .. ".id duplicates object " .. tostring(object.id))
            else
                object_ids[object.id] = true
            end
        end
    end
    local function validateLayers(layers, path)
        for index, layer in ipairs(layers or {}) do
            local layer_path = string.format("%s[%d]", path, index)
            if type(layer.id) ~= "string" or layer.id == "" then
                table.insert(diagnostics, layer_path .. ".id must be a non-empty string")
            elseif layer_ids[layer.id] then
                table.insert(diagnostics, layer_path .. ".id duplicates layer '" .. layer.id .. "'")
            else
                layer_ids[layer.id] = true
            end
            if layer.kind == "group" then
                validateLayers(layer.layers, layer_path .. ".layers")
            elseif layer.kind == "object" then
                validateObjects(layer.objects, layer_path)
            end
        end
    end
    if type(data.layers) == "table" then validateLayers(data.layers, "layers") end
    return #diagnostics == 0, diagnostics
end

---@return boolean? valid
---@return table|string? diagnostics
function EditorFormat.validateTileset(data, options)
    local diagnostics = {}
    if type(data.tile_width) ~= "number" or data.tile_width <= 0 then table.insert(diagnostics, "Tileset tile_width must be positive") end
    if type(data.tile_height) ~= "number" or data.tile_height <= 0 then table.insert(diagnostics, "Tileset tile_height must be positive") end
    if type(data.tile_count) ~= "number" or data.tile_count < 0 then table.insert(diagnostics, "Tileset tile_count must be non-negative") end
    if data.image ~= nil and type(data.image) ~= "string" and type(data.image) ~= "table" then
        table.insert(diagnostics, "Tileset image must be a path or an array of paths")
    end
    if data.tiles ~= nil and type(data.tiles) ~= "table" then table.insert(diagnostics, "Tileset tiles must be an array") end
    for tile_index, tile in ipairs(data.tiles or {}) do
        local object_ids = {}
        for object_index, object in ipairs(tile.collision or {}) do
            local path = string.format("tiles[%d].collision[%d]", tile_index, object_index)
            if type(object.id) ~= "number" or object.id < 1 or object.id % 1 ~= 0 then
                table.insert(diagnostics, path .. ".id must be a positive integer")
            elseif object_ids[object.id] then
                table.insert(diagnostics, path .. ".id duplicates collision object " .. tostring(object.id))
            else
                object_ids[object.id] = true
            end
        end
    end
    local terrain_ids = {}
    for terrain_index, terrain in ipairs(data.terrains or {}) do
        local path = string.format("terrains[%d]", terrain_index)
        if type(terrain.id) ~= "string" or terrain.id == "" then
            table.insert(diagnostics, path .. ".id must be a non-empty string")
        elseif terrain_ids[terrain.id] then
            table.insert(diagnostics, path .. ".id duplicates terrain '" .. terrain.id .. "'")
        else
            terrain_ids[terrain.id] = true
        end
        local variant_ids = {}
        for variant_index, variant in ipairs(terrain.terrain_variants or {}) do
            local variant_path = string.format("%s.terrain_variants[%d]", path, variant_index)
            if type(variant.id) ~= "number" or variant.id < 1 or variant.id % 1 ~= 0 then
                table.insert(diagnostics, variant_path .. ".id must be a positive integer")
            elseif variant_ids[variant.id] then
                table.insert(diagnostics, variant_path .. ".id duplicates variant " .. tostring(variant.id))
            else
                variant_ids[variant.id] = true
            end
        end
    end
    return #diagnostics == 0, diagnostics
end

function EditorFormat.validateWorld(data, options)
    local diagnostics = {}
    if type(data.maps) ~= "table" then
        table.insert(diagnostics, "World maps must be an array")
    else
        for index, entry in ipairs(data.maps) do
            if type(entry) ~= "table" or type(entry.map) ~= "string" then
                table.insert(diagnostics, string.format("World map entry %d requires a map id", index))
            elseif type(entry.x) ~= "number" or type(entry.y) ~= "number" then
                table.insert(diagnostics, string.format("World map entry %d requires numeric x/y", index))
            end
        end
    end
    return #diagnostics == 0, diagnostics
end

-- SECTION : Saving

---@return boolean success
---@return string? error
function EditorFormat.saveMapData(data, path, options)
    local encoded, reason = EditorFormat.encodeMap(data, options)
    if not encoded then return false, reason end
    return EditorFormat.writeFile(path, encoded, options)
end

---@return boolean success
---@return string? error
function EditorFormat.saveTilesetData(data, path, options)
    local encoded, reason = EditorFormat.encodeTileset(data, options)
    if not encoded then return false, reason end
    return EditorFormat.writeFile(path, encoded, options)
end

function EditorFormat.saveWorldData(data, path, options)
    local encoded, reason = EditorFormat.encodeWorld(data, options)
    if not encoded then return false, reason end
    return EditorFormat.writeFile(path, encoded, options)
end

function EditorFormat.writeFile(path, encoded, options)
    if type(path) ~= "string" or path == "" then return false, "A save path is required" end
    if options and options.writer then return options.writer(path, encoded, options) end
    local directory = FileSystemUtils.getDirname(path)
    if directory ~= "" then love.filesystem.createDirectory(directory) end
    local written, reason = love.filesystem.write(path, encoded)
    if not written then return false, reason or ("Could not write '" .. path .. "'") end
    return true
end

local function normalizeProjectPath(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("/+", "/")
    if path == "" or path:sub(1, 1) == "/" or path:match("^%a:/") then
        return nil, "Project save paths must be relative"
    end
    for segment in path:gmatch("[^/]+") do
        if segment == "." or segment == ".." then return nil, "Project save path escapes the project" end
    end
    return path
end

local function quoteDirectory(path)
    if love.system.getOS() == "Windows" then
        if path:find('[%%!\"]') then return nil end
        return '"' .. path:gsub("/", "\\") .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function createRealDirectory(path)
    local quoted = quoteDirectory(path)
    if not quoted then return false, "Project directory contains unsupported shell characters" end
    local command = love.system.getOS() == "Windows"
        and ("mkdir " .. quoted .. " >NUL 2>NUL")
        or ("mkdir -p " .. quoted .. " >/dev/null 2>&1")
    os.execute(command)
    local probe = io.open(path .. "/.kristal_editor_write_probe", "wb")
    if not probe then return false, "Could not create project directory '" .. path .. "'" end
    probe:close()
    os.remove(path .. "/.kristal_editor_write_probe")
    return true
end

function EditorFormat.getProjectRealPath(path)
    local normalized, reason = normalizeProjectPath(path)
    if not normalized then return nil, reason end
    if not Mod or not Mod.info or not Mod.info.path then return nil, "No project is loaded" end
    local project_path = Mod.info.path:gsub("\\", "/"):gsub("/+$", "")
    if normalized ~= project_path and not StringUtils.startsWith(normalized, project_path .. "/") then
        return nil, "Save path is outside the active project"
    end
    local real_root = love.filesystem.getRealDirectory(project_path)
    if not real_root then return nil, "Could not locate the active project on disk" end
    return (real_root:gsub("\\", "/"):gsub("/+$", "")) .. "/" .. normalized
end

function EditorFormat.writeProjectFile(path, encoded)
    local real_path, reason = EditorFormat.getProjectRealPath(path)
    if not real_path then return false, reason end
    local directory = FileSystemUtils.getDirname(real_path)
    local created
    created, reason = createRealDirectory(directory)
    if not created then return false, reason end

    local temporary = real_path .. ".kristal-tmp"
    local backup = real_path .. ".kristal-backup"
    local file, open_error = io.open(temporary, "wb")
    if not file then return false, open_error or ("Could not open '" .. temporary .. "'") end
    local written, write_error = file:write(encoded)
    local closed, close_error = file:close()
    if not written or not closed then
        os.remove(temporary)
        return false, write_error or close_error or "Could not finish writing project file"
    end

    os.remove(backup)
    local existing = io.open(real_path, "rb")
    if existing then
        existing:close()
        local moved, move_error = os.rename(real_path, backup)
        if not moved then os.remove(temporary) return false, move_error end
    end
    local replaced, replace_error = os.rename(temporary, real_path)
    if not replaced then
        os.rename(backup, real_path)
        os.remove(temporary)
        return false, replace_error or "Could not replace project file"
    end
    os.remove(backup)
    return true
end

function EditorFormat.saveMapDocument(document, path, options, map_id)
    local data, reason = EditorFormat.buildMapData(document, map_id, options)
    if not data then return false, reason end
    return EditorFormat.saveMapData(data, path, options)
end

function EditorFormat.saveTilesetDocument(document, path, options)
    local data, reason = EditorFormat.buildTilesetData(document, options)
    if not data then return false, reason end
    return EditorFormat.saveTilesetData(data, path, options)
end

function EditorFormat.saveWorld(world, path, options)
    local data = EditorFormat.buildWorldData(world, options)
    return EditorFormat.saveWorldData(data, path, options)
end

return EditorFormat
