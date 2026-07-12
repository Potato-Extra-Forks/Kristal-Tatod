---@class TiledMapReader : MapReader
---@overload fun(map: Map): TiledMapReader
local TiledMapReader, super = Class(MapReader)

TiledMapReader.FORMAT = "tiled"
TiledMapReader.LEGACY_FORMAT = true

local operations = {}
TiledMapReader.operations = operations

function TiledMapReader:initialize(data)
    local map = self.map

    if data.full_path then
        local split_map_path = StringUtils.split(data.full_path, "/")
        map.full_map_path = table.concat(split_map_path, "/", 1, #split_map_path - 1)
    end

    map.tile_width = data.tilewidth or 40
    map.tile_height = data.tileheight or 40
    map.width = data.width or 16
    map.height = data.height or 12

    map.name = data.properties and data.properties["name"]
    map.music = data.properties and data.properties["music"]
    map.keep_music = data.properties and data.properties["keepmusic"]
    map.light = data.properties and data.properties["light"] or false
    map.border = data.properties and data.properties["border"]

    if data.backgroundcolor then
        local bgc = data.backgroundcolor
        map.bg_color = { bgc[1] / 255, bgc[2] / 255, bgc[3] / 255, (bgc[4] or 255) / 255 }
    end

    map:populateTilesets(data.tilesets or {})
end

function TiledMapReader:read(data)
    return self:call("loadMapData", data)
end

--- Always saves as the editor format, cause i don't really wanna write a legacy saver...
function TiledMapReader:save(path, options)
    local data, reason = EditorMapReader.convertLegacyData(self.map.data, options)
    if not data then return false, reason end
    return EditorMapReader.saveData(data, path, options)
end

function operations.loadMapData(self, data)
    local object_depths = {}
    local tile_depths = {}
    local indexed_layers = {}
    local has_battle_border = false

    local layers = {}

    local function loadLayer(layer)
        if layer.type ~= "group" then
            table.insert(layers, layer)
        else
            for i, sublayer in ipairs(layer.layers) do
                local sublayer_copy = TableUtils.copy(sublayer)
                sublayer_copy.properties = TableUtils.mergeMany(layer.properties, sublayer_copy.properties)
                if i == #layer.layers then
                    sublayer_copy.properties.thin = sublayer.properties.thin
                end
                sublayer_copy.offsetx = (sublayer.offsetx or 0) + (layer.offsetx or 0)
                sublayer_copy.offsety = (sublayer.offsety or 0) + (layer.offsety or 0)
                sublayer_copy.parallaxx = (sublayer.parallaxx or 1) * (layer.parallaxx or 1)
                sublayer_copy.parallaxy = (sublayer.parallaxy or 1) * (layer.parallaxy or 1)
                loadLayer(sublayer_copy)
            end
        end
    end

    for _, layer in ipairs(data.layers or {}) do
        loadLayer(TableUtils.copy(layer))
    end

    for i, layer in ipairs(layers) do
        self.layers[layer.name] = self.next_layer
        indexed_layers[i] = self.next_layer
        if not (layer.properties and layer.properties.thin) then
            self.next_layer = self.next_layer + self.depth_per_layer
        end
    end

    self.object_layer = nil
    for i, layer in ipairs(layers) do
        local depth = indexed_layers[i]
        if not has_battle_border and self:isLayerType(layer, "battleborder") then
            self.battle_fader_layer = depth - (self.depth_per_layer / 2)
            has_battle_border = true
        end
        if layer.type == "objectgroup" and self:isLayerType(layer, "objects") then
            table.insert(object_depths, depth)
            if layer.properties["spawn"] then
                self.object_layer = depth
            end
        end
        if layer.type == "tilelayer" and not self:isLayerType(layer, "battleborder") then
            table.insert(tile_depths, depth)
        end
        if not Kristal.callEvent(KRISTAL_EVENT.loadLayer, self, layer, depth) then
            self:loadLayer(layer, depth)
        end
    end

    -- old behavior, ideally should not be used
    if not self.object_layer then
        self.object_layer = 1
        local priority_object_layer = nil
        local has_markers_layer = false
        for i, layer in ipairs(layers) do
            local depth = indexed_layers[i]
            if layer.type == "objectgroup" then
                if self:isLayerType(layer, "markers") then
                    has_markers_layer = true
                    priority_object_layer = nil
                    if #object_depths == 0 then
                        -- If there are no object layers, set the object depth to the marker layer's depth
                        self.object_layer = depth
                    else
                        -- Otherwise, set the object depth to the closest object layer's depth
                        local closest
                        for _, obj_depth in ipairs(object_depths) do
                            if not closest then
                                closest = obj_depth
                            elseif math.abs(depth - obj_depth) <= math.abs(depth - closest) then
                                closest = obj_depth
                            else
                                break
                            end
                        end
                        self.object_layer = closest or depth
                    end
                elseif self:getLayerClassOrName(layer):lower() == "objects_party" then
                    priority_object_layer = depth
                    break -- always use 'objects_party' if available
                elseif not has_markers_layer then
                    -- If there is no markers layer, set the object layer to the highest object layer
                    if self:isLayerType(layer, "objects") then
                        priority_object_layer = depth
                    end
                    self.object_layer = depth
                end
            end
        end
        -- If no marker layers, prioritize object layers without a custom name
        if priority_object_layer then
            self.object_layer = priority_object_layer
        end
    end

    -- Set the tile layer depth to the closest tile layer below the object layer
    self.tile_layer = 0
    for _, depth in ipairs(tile_depths) do
        if depth >= self.object_layer then break end

        self.tile_layer = depth
    end

    -- If no battleborder layer, set the battle fader layer depth to be below the object layer
    if not has_battle_border then
        self.battle_fader_layer = self.object_layer - (self.depth_per_layer / 2)
    end
end

function operations.getLayerClassOrName(self, layer)
    if layer.class ~= nil and layer.class ~= "" then
        return layer.class
    end

    return layer.name
end

function operations.isLayerType(self, layer, type)
    if layer.class ~= nil and layer.class ~= "" then
        -- If there's a defined class, check that (strict)
        return layer.class == type
    end

    -- If there isn't a class, use the name (loose)
    return StringUtils.startsWith(layer.name:lower(), type)
end

function operations.loadLayer(self, layer, depth)
    if layer.type == "tilelayer" then
        self:loadTiles(layer, depth)
    elseif layer.type == "imagelayer" then
        self:loadImage(layer, depth)
    elseif layer.type == "objectgroup" then
        if self:isLayerType(layer, "objects") then
            self:loadObjects(layer, depth, "events")
        elseif self:isLayerType(layer, "controllers") then
            self:loadObjects(layer, depth, "controllers")
        elseif self:isLayerType(layer, "markers") then
            self:loadMarkers(layer)
        elseif self:isLayerType(layer, "collision") then
            self:loadCollision(layer)
        elseif self:isLayerType(layer, "enemycollision") then
            self:loadEnemyCollision(layer)
        elseif self:isLayerType(layer, "blockcollision") then
            self:loadBlockCollision(layer)
        elseif self:isLayerType(layer, "paths") then
            self:loadPaths(layer)
        elseif self:isLayerType(layer, "battleareas") then
            self:loadBattleAreas(layer)
        end
        self:loadShapes(layer)
    else
        Kristal.Console:warn(string.format("Unhandled or unknown Tiled layer type \"%s\", ignoring", layer.type))
    end
end

function operations.loadTiles(self, layer, depth)
    local tilelayer = self:createTileLayer(layer)
    tilelayer:setPosition(layer.offsetx or 0, layer.offsety or 0)
    tilelayer.layer = depth
    self.world:addChild(tilelayer)
    table.insert(self.tile_layers, tilelayer)
    if StringUtils.startsWith(layer.name:lower(), "battleborder") then
        table.insert(self.battle_borders, tilelayer)
    end
end

function operations.createTileLayer(self, data)
    assert(data.encoding == "lua", "Tile layer format \"" .. tostring(data.encoding)
        .. "\" is not supported. Please set the format to CSV in the map properties.")
    return TileLayer(self, data)
end

function operations.decodeTileData(self, tile)
    return TiledUtils.parseTileGid(tile)
end

function operations.encodeTileData(self, tileset, tile_id)
    local _, first_id = self:getTileset(tileset)
    return first_id + tile_id
end

function operations.loadImage(self, layer, depth)
    local success, texture_result = self:loadTextureFromImagePath(layer.image)
    if not success then
        error("Map \"" .. self.data.id .. "\" failed to load image layer \"" .. layer.name .. "\"\n" .. texture_result)
    end
    local sprite = Sprite(texture_result, layer.offsetx, layer.offsety)
    sprite:setParallax(layer.parallaxx, layer.parallaxy)
    sprite.alpha = layer.opacity
    sprite.layer = depth
    if layer.tintcolor then
        sprite:setColor(layer.tintcolor[1] / 255, layer.tintcolor[2] / 255, layer.tintcolor[3] / 255)
    end
    sprite:setSpeed(layer.properties["speedx"] or 0, layer.properties["speedy"] or 0)
    if layer.repeatx or layer.properties["wrapx"] then
        sprite.wrap_texture_x = true
    end
    if layer.repeaty or layer.properties["wrapy"] then
        sprite.wrap_texture_y = true
    end
    if layer.properties["fitscreen"] then
        sprite.width = SCREEN_WIDTH
        sprite.height = SCREEN_HEIGHT
    end
    sprite:setScale(layer.properties["scalex"] or 1, layer.properties["scaley"] or 1)
    self.world:addChild(sprite)
    self.image_layers[layer.name] = sprite
    if StringUtils.startsWith(layer.name:lower(), "battleborder") then
        sprite.alpha = 0
        table.insert(self.battle_borders, sprite)
    end
end

function operations.loadTextureFromImagePath(self, filename)
    local image_dir = "assets/sprites"
    local success, result, final_path = TiledUtils.relativePathToAssetId(image_dir, filename, self.full_map_path)

    if not success then
        if result == "not under prefix" then
            return false, "Image not found in \"" .. image_dir .. "\" (Got path \"" .. final_path .. "\")"
        elseif result == "path outside root" then
            return false, "Image path located outside Kristal (Got path \"<kristal>/" .. final_path .. "\")"
        else
            return false, "Unknown reason"
        end
    end

    return true, result
end

function operations.loadCollision(self, layer)
    TableUtils.merge(self.collision, self:loadHitboxes(layer))
end

function operations.loadEnemyCollision(self, layer)
    TableUtils.merge(self.enemy_collision, self:loadHitboxes(layer))
end

function operations.loadBlockCollision(self, layer)
    TableUtils.merge(self.block_collision, self:loadHitboxes(layer))
end

function operations.loadBattleAreas(self, layer)
    TableUtils.merge(self.battle_areas, self:loadHitboxes(layer))
end

function operations.loadHitboxes(self, layer)
    local hitboxes = {}
    local ox, oy = layer.offsetx or 0, layer.offsety or 0
    for _, v in ipairs(layer.objects) do
        local hitbox = TiledUtils.colliderFromShape(self.world, v, v.x + ox, v.y + oy, v.properties)
        if hitbox then
            table.insert(hitboxes, hitbox)

            self.hitboxes_by_id[v.id] = hitbox

            self.hitboxes_by_name[v.name] = self.hitboxes_by_name[v.name] or {}
            table.insert(self.hitboxes_by_name[v.name], hitbox)
        end
    end
    return hitboxes
end

function operations.loadShapes(self, layer)
    self.shape_layers[layer.name] = layer

    for _, v in ipairs(layer.objects) do
        self.shapes_by_id[v.id] = v

        self.shapes_by_name[v.name] = self.shapes_by_name[v.name] or {}
        table.insert(self.shapes_by_name[v.name], v)
    end
end

function operations.loadMarkers(self, layer)
    for _, v in ipairs(layer.objects) do
        v.width = v.width or 0
        v.height = v.height or 0
        v.center_x = v.x + v.width / 2
        v.center_y = v.y + v.height / 2

        local marker = TableUtils.copy(v, true)

        v.x = v.x + (layer.offsetx or 0)
        v.y = v.y + (layer.offsety or 0)
        v.center_x = v.center_x + (layer.offsetx or 0)
        v.center_y = v.center_y + (layer.offsety or 0)

        v.player_state = marker.properties["player_state"] or "WALK"

        if v.name ~= nil then
            self.markers[v.name] = v
        end

        self.markers_by_id[v.id] = v
    end
end

function operations.loadPaths(self, layer)
    local ox, oy = layer.offsetx or 0, layer.offsety or 0
    for _, v in ipairs(layer.objects) do
        local path = {}
        if v.shape == "ellipse" then
            path.shape = "ellipse"
            path.x = v.x + v.width / 2 + ox
            path.y = v.y + v.height / 2 + oy
            path.rx = v.width / 2 + ox
            path.ry = v.height / 2 + oy

            -- Roughly calculte ellipse perimeter bc the actual calculation is hard
            path.length = 2 * math.pi * ((path.rx + path.ry) / 2)
            path.closed = true
        else
            path.shape = "line"
            path.x = v.x
            path.y = v.y
            local points = TableUtils.copy(v.polygon or v.polyline or {})
            if v.shape == "rectangle" then
                points = { { x = 0, y = 0 }, { x = v.width, y = 0 }, { x = v.width, y = v.height }, { x = 0, y = v.height }, { x = 0, y = 0 } }
                path.closed = true
            else
                if v.shape ~= "polyline" then
                    table.insert(points, points[1])
                    path.closed = true
                end
            end
            for i, point in ipairs(points) do
                points[i] = { x = v.x + point.x + ox, y = v.y + point.y + oy }
            end
            path.points = points
            path.length = 0
            for i = 1, #points - 1 do
                path.length = path.length + MathUtils.dist(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y)
            end
        end
        self.paths[v.name] = path
    end
end

function operations.shouldLoadObject(self, data, layer)
    local skip_loading = false
    local uid = self:getUniqueID() .. "#" .. tostring(data.properties["uid"] or data.id)
    if data.properties["cond"] then
        local env = setmetatable({}, {__index = function(t, k)
            return Game:getFlag(uid .. ":" .. k) or Game:getFlag(k) or _G[k]
        end})
        local chunk, _ = assert(loadstring("return " .. data.properties["cond"]))
        skip_loading = not setfenv(chunk, env)()
    elseif data.properties["flagcheck"] then
        local inverted, flag = StringUtils.startsWith(data.properties["flagcheck"], "!")

        local result = Game:getFlag(uid .. ":" .. flag) or Game:getFlag(flag)
        local value = data.properties["flagvalue"]
        local is_true
        if value ~= nil then
            is_true = result == value
        elseif type(result) == "number" then
            is_true = result > 0
        else
            is_true = result
        end

        if is_true then
            skip_loading = inverted
        else
            skip_loading = not inverted
        end
    end
    return not skip_loading
end

function operations.loadObjects(self, layer, depth, layer_type)
    local parent = layer_type == "controllers" and self.world.controller_parent or self.world

    self.events_by_layer[layer.name] = {}
    for _, v in ipairs(layer.objects) do
        v.width = v.width or 0
        v.height = v.height or 0
        v.center_x = v.x + v.width / 2
        v.center_y = v.y + v.height / 2

        -- Get width/height of the full polygon (usable when a polygon is not supported on an object)
        if v.polygon then
            local min_x, max_x, min_y, max_y = 0, 0, 0, 0
            for _, point in ipairs(v.polygon) do
                min_x = math.min(point.x, min_x)
                max_x = math.max(point.x, max_x)
                min_y = math.min(point.y, min_y)
                max_y = math.max(point.y, max_y)
            end

            v.width = max_x - min_x
            v.height = max_y - min_y
            v.center_x = v.x - min_x + v.width / 2
            v.center_y = v.y - min_y + v.height / 2
        end

        if v.gid then
            local tx, ty, tw, th = self:getTileObjectRect(v)
            v.center_x = tx + tw / 2
            v.center_y = ty + th / 2
        end

        local obj_type = v.type or v.class
        if obj_type == "" then
            obj_type = v.name
        end

        local uid = self:getUniqueID() .. "#" .. tostring(v.properties["uid"] or v.id)
        if not Game:getFlag(uid .. ":dont_load") then
            if self:shouldLoadObject(v, layer) then
                local obj
                if layer_type == "controllers" then
                    obj = self:loadController(obj_type, v)
                else
                    obj = self:loadObject(obj_type, v)
                end
                if obj then
                    obj.x = obj.x + (layer.offsetx or 0)
                    obj.y = obj.y + (layer.offsety or 0)
                    obj:setParallax((obj.parallax_x or 1) * layer.parallaxx, (obj.parallax_y or 1) * layer.parallaxy)
                    if not obj.object_id then
                        obj.object_id = v.id
                    end
                    if not obj.unique_id then
                        obj.unique_id = v.properties["uid"]
                    end
                    obj.layer = depth
                    obj.layer_name = layer.name
                    obj.data = v

                    if v.gid and obj.applyTileObject then
                        obj:applyTileObject(v, self)
                    end

                    parent:addChild(obj)

                    table.insert(self.events, obj)

                    self.events_by_name[v.name] = self.events_by_name[v.name] or {}
                    table.insert(self.events_by_name[v.name], obj)
                    table.insert(self.events_by_layer[layer.name], obj)

                    if v.id then
                        self.events_by_id[v.id] = obj
                        self.next_object_id = math.max(self.next_object_id, v.id)
                    end
                end
            end
        end
    end
end

function operations.legacyLoadObject(self, name, data)
    local registered_event = Registry.getLegacyEvent(name)
    if registered_event then
        return Registry.createLegacyEvent(name, data)
    end

    return nil
end

function operations.loadObject(self, name, data)

    -- Check the events
    local loaded = Kristal.callEvent(KRISTAL_EVENT.loadObject, self.world, name, data)
    if loaded ~= nil then
        if type(loaded) == "boolean" then -- don't load the object if it returns true
            if loaded then
                return
            end
        else
            return loaded
        end
    end

    -- Check the registry
    if Game.event_registry:has(name) then
        return Game.event_registry:create(name, data)
    end

    -- Attempt to use the legacy system to load it
    loaded = self:legacyLoadObject(name, data)
    if loaded ~= nil then
        return loaded
    end

    -- Check for built-in events, must happen after everything else
    if Game.builtin_event_registry:has(name) then
        return Game.builtin_event_registry:create(name, data)
    end

    -- Fallback to a TileObject
    if data.gid then
        return self:createTileObject(data)
    end

    Kristal.Console:warn("No event with ID '" .. tostring(name) .. "' found")
end

function operations.loadController(self, name, data)
    -- Mod object loading
    local obj = Kristal.modCall("loadController", self.world, name, data)
    if obj then
        return obj
    else
        local controllers = Kristal.modGet("Controllers")
        if controllers and controllers[name] then
            return controllers[name](data)
        end
    end
    local registered_event = Registry.getController(name)
    if registered_event then
        return Registry.createController(name, data)
    end
    -- Library object loading
    for id, lib in Kristal.iterLibraries() do
        local obj = Kristal.libCall(id, "loadController", self.world, name, data)
        if obj then
            return obj
        else
            if lib.Controllers and lib.Controllers[name] then
                return lib.Controllers[name](data)
            end
        end
    end
    -- Kristal object loading
    if name:lower() == "toggle" then
        return ToggleController(data.properties)
    elseif name:lower() == "fountainshadow" then
        return FountainShadowController(data.properties)
    end
end

function operations.populateTilesets(self, data)
    self.tilesets = {}
    for _, tileset_data in ipairs(data) do
        local tileset
        local filename = tileset_data.exportfilename or tileset_data.filename
        if filename then
            local success, result = self:loadTilesetFromTilesetPath(filename)
            if not success then
                error("Map \"" .. self.data.id .. "\" failed to load tileset \"" .. tostring(tileset_data.name) .. "\"\n" .. result)
            end
            tileset = result
        else
            tileset = Tileset(tileset_data, self.full_map_path .. "/" .. self.data.id, self.full_map_path)
        end
        table.insert(self.tilesets, tileset)
        local gid = tileset_data.firstgid or (self.max_gid + 1)
        self.tileset_gids[tileset] = gid
        self.max_gid = math.max(self.max_gid, gid + tileset.id_count - 1)
    end
end

function operations.loadTilesetFromTilesetPath(self, filename)
    local tileset_dir = "scripts/world/tilesets"
    local success, result, final_path = TiledUtils.relativePathToAssetId(tileset_dir, filename, self.full_map_path)

    if not success then
        if result == "not under prefix" then
            return false, "Tileset not found in \"" .. tileset_dir .. "\" (Got path \"" .. final_path .. "\")"
        elseif result == "path outside root" then
            return false, "Tileset path located outside Kristal (Got path \"<kristal>/" .. final_path .. "\")"
        else
            return false, "Unknown reason"
        end
    end

    local tileset = Registry.getTileset(result)

    if not tileset then
        return false, "No tileset found with id \"" .. result .. "\""
    end

    return true, tileset
end

function operations.getTileset(self, id)
    if type(id) == "number" then
        id = TiledUtils.parseTileGid(id)
        for i = 1, #self.tilesets do
            local tileset = self.tilesets[i]
            local first_id = self.tileset_gids[tileset]
            local next_id = first_id + tileset.id_count
            if i < #self.tilesets then
                next_id = self.tileset_gids[self.tilesets[i + 1]]
            end
            if id >= first_id and id < next_id then
                return tileset, (id - first_id)
            end
        end
    elseif type(id) == "string" then
        for _, v in ipairs(self.tilesets) do
            if v.name == id then
                return v, self.tileset_gids[v]
            end
        end
    end
    return nil, 0
end

function operations.getTileObjectRect(self, data)
    local gid = TiledUtils.parseTileGid(data.gid)
    local tileset = self:getTileset(gid)

    local origin = Tileset.ORIGINS[tileset.object_alignment] or Tileset.ORIGINS["unspecified"]

    return data.x - (origin[1] * data.width), data.y - (origin[2] * data.height), data.width, data.height
end

function operations.createTileObject(self, data, x, y, width, height)
    if data.gid then
        local gid, flip_x, flip_y = TiledUtils.parseTileGid(data.gid)
        local tileset, tile_id = self:getTileset(gid)
        return TileObject(tileset, tile_id, x or data.x, y or data.y, width or data.width, height or data.height, math.rad(data.rotation or 0), flip_x, flip_y)
    end
end

return TiledMapReader
