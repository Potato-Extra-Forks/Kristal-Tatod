---@class EditorTilesetReader : TilesetReader
---@overload fun(tileset: Tileset): EditorTilesetReader
local EditorTilesetReader, super = Class(TilesetReader)

function EditorTilesetReader:initialize(data, path, base_dir)
    error("EditorTilesetReader is a placeholder; the Kristal editor tileset format is not implemented", 2)
end

return EditorTilesetReader
