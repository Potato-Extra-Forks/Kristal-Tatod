local EditorFont = {}

local default_fonts = {}

function EditorFont.get(size)
    size = size or 16
    local editor = Kristal and Kristal.States and Kristal.States["Editor"]
    if not editor or editor.use_deltarune_font ~= false then
        return Assets.getFont("main", size)
    end
    if not default_fonts[size] then
        default_fonts[size] = love.graphics.newFont(size)
    end
    return default_fonts[size]
end

return EditorFont
