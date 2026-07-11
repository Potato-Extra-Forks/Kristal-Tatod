---@class EditorPropertySet : Class
---@overload fun(values?: table, types?: table): EditorPropertySet
local EditorPropertySet = Class()

function EditorPropertySet:init(values, types)
    self.values = values or {}
    self.types = types or {}
    self.order = {}
    self.definitions = {}
    self.group_order = {}
    self.groups = {}
    local names = {}
    for name in pairs(self.values) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        self:registerProperty(name, self.types[name] or self:inferType(self.values[name]), { custom = true })
    end
end

function EditorPropertySet:inferType(value)
    if type(value) == "boolean" then return "boolean" end
    if type(value) == "number" then return "number" end
    return "string"
end

function EditorPropertySet:registerProperty(id, property_type, options)
    options = TableUtils.copy(options or {}, true)
    options.id = id
    options.type = property_type or options.type or self.types[id] or "string"
    options.name = options.name or StringUtils.titleCase(id:gsub("_", " "))
    if not self.definitions[id] then table.insert(self.order, id) end
    self.definitions[id] = options
    if self.values[id] ~= nil then self.types[id] = options.type end
    return options
end

function EditorPropertySet:getProperty(id)
    return self.definitions[id]
end

function EditorPropertySet:getProperties()
    local result = {}
    for _, id in ipairs(self.order) do table.insert(result, self.definitions[id]) end
    return result
end

function EditorPropertySet:getValue(id)
    if self.values[id] ~= nil then return self.values[id] end
    local definition = self.definitions[id]
    return Registry.editor_properties:getDefault(definition and definition.type or "string", definition)
end

function EditorPropertySet:setValue(id, value)
    local definition = self.definitions[id] or self:registerProperty(id, self.types[id] or self:inferType(value), { custom = true })
    local coerced = Registry.editor_properties:coerce(definition.type, value, definition)
    if coerced == nil then return false end
    self.values[id] = coerced
    self.types[id] = definition.type
    return true
end

function EditorPropertySet:addProperty(id, property_type, options)
    local definition = self:registerProperty(id, property_type, TableUtils.merge({ custom = true }, options or {}))
    self.values[id] = Registry.editor_properties:getDefault(definition.type, definition)
    self.types[id] = definition.type
    return definition
end

function EditorPropertySet:renameProperty(old_id, new_id)
    local definition = self.definitions[old_id]
    if not definition or self.definitions[new_id] then return false end
    self.values[new_id], self.values[old_id] = self.values[old_id], nil
    self.types[new_id], self.types[old_id] = self.types[old_id], nil
    self.definitions[old_id] = nil
    definition.id = new_id
    definition.name = StringUtils.titleCase(new_id:gsub("_", " "))
    self.definitions[new_id] = definition
    for index, id in ipairs(self.order) do if id == old_id then self.order[index] = new_id break end end
    return true
end

function EditorPropertySet:removeProperty(id)
    local definition = self.definitions[id]
    self.values[id] = nil
    self.types[id] = nil
    if definition and definition.custom then
        self.definitions[id] = nil
        for index, candidate in ipairs(self.order) do
            if candidate == id then table.remove(self.order, index) break end
        end
    end
    return definition ~= nil
end

function EditorPropertySet:registerGroup(id, options)
    local group = EditorPropertyGroup(id, options, self):bind(Registry.editor_properties)
    if not self.groups[id] then table.insert(self.group_order, id) end
    self.groups[id] = group
    return group
end

function EditorPropertySet:getGroups()
    local result = {}
    for _, id in ipairs(self.group_order) do table.insert(result, self.groups[id]) end
    return result
end

return EditorPropertySet
