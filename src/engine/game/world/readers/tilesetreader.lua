---@class TilesetReader : Class
---@overload fun(tileset: Tileset): TilesetReader
local TilesetReader = Class()

function TilesetReader:init(tileset)
    self.tileset = tileset
    self.operations = self.operations or {}
end

function TilesetReader:call(operation, ...)
    local callback = self.operations[operation]
    if not callback then
        error(string.format("%s does not implement tileset operation '%s'",
            ClassUtils.getClassName(self), tostring(operation)), 2)
    end
    return callback(self.tileset, ...)
end

function TilesetReader:initialize(data, path, base_dir)
    error(ClassUtils.getClassName(self) .. " does not implement tileset initialization", 2)
end

return TilesetReader
