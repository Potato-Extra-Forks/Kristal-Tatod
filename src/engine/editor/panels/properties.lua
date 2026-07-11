---@class EditorPropertiesPanel : EditorControl
---@overload fun(editor: table): EditorPropertiesPanel
local EditorPropertiesPanel, super = Class(EditorControl)

local function displayValue(value)
    if value == nil then return "" end
    return tostring(value)
end

local function coerceValue(value, previous)
    if type(previous) == "number" then return tonumber(value) or previous end
    if type(previous) == "boolean" then
        local lowered = tostring(value):lower()
        if lowered == "true" then return true end
        if lowered == "false" then return false end
        return previous
    end
    return value
end

function EditorPropertiesPanel:init(editor)
    super.init(self, 0, 0, 300, 400)
    self.editor = editor
    self.target = nil
    self.generated_controls = {}
    self.layout_rows = {}
    self.add_button = self:addChild(EditorButton("Add Property", function() self:addProperty() end))
    self.add_button.visible = false
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
    if self.target.get_properties then return self.target.get_properties() end
    return self.target.properties
end

function EditorPropertiesPanel:notifyChanged(kind)
    if self.target and self.target.on_changed then self.target.on_changed(kind) end
end

function EditorPropertiesPanel:setTarget(target)
    self.target = target
    self:rebuild()
end

function EditorPropertiesPanel:rebuild()
    self:clearGeneratedControls()
    self.add_button.visible = self.target ~= nil and self:getProperties() ~= nil
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
        table.insert(self.layout_rows, { kind = "standard", label = field.label, input = input })
    end

    local properties = self:getProperties()
    local names = {}
    for name in pairs(properties or {}) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local property_name = name
        local name_input = self:addGeneratedControl(EditorTextInput({
            on_submit = function(value) self:renameProperty(property_name, value) end
        }))
        name_input:setValue(property_name, true)
        local value_input = self:addGeneratedControl(EditorTextInput({
            on_submit = function(value) self:setPropertyValue(property_name, value) end
        }))
        value_input:setValue(displayValue(properties[property_name]), true)
        local remove_button = self:addGeneratedControl(EditorButton("-", function()
            self:removeProperty(property_name)
        end))
        table.insert(self.layout_rows, {
            kind = "property",
            property_name = property_name,
            name_input = name_input,
            value_input = value_input,
            remove_button = remove_button
        })
    end
end

function EditorPropertiesPanel:focusProperty(name, column)
    for _, row in ipairs(self.layout_rows) do
        if row.kind == "property" and row.property_name == name then
            local control = column == "value" and row.value_input or row.name_input
            if self.editor.dockspace then self.editor.dockspace:setFocus(control) end
            return true
        end
    end
    return false
end

function EditorPropertiesPanel:addProperty()
    local properties = self:getProperties()
    if not properties then return false end
    local base, name, index = "property", "property", 2
    while properties[name] ~= nil do
        name = base .. tostring(index)
        index = index + 1
    end
    properties[name] = ""
    self:notifyChanged("properties")
    self:rebuild()
    self:focusProperty(name, "name")
    return true
end

function EditorPropertiesPanel:renameProperty(old_name, new_name)
    local properties = self:getProperties()
    new_name = tostring(new_name or ""):match("^%s*(.-)%s*$")
    if not properties or new_name == "" or new_name == old_name then return false end
    if properties[new_name] ~= nil then
        self.editor:addWarning("A property named '" .. new_name .. "' already exists", nil, "property_name")
        self:rebuild()
        return false
    end
    properties[new_name] = properties[old_name]
    properties[old_name] = nil
    self.editor:clearDiagnostics("property_name")
    self:notifyChanged("properties")
    self:rebuild()
    self:focusProperty(new_name, "name")
    return true
end

function EditorPropertiesPanel:setPropertyValue(name, value)
    local properties = self:getProperties()
    if not properties or properties[name] == nil then return false end
    properties[name] = coerceValue(value, properties[name])
    self:notifyChanged("properties")
    return true
end

function EditorPropertiesPanel:removeProperty(name)
    local properties = self:getProperties()
    if not properties or properties[name] == nil then return false end
    properties[name] = nil
    self:notifyChanged("properties")
    self:rebuild()
    if self.editor.dockspace then self.editor.dockspace:setFocus(self) end
    return true
end

function EditorPropertiesPanel:update(dt)
    local padding, y = 8, 28
    local width = math.max(0, self.width - padding * 2)
    local custom_started = false
    for _, row in ipairs(self.layout_rows) do
        if row.kind == "standard" then
            row.input:setBounds(padding, y + 18, width, 28)
            y = y + 54
        else
            if not custom_started then
                self.custom_header_y = y + 2
                y = y + 24
                custom_started = true
            end
            local remove_width, gap = 28, 6
            local column_width = math.max(30, (width - remove_width - gap * 2) / 2)
            row.name_input:setBounds(padding, y, column_width, 28)
            row.value_input:setBounds(padding + column_width + gap, y, column_width, 28)
            row.remove_button:setBounds(padding + column_width * 2 + gap * 2, y, remove_width, 28)
            y = y + 34
        end
    end
    if not custom_started then
        self.custom_header_y = y + 2
        y = y + 24
    end
    self.add_button:setBounds(padding, y + 4, width, 28)
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
        if row.kind == "standard" then
            Draw.setColor(0.68, 0.68, 0.72, 1)
            love.graphics.print(row.label, row.input.x, row.input.y - 18)
        end
    end
    Draw.setColor(0.68, 0.68, 0.72, 1)
    love.graphics.print("Custom Properties", 8, self.custom_header_y or 28)
end

return EditorPropertiesPanel
