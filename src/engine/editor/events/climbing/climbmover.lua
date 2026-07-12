local EditorClimbMover, super = Class(EditorEvent)

EditorClimbMover.editor_sprite = "world/events/climb_mover"
function EditorClimbMover:init(data, options)
    super.init(self, data, options)
    self:registerProperty("target", "object_reference")
    self:registerProperty("exit", "object_reference")
    self:registerProperty("start_exit", "object_reference", { name = "Start Exit" })
    self:registerProperty("one_way", "boolean", { name = "One Way" })
end
return EditorClimbMover
