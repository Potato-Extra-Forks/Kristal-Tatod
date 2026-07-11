local EditorMagicGlass, super = Class(EditorEvent)
function EditorMagicGlass:init(data, options)
    super.init(self, data, options)
    self:registerProperty("new_sprite", "boolean", { name = "New Sprite" })
end
return EditorMagicGlass
