---@class EditorPropertiesPanel : EditorControl
---@overload fun(editor: table): EditorPropertiesPanel
local EditorPropertiesPanel, super = Class(EditorControl)

local function displayValue(value)
    if value == nil then return "" end
    return tostring(value)
end

function EditorPropertiesPanel:init(editor)
    super.init(self, 0, 0, 300, 400)
    self.editor = editor
    self.target = nil
    self.generated_controls = {}
    self.layout_rows = {}
    self.scroll_y = 0
    self.content_height = 0
    self.clip = true
    self.add_button = self:addChild(EditorButton("Add Property", function() self:openAddPropertyMenu() end))
    self.add_button.visible = false
    self.scrollbar = self:addChild(EditorScrollbar({
        width = 12,
        on_changed = function(value) self.scroll_y = self:getMaxScroll() * value end
    }))
end

function EditorPropertiesPanel:clearGeneratedControls()
    for _, control in ipairs(self.generated_controls) do self:removeChild(control) end
    self.generated_controls = {}
    self.layout_rows = {}
end

function EditorPropertiesPanel:addGeneratedControl(control)
    table.insert(self.generated_controls, control)
    return self:addChild(control)
end

function EditorPropertiesPanel:getProperties()
    if not self.target then return nil end
    if self.target.property_set then return self.target.property_set.values end
    if self.target.get_properties then return self.target.get_properties() end
    return self.target.properties
end

function EditorPropertiesPanel:getPropertyTypes()
    if not self.target then return nil end
    if self.target.property_set then return self.target.property_set.types end
    if self.target.get_property_types then return self.target.get_property_types() end
    self.target.property_types = self.target.property_types or {}
    return self.target.property_types
end

function EditorPropertiesPanel:getSchema()
    if self.target and self.target.property_set then return self.target.property_set:getProperties() end
    return {}
end

function EditorPropertiesPanel:getPropertyGroups()
    if self.target and self.target.property_set then return self.target.property_set:getGroups() end
    return {}
end

function EditorPropertiesPanel:notifyChanged(kind)
    if self.target and self.target.on_changed then self.target.on_changed(kind) end
end

function EditorPropertiesPanel:setTarget(target)
    self.target = target
    self.scroll_y = 0
    self:rebuild()
end

function EditorPropertiesPanel:getPropertyDefinition(name)
    if self.target and self.target.property_set then return self.target.property_set:getProperty(name) end
    return nil
end

function EditorPropertiesPanel:getPropertyType(name, definition, value)
    local property_types = self:getPropertyTypes() or {}
    if definition then return definition.type end
    if property_types[name] then return property_types[name] end
    if type(value) == "boolean" then return "boolean" end
    if type(value) == "number" then return "number" end
    return "string"
end

function EditorPropertiesPanel:createChoiceControl(name, definition, value)
    local button
    button = EditorButton(displayValue(value), function()
        local items = {}
        for _, choice in ipairs(Registry.editor_properties:getChoices(definition)) do
            local choice_value = type(choice) == "table" and (choice.value ~= nil and choice.value or choice.id) or choice
            local choice_label = type(choice) == "table" and (choice.label or choice.name or choice_value) or choice
            table.insert(items, {
                label = tostring(choice_label),
                checked = choice_value == self:getPropertyValue(name, definition),
                action = function()
                    if self:setPropertyValue(name, choice_value, definition) then button.label = displayValue(choice_value) end
                end
            })
        end
        local x, y = button:getGlobalPosition()
        self.editor.dockspace:openContextMenu(items, x, y + button.height, button)
    end)
    return button
end

function EditorPropertiesPanel:createValueControl(name, definition, value)
    local property_type = self:getPropertyType(name, definition, value)
    local control_type = Registry.getEditorPropertyType(property_type).control or "text"
    if control_type == "boolean" then
        return self:addGeneratedControl(EditorCheckbox("", value == true, function(checked)
            self:setPropertyValue(name, checked, definition)
        end))
    elseif control_type == "choice" then
        return self:addGeneratedControl(self:createChoiceControl(name, definition, value))
    end
    local input = self:addGeneratedControl(EditorTextInput({
        on_submit = function(input_value) self:setPropertyValue(name, input_value, definition) end
    }))
    input:setValue(displayValue(value), true)
    return input
end

function EditorPropertiesPanel:rebuild()
    self:clearGeneratedControls()
    local properties = self:getProperties()
    self.add_button.visible = self.target ~= nil and properties ~= nil
    if not self.target then return end

    for _, field in ipairs(self.target.fields or {}) do
        local input = self:addGeneratedControl(EditorTextInput({
            placeholder = field.placeholder,
            on_changed = field.live and function(value)
                if field.set(value, false) ~= false then self:notifyChanged("standard") end
            end or nil,
            on_submit = function(value)
                if field.set(value, true) ~= false then self:notifyChanged("standard") end
            end
        }))
        input:setValue(displayValue(field.get()), true)
        input.enabled = field.readonly ~= true
        table.insert(self.layout_rows, { kind = "standard", label = field.label, controls = { input }, value_control = input })
    end

    local definitions, included = self:getSchema(), {}
    for _, definition in ipairs(definitions) do
        local name = definition.id
        included[name] = true
        local value = self:getPropertyValue(name, definition)
        local name_input = self:addGeneratedControl(EditorTextInput(definition.custom and {
            on_submit = function(value) self:renameProperty(name, value) end
        } or nil))
        name_input:setValue(name, true)
        name_input.enabled = definition.custom == true
        local value_control = self:createValueControl(name, definition, value)
        local remove_button = self:addGeneratedControl(EditorButton("-", function() self:removeProperty(name) end))
        table.insert(self.layout_rows, {
            kind = "property", property_name = name, definition = definition,
            name_input = name_input, value_control = value_control, remove_button = remove_button,
            controls = { name_input, value_control, remove_button }
        })
    end

    local names = {}
    for name in pairs(properties or {}) do if not included[name] then table.insert(names, name) end end
    table.sort(names)
    for _, name in ipairs(names) do
        local property_name = name
        local name_input = self:addGeneratedControl(EditorTextInput({
            on_submit = function(value) self:renameProperty(property_name, value) end
        }))
        name_input:setValue(property_name, true)
        local definition = self:getPropertyDefinition(property_name)
        local value_control = self:createValueControl(property_name, definition, properties[property_name])
        local remove_button = self:addGeneratedControl(EditorButton("-", function() self:removeProperty(property_name) end))
        table.insert(self.layout_rows, {
            kind = "property", property_name = property_name, definition = definition,
            name_input = name_input, value_control = value_control, remove_button = remove_button,
            controls = { name_input, value_control, remove_button }
        })
    end
end

function EditorPropertiesPanel:getPropertyValue(name, definition)
    local properties = self:getProperties() or {}
    if properties[name] ~= nil then return properties[name] end
    local property_type = definition and definition.type or (self:getPropertyTypes() or {})[name] or "string"
    return Registry.editor_properties:getDefault(property_type, definition)
end

function EditorPropertiesPanel:focusProperty(name, column)
    for _, row in ipairs(self.layout_rows) do
        if row.kind == "property" and row.property_name == name then
            local control = column == "value" and row.value_control or row.name_input
            if self.editor.dockspace then self.editor.dockspace:setFocus(control) end
            return true
        end
    end
    return false
end

function EditorPropertiesPanel:openAddPropertyMenu()
    if not self:getProperties() then return false end
    local items = {}
    for _, property_type in ipairs(Registry.getEditorPropertyTypes()) do
        table.insert(items, {
            label = property_type.name,
            action = function() self:addProperty(property_type.id) end
        })
    end
    for _, group in ipairs(self:getPropertyGroups()) do
        table.insert(items, {
            label = "Add " .. group.name,
            action = function() self:addPropertyGroup(group.id) end
        })
    end
    local x, y = self.add_button:getGlobalPosition()
    return self.editor.dockspace:openContextMenu(items, x, y + self.add_button.height, self.add_button)
end

function EditorPropertiesPanel:addPropertyGroup(group_id)
    local properties, property_types = self:getProperties(), self:getPropertyTypes()
    local group = self.target and self.target.property_set and self.target.property_set.groups[group_id]
    if not properties or not group then return false end
    local index = group:addInstance(properties, property_types)
    self:notifyChanged("properties")
    self:rebuild()
    self:focusProperty(group:getStorageKey(group.primary or group.order[1], index), "value")
    return true
end

function EditorPropertiesPanel:addProperty(property_type)
    local properties, property_types = self:getProperties(), self:getPropertyTypes()
    if not properties then return false end
    property_type = property_type or "string"
    local base, name, index = "property", "property", 2
    local reserved = {}
    for _, definition in ipairs(self:getSchema()) do reserved[definition.id] = true end
    while properties[name] ~= nil or reserved[name] do
        name = base .. tostring(index)
        index = index + 1
    end
    if self.target.property_set then
        self.target.property_set:addProperty(name, property_type)
    else
        properties[name] = Registry.editor_properties:getDefault(property_type)
        property_types[name] = property_type
    end
    self:notifyChanged("properties")
    self:rebuild()
    self:focusProperty(name, "name")
    return true
end

function EditorPropertiesPanel:renameProperty(old_name, new_name)
    local properties, property_types = self:getProperties(), self:getPropertyTypes()
    new_name = tostring(new_name or ""):match("^%s*(.-)%s*$")
    if not properties or new_name == "" or new_name == old_name then return false end
    if properties[new_name] ~= nil or self:getPropertyDefinition(new_name) then
        self.editor:addWarning("A property named '" .. new_name .. "' already exists", nil, "property_name")
        self:rebuild()
        return false
    end
    if self.target.property_set then
        if not self.target.property_set:renameProperty(old_name, new_name) then return false end
    else
        properties[new_name] = properties[old_name]
        properties[old_name] = nil
        property_types[new_name] = property_types[old_name]
        property_types[old_name] = nil
    end
    self.editor:clearDiagnostics("property_name")
    self:notifyChanged("properties")
    self:rebuild()
    self:focusProperty(new_name, "name")
    return true
end

function EditorPropertiesPanel:setPropertyValue(name, value, definition)
    local properties, property_types = self:getProperties(), self:getPropertyTypes()
    if not properties then return false end
    definition = definition or self:getPropertyDefinition(name)
    local property_type = self:getPropertyType(name, definition, properties[name])
    local coerced = Registry.editor_properties:coerce(property_type, value, definition)
    if coerced == nil then
        self.editor:addWarning("Invalid " .. Registry.getEditorPropertyType(property_type).name:lower()
            .. " value for '" .. name .. "'", nil, "property_value")
        return false
    end
    if self.target.property_set then
        self.target.property_set:setValue(name, coerced)
    else
        properties[name] = coerced
        property_types[name] = property_type
    end
    self.editor:clearDiagnostics("property_value")
    self:notifyChanged("properties")
    return true
end

function EditorPropertiesPanel:removeProperty(name)
    local properties, property_types = self:getProperties(), self:getPropertyTypes()
    if not properties then return false end
    if self.target.property_set then
        self.target.property_set:removeProperty(name)
    else
        properties[name] = nil
        property_types[name] = nil
    end
    self:notifyChanged("properties")
    self:rebuild()
    if self.editor.dockspace then self.editor.dockspace:setFocus(self) end
    return true
end

function EditorPropertiesPanel:getMaxScroll()
    return math.max(0, self.content_height - math.max(0, self.height - 28))
end

function EditorPropertiesPanel:onWheelMoved(_, y)
    self.scroll_y = MathUtils.clamp(self.scroll_y - y * 42, 0, self:getMaxScroll())
    return true
end

function EditorPropertiesPanel:update(dt)
    local padding, y = 8, 30 - self.scroll_y
    local width = math.max(0, self.width - padding * 2 - self.scrollbar.width)
    local property_header_set = false
    for _, row in ipairs(self.layout_rows) do
        if row.kind == "standard" then
            row.label_y = y
            row.value_control:setBounds(padding, y + 18, width, 28)
            y = y + 54
        else
            if not property_header_set then
                self.property_header_y = y + 2
                y = y + 24
                property_header_set = true
            end
            local remove_width, gap = 28, 6
            local column_width = math.max(30, (width - remove_width - gap * 2) / 2)
            row.name_input:setBounds(padding, y, column_width, 28)
            row.value_control:setBounds(padding + column_width + gap, y, column_width, 28)
            row.remove_button:setBounds(padding + column_width * 2 + gap * 2, y, remove_width, 28)
            y = y + 34
        end
        for _, control in ipairs(row.controls) do
            control.visible = control.y + control.height > 27 and control.y < self.height
        end
    end
    if not property_header_set then
        self.property_header_y = y + 2
        y = y + 24
    end
    self.add_button:setBounds(padding, y + 4, width, 28)
    self.add_button.visible = self.target ~= nil and self:getProperties() ~= nil
        and self.add_button.y + self.add_button.height > 27 and self.add_button.y < self.height
    self.content_height = y + self.scroll_y + 40
    self.scroll_y = MathUtils.clamp(self.scroll_y, 0, self:getMaxScroll())
    local max_scroll = self:getMaxScroll()
    self.scrollbar.page = self.content_height == 0 and 1 or MathUtils.clamp((self.height - 28) / self.content_height, 0, 1)
    self.scrollbar.value = max_scroll == 0 and 0 or self.scroll_y / max_scroll
    self.scrollbar:setBounds(self.width - self.scrollbar.width, 28, self.scrollbar.width, math.max(0, self.height - 28))
    super.update(self, dt)
end

function EditorPropertiesPanel:drawSelf()
    Draw.setColor(0.08, 0.08, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    local font = EditorFont.get(16)
    love.graphics.setFont(font)
    if not self.target then
        Draw.setColor(0.55, 0.55, 0.58, 1)
        love.graphics.print("Nothing selected", 8, 8)
        return
    end
    Draw.setColor(0.88, 0.88, 0.9, 1)
    love.graphics.print(self.target.title or "Selection", 8, 8)
    for _, row in ipairs(self.layout_rows) do
        if row.kind == "standard" and row.label_y and row.label_y >= 27 and row.label_y < self.height then
            Draw.setColor(0.68, 0.68, 0.72, 1)
            love.graphics.print(row.label, 8, row.label_y)
        end
    end
    if self.property_header_y and self.property_header_y >= 27 and self.property_header_y < self.height then
        Draw.setColor(0.68, 0.68, 0.72, 1)
        love.graphics.print("Properties", 8, self.property_header_y)
    end
end

return EditorPropertiesPanel
