---@class EditorMapReader : MapReader
---@overload fun(map: Map): EditorMapReader
local EditorMapReader, super = Class(MapReader)

EditorMapReader.FORMAT = "editor"
EditorMapReader.LEGACY_FORMAT = false
EditorMapReader.operations = EditorFormat.mapOperations

function EditorMapReader:initialize(data)
    return EditorFormat.initializeMap(self.map, data, self)
end

function EditorMapReader:read(data)
    return EditorFormat.readMap(self.map, data, self)
end

function EditorMapReader.convertLegacyData(data, options)
    return EditorFormat.convertTiledMap(data, options)
end

function EditorMapReader.saveData(data, path, options)
    return EditorFormat.saveMapData(data, path, options)
end

function EditorMapReader:save(path, options)
    return EditorFormat.saveMapData(self.map.data, path, options)
end

return EditorMapReader
