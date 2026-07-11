local EditorDarkFountain, super = Class(EditorEvent)
function EditorDarkFountain:init(data, options)
    super.init(self, data, options)
    self:registerProperty("narrow", "boolean")
end
return EditorDarkFountain
