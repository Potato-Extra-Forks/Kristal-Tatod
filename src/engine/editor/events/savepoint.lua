local EditorSavepoint, super = Class(EditorEvent)

function EditorSavepoint:init(data, options)
    super.init(self, data, options)
    self:registerProperty("marker", "string")
    self:registerProperty("simple", "boolean")
    self:registerProperty("text_once", "string", { name = "Text Once" })
    self:registerProperty("heals", "boolean")
end

return EditorSavepoint
