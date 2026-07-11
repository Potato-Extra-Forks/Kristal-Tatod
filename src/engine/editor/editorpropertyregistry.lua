---@class EditorPropertyRegistry : Class
---@overload fun(): EditorPropertyRegistry
local EditorPropertyRegistry = Class()

function EditorPropertyRegistry:init()
    self.types = {}
    self.type_order = {}
    self:registerType("string", { name = "String", default = "", control = "text" })
    self:registerType("value", {
        name = "Value", default = "", control = "text",
        coerce = function(value)
            if type(value) ~= "string" then return value end
            if value:lower() == "true" then return true end
            if value:lower() == "false" then return false end
            return tonumber(value) or value
        end
    })
    self:registerType("number", { name = "Number", default = 0, control = "text", coerce = function(value) return tonumber(value) end })
    self:registerType("integer", {
        name = "Integer", default = 0, control = "text",
        coerce = function(value)
            local number = tonumber(value)
            return number and MathUtils.round(number) or nil
        end
    })
    self:registerType("boolean", {
        name = "Boolean", default = false, control = "boolean",
        coerce = function(value)
            if type(value) == "boolean" then return value end
            if tostring(value):lower() == "true" then return true end
            if tostring(value):lower() == "false" then return false end
        end
    })
    self:registerType("choice", {
        name = "Choice", default = "", control = "choice",
        coerce = function(value, definition)
            for _, choice in ipairs(self:getChoices(definition)) do
                local choice_value = type(choice) == "table" and (choice.value ~= nil and choice.value or choice.id) or choice
                if choice_value == value or tostring(choice_value) == tostring(value) then return choice_value end
            end
        end
    })
    self:registerType("chooser", {
        name = "Chooser", default = "", control = "choice", coerce = self.types.choice.coerce
    })
    self:registerType("color", {
        name = "Color", default = "#FFFFFFFF", control = "text",
        coerce = function(value)
            value = tostring(value or "")
            local hex = value:gsub("^#", "")
            return (#hex == 6 or #hex == 8) and hex:match("^%x+$") and "#" .. hex or nil
        end
    })
end

function EditorPropertyRegistry:registerType(id, definition)
    assert(type(id) == "string" and id ~= "", "Editor property types require an id")
    assert(type(definition) == "table", "Editor property type definitions must be tables")
    local entry = TableUtils.copy(definition, true)
    entry.id = id
    entry.name = entry.name or StringUtils.titleCase(id:gsub("_", " "))
    if not self.types[id] then table.insert(self.type_order, id) end
    self.types[id] = entry
    return entry
end

function EditorPropertyRegistry:getType(id)
    return self.types[id] or self.types.string
end

function EditorPropertyRegistry:getTypes()
    local result = {}
    for _, id in ipairs(self.type_order) do table.insert(result, self.types[id]) end
    return result
end

function EditorPropertyRegistry:getChoices(definition)
    local choices = definition and definition.choices or {}
    if type(choices) == "function" then
        local success, result = pcall(choices, definition)
        return success and type(result) == "table" and result or {}
    end
    return type(choices) == "table" and choices or {}
end

function EditorPropertyRegistry:coerce(type_id, value, definition)
    local property_type = self:getType(type_id)
    if property_type.coerce then return property_type.coerce(value, definition or {}, property_type) end
    return tostring(value or "")
end

function EditorPropertyRegistry:getDefault(type_id, definition)
    local value = definition and definition.default
    if value == nil then value = self:getType(type_id).default end
    return type(value) == "table" and TableUtils.copy(value, true) or value
end

return EditorPropertyRegistry
