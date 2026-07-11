local EditorClimbMover, super = Class(EditorEvent)

EditorClimbMover.editor_sprite = "world/events/climb_mover"
function EditorClimbMover:init(data, options)
    super.init(self, data, options)
    self:registerProperty("target", "string")
    self:registerProperty("exit", "string")
    self:registerProperty("start_exit", "string", { name = "Start Exit" })
    self:registerProperty("one_way", "boolean", { name = "One Way" })
end
return EditorClimbMover
