---@class EditorPropertyRegistry : Class
---@overload fun(): EditorPropertyRegistry
local EditorPropertyRegistry = Class()

function EditorPropertyRegistry:init()
    self.types = {}
    self.type_order = {}
    self.function_sources = setmetatable({}, { __mode = "k" })
    self:registerType("string", { name = "String", default = "", control = "text" })
    self:registerType("value", {
        name = "Value", default = "", control = "multiline_value",
        coerce = function(value)
            if type(value) ~= "string" then return value end
            local trimmed = value:match("^%s*(.-)%s*$")
            if trimmed:match("^function%s*%(") then
                return self:compileFunction(value)
            end
            if trimmed:sub(1, 1) == "{" then
                return self:compileTable(value)
            end
            if value:lower() == "true" then return true end
            if value:lower() == "false" then return false end
            return tonumber(value) or value
        end
    })
    self:registerType("table", {
        name = "Table", default = {}, control = "table",
        coerce = function(value)
            if type(value) == "table" then return value end
            return self:compileTable(value)
        end
    })
    self:registerType("function", {
        name = "Function", default = "", control = "multiline_value",
        coerce = function(value)
            if type(value) == "function" then return value end
            return self:compileFunction(tostring(value or ""))
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
    self:registerType("object_reference", {
        name = "Object Reference",
        default = nil,
        control = "object_reference",
        coerce = function(value, definition)
            if value == nil or value == "" then return EditorObjectReference(definition and definition.map_id, nil) end
            return EditorObjectReference.from(value, definition and definition.map_id)
        end
    })
end

function EditorPropertyRegistry:compileTable(source)
    local chunk, message = loadstring("return " .. tostring(source or ""), "editor_property_table")
    if not chunk then self.last_function_error = message return nil end
    local success, value = pcall(chunk)
    if not success or type(value) ~= "table" then
        self.last_function_error = success and "Value is not a table" or tostring(value)
        return nil
    end
    self.last_function_error = nil
    return value
end

local function sortedTableKeys(value)
    local keys = {}
    for key in pairs(value) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            if type(a) == "number" or type(a) == "string" then return a < b end
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)
    return keys
end

local function isContiguousArray(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count, maximum = count + 1, math.max(maximum, key)
    end
    return count == maximum
end

function EditorPropertyRegistry:formatValue(value, indent, seen)
    local value_type = type(value)
    if value_type == "function" then
        return self.function_sources[value]
            or "function(...)\n    -- existing function source is unavailable\nend"
    elseif value_type == "string" then
        return string.format("%q", value)
    elseif value_type ~= "table" then
        if value == nil then return "nil" end
        return tostring(value)
    end

    indent = indent or 0
    seen = seen or {}
    if seen[value] then return "\"<cyclic table>\"" end
    seen[value] = true
    local padding = string.rep("    ", indent)
    local child_padding = string.rep("    ", indent + 1)
    local entries = {}
    local array = isContiguousArray(value)
    for _, key in ipairs(sortedTableKeys(value)) do
        local formatted = self:formatValue(value[key], indent + 1, seen)
        if array then
            table.insert(entries, child_padding .. formatted)
        else
            local key_text
            if type(key) == "string" and key:match("^[%a_][%w_]*$") then
                key_text = key
            else
                key_text = "[" .. self:formatValue(key, indent + 1, seen) .. "]"
            end
            table.insert(entries, child_padding .. key_text .. " = " .. formatted)
        end
    end
    seen[value] = nil
    if #entries == 0 then return "{}" end
    return "{\n" .. table.concat(entries, ",\n") .. "\n" .. padding .. "}"
end

function EditorPropertyRegistry:compileFunction(source)
    local chunk, message = loadstring("return " .. tostring(source or ""), "editor_property_function")
    if not chunk then self.last_function_error = message return nil end
    local success, value = pcall(chunk)
    if not success or type(value) ~= "function" then
        self.last_function_error = success and "Value is not an anonymous function" or tostring(value)
        return nil
    end
    self.last_function_error = nil
    self.function_sources[value] = source
    return value
end

function EditorPropertyRegistry:getDisplayValue(type_id, value)
    if type(value) == "function" then
        return self.function_sources[value] or "-- Existing function source is unavailable\nfunction(...)\n    -- replace to edit\nend"
    end
    if type(value) == "table" then return self:formatValue(value) end
    if value == nil then return "" end
    return tostring(value)
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
