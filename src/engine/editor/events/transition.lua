local EditorTransition, super = Class(EditorEvent)

EditorTransition.editor_sprite = "editor/transition"
function EditorTransition:init(data, options)
    super.init(self, data, options)
    self:registerProperty("map", "string")
    self:registerProperty("shop", "string")
    self:registerProperty("x", "number")
    self:registerProperty("y", "number")
    self:registerProperty("marker", "string")
    self:registerProperty("facing", "choice", { choices = { "up", "down", "left", "right" } })
    self:registerProperty("sound", "string")
    self:registerProperty("pitch", "number", { default = 1 })
    self:registerProperty("exit_delay", "number", { name = "Exit Delay" })
    self:registerProperty("exit_sound", "string", { name = "Exit Sound" })
    self:registerProperty("exit_pitch", "number", { name = "Exit Pitch", default = 1 })
end

return EditorTransition
