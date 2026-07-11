local EditorWarpDoor, super = Class(EditorEvent)

function EditorWarpDoor:init(data, options)
    super.init(self, data, options)
    self:registerProperty("open", "boolean", { default = true })
    self:registerProperty("openflag", "string", { name = "Open Flag" })
    local destinations = self:registerPropertyGroup("destinations", {
        name = "Destination",
        indexed = true,
        primary = "map"
    })
    destinations:registerProperty("map", "string")
    destinations:registerProperty("name", "string")
    destinations:registerProperty("marker", "string")
    destinations:registerProperty("flag", "string")
end
return EditorWarpDoor
