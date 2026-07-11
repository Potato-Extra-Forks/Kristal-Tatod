---@class EditorMapReader : MapReader
---@overload fun(map: Map): EditorMapReader
local EditorMapReader, super = Class(MapReader)

EditorMapReader.FORMAT = "editor"
EditorMapReader.LEGACY_FORMAT = false

function EditorMapReader:initialize(data)
    error("EditorMapReader is a placeholder; the Kristal editor map format is not implemented", 2)
end

function EditorMapReader:read(data)
    error("EditorMapReader is a placeholder; the Kristal editor map format is not implemented", 2)
end

function EditorMapReader.convertLegacyData(data, options)
    return nil, "Legacy Tiled map conversion is not implemented"
end

function EditorMapReader.saveData(data, path, options)
    return false, "The Kristal editor map format is not implemented"
end

return EditorMapReader
