local EditorCyberTrashCan, super = Class(EditorEvent)
function EditorCyberTrashCan:init(data, options)
    super.init(self, data, options)
    self:registerProperty("item", "string")
    self:registerProperty("money", "integer")
    self:registerProperty("setflag", "string", { name = "Set Flag" })
    self:registerProperty("setvalue", "value", { name = "Set Value" })
end
return EditorCyberTrashCan
