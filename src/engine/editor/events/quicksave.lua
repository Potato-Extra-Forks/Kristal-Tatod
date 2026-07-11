local EditorQuicksave, super = Class(EditorEvent)
function EditorQuicksave:init(data, options)
    super.init(self, data, options)
    self:registerProperty("marker", "string")
end
return EditorQuicksave
