local EditorNPC, super = Class(EditorEvent)

EditorNPC.sprite_property = "sprite"
function EditorNPC:init(data, options)
    super.init(self, data, options)
    self:registerProperty("actor", "string")
    self:registerProperty("sprite", "string")
    self:registerProperty("animation", "string")
    self:registerProperty("facing", "choice", { choices = { "up", "down", "left", "right" }, default = "down" })
    self:registerProperty("turn", "boolean")
    self:registerProperty("talk", "boolean", { default = true })
    self:registerProperty("talksprite", "string", { name = "Talk Sprite" })
    self:registerProperty("solid", "boolean", { default = true })
    self:registerProperty("cutscene", "string")
    self:registerProperty("script", "string")
    self:registerProperty("setflag", "string", { name = "Set Flag" })
    self:registerProperty("setvalue", "value", { name = "Set Value" })
    self:registerProperty("path", "string")
    self:registerProperty("speed", "number", { default = 6 })
    self:registerProperty("progress", "number")
end

return EditorNPC
