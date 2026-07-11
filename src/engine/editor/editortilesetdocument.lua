---@class EditorTilesetDocument : Class
---@overload fun(editor: table, id: string, tileset?: Tileset, data?: table): EditorTilesetDocument
local EditorTilesetDocument = Class()

local function findTileData(data, id)
    for _, tile in ipairs(data.tiles or {}) do if tile.id == id then return tile end end
    local tile = { id = id, properties = {}, __editor_property_types = {} }
    data.tiles = data.tiles or {}
    table.insert(data.tiles, tile)
    return tile
end

function EditorTilesetDocument:init(editor, id, tileset, data)
    self.editor = editor
    self.id = id
    self.tileset = tileset
    self.data = data or tileset and tileset.data or {
        name = id, tilewidth = 40, tileheight = 40, tilecount = 0, columns = 1,
        properties = {}, tiles = {}, wangsets = {}
    }
    self.data.properties = self.data.properties or {}
    self.data.__editor_property_types = self.data.__editor_property_types or {}
    self.property_set = EditorPropertySet(self.data.properties, self.data.__editor_property_types)
    self.virtual = tileset == nil
    self.tile_documents = {}
    self.history_revision = 0
    self.saved_history_revision = 0
end

function EditorTilesetDocument:captureHistoryState()
    return { data = TableUtils.copy(self.data, true) }
end

function EditorTilesetDocument:restoreHistoryState(state)
    if not state then return false end
    self.data = TableUtils.copy(state.data, true)
    self.data.properties = self.data.properties or {}
    self.data.__editor_property_types = self.data.__editor_property_types or {}
    self.property_set = EditorPropertySet(self.data.properties, self.data.__editor_property_types)
    self.tile_documents = {}
    if self.tileset then self.tileset.data = self.data end
    return true
end

function EditorTilesetDocument:isDirty()
    return (self.history_revision or 0) ~= (self.saved_history_revision or 0)
end

function EditorTilesetDocument:getName()
    return self.data.name or self.id
end

function EditorTilesetDocument:getTileCount()
    return self.tileset and self.tileset.id_count or self.data.tilecount or 0
end

function EditorTilesetDocument:getColumns()
    return math.max(1, self.tileset and self.tileset.columns or self.data.columns or 1)
end

function EditorTilesetDocument:getPaletteTileSize()
    local grid = self.data.grid or {}
    local width = tonumber(grid.width)
        or (self.tileset and self.tileset.tile_width)
        or tonumber(self.data.tilewidth)
        or 40
    local height = tonumber(grid.height)
        or (self.tileset and self.tileset.tile_height)
        or tonumber(self.data.tileheight)
        or 40
    return math.max(1, width), math.max(1, height)
end

function EditorTilesetDocument:getTile(id)
    if id == nil or id < 0 or id >= self:getTileCount() then return nil end
    if self.tile_documents[id] then return self.tile_documents[id] end
    local source = findTileData(self.data, id)
    source.properties = source.properties or {}
    source.__editor_property_types = source.__editor_property_types or {}
    local tile = {
        id = id,
        source = source,
        property_set = EditorPropertySet(source.properties, source.__editor_property_types),
        document = self
    }
    self.tile_documents[id] = tile
    return tile
end

function EditorTilesetDocument:getTileProbability(id)
    local tile = self:getTile(id)
    return tile and tonumber(tile.source.probability) or 1
end

function EditorTilesetDocument:getCollisionShapes(tile)
    if not tile then return {} end
    tile.source.objectgroup = tile.source.objectgroup or { objects = {} }
    tile.source.objectgroup.objects = tile.source.objectgroup.objects or {}
    return tile.source.objectgroup.objects
end

function EditorTilesetDocument:addCollisionShape(tile)
    local shapes = self:getCollisionShapes(tile)
    local width = self.data.tilewidth or 40
    local height = self.data.tileheight or 40
    local shape = { x = 0, y = 0, width = width, height = height, shape = "rectangle", properties = {} }
    table.insert(shapes, shape)
    return shape
end

function EditorTilesetDocument:getAnimationFrames(tile)
    if not tile then return {} end
    tile.source.animation = tile.source.animation or {}
    return tile.source.animation
end

function EditorTilesetDocument:addAnimationFrame(tile, tile_id)
    local frame = { tileid = tile_id or tile.id, duration = 100 }
    table.insert(self:getAnimationFrames(tile), frame)
    return frame
end

function EditorTilesetDocument:getTerrainSets()
    self.data.wangsets = self.data.wangsets or {}
    return self.data.wangsets
end

function EditorTilesetDocument:addTerrainSet()
    local set = { name = "New Terrain Set", type = "mixed", properties = {}, wangcolors = {}, wangtiles = {} }
    table.insert(self:getTerrainSets(), set)
    return set
end

function EditorTilesetDocument:getPropertiesTarget()
    local data = self.data
    local function numberField(label, key, readonly)
        return { label = label, readonly = readonly, get = function() return data[key] or 0 end,
            set = function(value)
                local number = tonumber(value)
                if not number or readonly then return false end
                data[key] = number
                return true
            end }
    end
    local function offsetField(label, key)
        return { label = label, get = function() return data.tileoffset and data.tileoffset[key] or 0 end,
            set = function(value)
                value = tonumber(value)
                if not value then return false end
                data.tileoffset = data.tileoffset or {}
                data.tileoffset[key] = value
                return true
            end }
    end
    local function gridField(label, key, fallback)
        return { label = label, get = function() return data.grid and data.grid[key] or fallback end,
            set = function(value)
                if key ~= "orientation" then value = tonumber(value) if not value then return false end end
                data.grid = data.grid or {}
                data.grid[key] = value
                return true
            end }
    end
    return {
        title = "Tileset: " .. self:getName(),
        history_owner = self,
        property_set = self.property_set,
        properties = data.properties,
        property_types = data.__editor_property_types,
        fields = {
            { label = "Name", get = function() return data.name or self.id end,
                set = function(value) data.name = value return true end },
            { label = "Type", readonly = true,
                get = function() return data.image and "Tileset Image" or "Collection of Images" end,
                set = function() return false end },
            { label = "Image", get = function() return data.image or "" end,
                set = function(value) data.image = value ~= "" and value or nil return true end },
            numberField("Tile Width", "tilewidth"), numberField("Tile Height", "tileheight"),
            numberField("Tile Count", "tilecount"),
            numberField("Margin", "margin"), numberField("Spacing", "spacing"),
            numberField("Columns", "columns"),
            { label = "Object Alignment", get = function() return data.objectalignment or "unspecified" end,
                set = function(value) data.objectalignment = value return true end },
            offsetField("Drawing Offset X", "x"), offsetField("Drawing Offset Y", "y"),
            { label = "Background Color", get = function() return data.backgroundcolor or "" end,
                set = function(value) data.backgroundcolor = value return true end },
            gridField("Orientation", "orientation", "orthogonal"),
            gridField("Grid Width", "width", data.tilewidth or 40),
            gridField("Grid Height", "height", data.tileheight or 40),
            { label = "Tile Render Size", get = function() return data.tilerendersize or "tile" end,
                set = function(value) data.tilerendersize = value return true end },
            { label = "Fill Mode", get = function() return data.fillmode or "stretch" end,
                set = function(value) data.fillmode = value return true end }
        }
    }
end

function EditorTilesetDocument:getTilePropertiesTarget(tile)
    if not tile then return nil end
    local source = tile.source
    return {
        title = string.format("Tile %d", tile.id),
        history_owner = self,
        property_set = tile.property_set,
        properties = source.properties,
        property_types = source.__editor_property_types,
        fields = {
            { label = "ID", readonly = true, get = function() return tile.id end, set = function() return false end },
            { label = "Class", get = function() return source.class or source.type or "" end,
                set = function(value) source.class = value return true end },
            { label = "Probability", get = function() return source.probability or 1 end,
                set = function(value) local number = tonumber(value) if not number then return false end source.probability = number return true end },
            { label = "Width", readonly = true,
                get = function() return source.width or self.data.tilewidth or 0 end, set = function() return false end },
            { label = "Height", readonly = true,
                get = function() return source.height or self.data.tileheight or 0 end, set = function() return false end },
            { label = "Terrain", get = function()
                    return type(source.terrain) == "table" and table.concat(source.terrain, ",") or source.terrain or ""
                end,
                set = function(value) source.terrain = value return true end },
            { label = "Image", readonly = self.data.image ~= nil,
                get = function() return source.image or (self.data.image and "Tileset image" or "") end,
                set = function(value) if self.data.image ~= nil then return false end source.image = value return true end }
        }
    }
end

return EditorTilesetDocument
