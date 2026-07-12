--[[
    Kristal editor map/tileset format design surface

    INSERT FORMAT LAYOUT INFO HERE
]]

local EditorFormat = {}

EditorFormat.DESIGNED = false
EditorFormat.MAP_FORMAT_VERSION = 1
EditorFormat.TILESET_FORMAT_VERSION = 1
EditorFormat.WORLD_FORMAT_VERSION = 1

-- Map and Tileset methods callback format specific helpers through these tables.
EditorFormat.mapOperations = {}
EditorFormat.tilesetOperations = {}

-- These lists document the complete operation surface currently requested by Map/Tileset.
EditorFormat.MAP_OPERATION_CONTRACT = {
    "loadMapData", "getLayerClassOrName", "isLayerType", "loadLayer",
    "loadTiles", "createTileLayer", "decodeTileData", "encodeTileData",
    "loadImage", "loadTextureFromImagePath", "loadCollision",
    "loadEnemyCollision", "loadBlockCollision", "loadBattleAreas",
    "loadHitboxes", "loadShapes", "loadMarkers", "loadPaths",
    "shouldLoadObject", "loadObjects", "legacyLoadObject", "loadObject",
    "loadController", "populateTilesets", "loadTilesetFromTilesetPath",
    "getTileset", "getTileObjectRect", "createTileObject"
}

EditorFormat.TILESET_OPERATION_CONTRACT = {
    "loadTextureFromImagePath"
}

EditorFormat.ORDERING = {
    map = {
        "version",
        "kristal_version",
        "id",
        "name",
        "width",
        "height",
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
        "can_vflip",
        "can_hflip",
        "can_rotate",
        "prefer_untransformed",
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

local function pending(piece)
    return nil, "not yet implemented " .. piece
end

local function runtimePending(piece)
    error("not yet implemented " .. piece, 3)
end

-- SECTION : Discovery

---@param registry Registry
function EditorFormat.registerMaps(registry)
    return true
end

---@param registry Registry
function EditorFormat.registerTilesets(registry)
    return true
end

-- SECTION : Encode/Decode

---@return table? data
---@return string? error
function EditorFormat.decodeMap(source, path, options)
    return pending("decodeMap")
end

---@return string? encoded
---@return string? error
function EditorFormat.encodeMap(data, options)
    return pending("encodeMap")
end

---@return table? data
---@return string? error
function EditorFormat.decodeTileset(source, path, options)
    return pending("decodeTileset")
end

---@return string? encoded
---@return string? error
function EditorFormat.encodeTileset(data, options)
    return pending("encodeTileset")
end

-- SECTION : Editor document input 

---Returns all current map-editor inputs without deciding their serialized
---names or nesting.
---@param document EditorMapDocument
---@param map_id? string
---@return table? context
---@return string? error
function EditorFormat.getMapContext(document, map_id)
    map_id = map_id or document.primary_map_id
    if not map_id then return nil, "Map document has no primary map" end
    local entry = document.map_lookup and document.map_lookup[map_id]
    return {
        id = map_id,
        document = document,
        source_data = Registry.getMapData(map_id),
        layers = document:getEditableLayers(map_id),
        world = document.world,
        world_entry = entry
    }
end

---Returns all current tileset-editor inputs without deciding their serialized
---names or nesting. The data table is the editor's current working state.
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
    return pending("buildMapData")
end

---@return table? data
---@return string? error
function EditorFormat.buildTilesetData(document, options)
    return pending("buildTilesetData")
end

-- SECTION : Legacy conversion

---@return table? data
---@return string? error
function EditorFormat.convertTiledMap(data, options)
    return pending("convertTiledMap")
end

---@return table? data
---@return string? error
function EditorFormat.convertTiledTileset(data, options)
    return pending("convertTiledTileset")
end

--- Method for migrating older versioned Editor format maps to the current version.
---@return table? data
---@return string? error
function EditorFormat.migrateMap(data, reader)
    return pending("migrateMap")
end

--- Method for migrating older versioned Editor format tilesets to the current version.
---@return table? data
---@return string? error
function EditorFormat.migrateTileset(data, reader)
    return pending("migrateMap")
end

-- SECTION : Validation

---@return boolean? valid
---@return table|string? diagnostics
function EditorFormat.validateMap(data, options)
    return pending("validateMap")
end

---@return boolean? valid
---@return table|string? diagnostics
function EditorFormat.validateTileset(data, options)
    return pending("validateTileset")
end

-- SECTION : Loading

---Populate scalar/runtime map state before Map:load().
function EditorFormat.initializeMap(map, data, reader)
    return runtimePending("initializeMap")
end

---Create layers, events, collision, markers, and other runtime map contents.
function EditorFormat.readMap(map, data, reader)
    return runtimePending("readMap")
end

---Populate textures, tile metadata, animation, collision, and runtime tileset state.
function EditorFormat.initializeTileset(tileset, data, path, base_dir, reader)
    return runtimePending("initializeTileset")
end

-- SECTION : Saving

---@return boolean success
---@return string? error
function EditorFormat.saveMapData(data, path, options)
    local encoded, reason = EditorFormat.encodeMap(data, options)
    if not encoded then return false, reason end
    return encoded, reason
end

---@return boolean success
---@return string? error
function EditorFormat.saveTilesetData(data, path, options)
    local encoded, reason = EditorFormat.encodeTileset(data, options)
    if not encoded then return false, reason end
    return false, "EditorFormat.saveTilesetData still needs the designed path and write policy"
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

return EditorFormat
