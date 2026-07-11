local EditorMirrorArea, super = Class(EditorEvent)
function EditorMirrorArea:init(data, options)
    super.init(self, data, options)
    self:registerProperty("offset", "number")
    self:registerProperty("opacity", "number", { default = 1 })
end
return EditorMirrorArea
