---@class EditorTilesetReader : TilesetReader
---@overload fun(tileset: Tileset): EditorTilesetReader
local EditorTilesetReader, super = Class(TilesetReader)

EditorTilesetReader.FORMAT = "editor"
EditorTilesetReader.LEGACY_FORMAT = false
EditorTilesetReader.operations = EditorFormat.tilesetOperations

function EditorTilesetReader:initialize(data, path, base_dir)
    return EditorFormat.initializeTileset(self.tileset, data, path, base_dir, self)
end

function EditorTilesetReader.convertLegacyData(data, options)
    return EditorFormat.convertTiledTileset(data, options)
end

function EditorTilesetReader.saveData(data, path, options)
    return EditorFormat.saveTilesetData(data, path, options)
end

function EditorTilesetReader:save(path, options)
    return EditorFormat.saveTilesetData(self.tileset.data, path, options)
end

return EditorTilesetReader
