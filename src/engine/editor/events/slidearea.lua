local EditorSlideArea, super = Class(EditorEvent)
function EditorSlideArea:init(data, options)
    super.init(self, data, options)
    self:registerProperty("lock", "boolean")
end
return EditorSlideArea
