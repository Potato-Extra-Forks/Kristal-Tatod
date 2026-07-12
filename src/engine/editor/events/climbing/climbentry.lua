local EditorClimbEntry, super = Class(EditorEvent)
function EditorClimbEntry:init(data, options)
    super.init(self, data, options)
    self:registerProperty("target", "object_reference")
    self:registerProperty("solid", "boolean")
end
return EditorClimbEntry
