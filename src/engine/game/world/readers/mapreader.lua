---@class MapReader : Class
---@overload fun(map: Map): MapReader
local MapReader = Class()

MapReader.FORMAT = "unknown"
MapReader.LEGACY_FORMAT = false

function MapReader:init(map)
    self.map = map
    self.operations = self.operations or {}
end

function MapReader:call(operation, ...)
    local callback = self.operations[operation]
    if not callback then
        error(string.format("%s does not implement map operation '%s'",
            ClassUtils.getClassName(self), tostring(operation)), 2)
    end
    return callback(self.map, ...)
end

function MapReader:initialize(data)
    error(ClassUtils.getClassName(self) .. " does not implement map initialization", 2)
end

function MapReader:read(data)
    error(ClassUtils.getClassName(self) .. " does not implement map reading", 2)
end

function MapReader:getFormat()
    return self.FORMAT
end

function MapReader:isLegacyFormat()
    return self.LEGACY_FORMAT == true
end

function MapReader:saveAsEditorFormat(path, options)
    return false, string.format("Map format '%s' cannot be saved as an editor map", tostring(self:getFormat()))
end

return MapReader
