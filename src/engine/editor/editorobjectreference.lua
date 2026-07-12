---@class EditorObjectReference : Class
---@overload fun(map_id?: string, object_id?: string|number): EditorObjectReference
local EditorObjectReference = Class()

function EditorObjectReference:init(map_id, object_id)
    self.map_id = map_id
    self.object_id = object_id
end

function EditorObjectReference:getLabel()
    if self.object_id == nil then return "None" end
    if self.map_id and self.map_id ~= "" then
        return tostring(self.map_id) .. " : " .. tostring(self.object_id)
    end
    return tostring(self.object_id)
end

function EditorObjectReference:matches(map_id, object_id)
    return self.map_id == map_id and tostring(self.object_id) == tostring(object_id)
end

function EditorObjectReference.from(value, default_map_id)
    if type(value) == "table" and value.includes and value:includes(EditorObjectReference) then
        if value.map_id ~= nil or default_map_id == nil then return value end
        return EditorObjectReference(default_map_id, value.object_id)
    end
    if type(value) == "table" then
        return EditorObjectReference(value.map_id or value.map or default_map_id,
            value.object_id or value.object or value.id)
    end
    if value == nil or value == "" then return EditorObjectReference(default_map_id, nil) end
    return EditorObjectReference(default_map_id, value)
end

return EditorObjectReference
