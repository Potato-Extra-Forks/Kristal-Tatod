---@class EditorTextInput : EditorControl
---@overload fun(options?: table): EditorTextInput
local EditorTextInput, super = Class(EditorControl)

local function clampCursor(value, cursor)
    return MathUtils.clamp(cursor or (#value + 1), 1, #value + 1)
end

local function previousCodepoint(value, cursor)
    cursor = clampCursor(value, cursor)
    if cursor <= 1 then return 1 end
    return utf8.offset(value, -1, cursor) or 1
end

local function nextCodepoint(value, cursor)
    cursor = clampCursor(value, cursor)
    if cursor > #value then return #value + 1 end
    return utf8.offset(value, 2, cursor) or (#value + 1)
end

function EditorTextInput:init(options)
    options = options or {}
    super.init(self, options.x, options.y, options.width or 180, options.height or 28)
    self.value = options.value or ""
    self.placeholder = options.placeholder or ""
    self.on_changed = options.on_changed
    self.on_submit = options.on_submit
    self.on_cancel = options.on_cancel
    self.font = options.font
    self.cursor = #self.value + 1
    self.focusable = true
    self.accepts_text_input = true
    self.cursor_type = "type"
    self.focused = false
    self.padding = options.padding or 6
    self.clip = true
end

function EditorTextInput:setValue(value, silent)
    value = tostring(value or "")
    if self.value == value then return end
    self.value = value
    self.cursor = #value + 1
    if not silent and self.on_changed then
        self.on_changed(value, self)
    end
end

function EditorTextInput:onFocus()
    self.focused = true
    love.keyboard.setTextInput(true)
end

function EditorTextInput:onBlur()
    self.focused = false
    love.keyboard.setTextInput(false)
end

function EditorTextInput:onMousePressed(x, y, button)
    if button ~= 1 then return false end
    local font = self.font or EditorFont.get(16)
    local best_cursor = 1
    local best_distance = math.huge
    local cursor = 1
    while cursor <= #self.value + 1 do
        local width = font:getWidth(self.value:sub(1, cursor - 1))
        local distance = math.abs((x - self.padding) - width)
        if distance < best_distance then
            best_distance = distance
            best_cursor = cursor
        end
        if cursor > #self.value then break end
        cursor = nextCodepoint(self.value, cursor)
    end
    self.cursor = best_cursor
    return true
end

function EditorTextInput:onKeyPressed(key)
    self.cursor = clampCursor(self.value, self.cursor)
    if key == "backspace" then
        local previous = previousCodepoint(self.value, self.cursor)
        if previous < self.cursor then
            self:setValue(self.value:sub(1, previous - 1) .. self.value:sub(self.cursor))
            self.cursor = previous
        end
        return true
    elseif key == "delete" then
        local old_cursor = self.cursor
        local next_cursor = nextCodepoint(self.value, self.cursor)
        if next_cursor > self.cursor then
            self:setValue(self.value:sub(1, self.cursor - 1) .. self.value:sub(next_cursor))
            self.cursor = math.min(old_cursor, #self.value + 1)
        end
        return true
    elseif key == "left" then
        self.cursor = previousCodepoint(self.value, self.cursor)
        return true
    elseif key == "right" then
        self.cursor = nextCodepoint(self.value, self.cursor)
        return true
    elseif key == "home" then
        self.cursor = 1
        return true
    elseif key == "end" then
        self.cursor = #self.value + 1
        return true
    elseif key == "return" or key == "kpenter" then
        if self.on_submit then self.on_submit(self.value, self) end
        return true
    elseif key == "escape" and self.on_cancel then
        self.on_cancel(self)
        return true
    end
    return false
end

function EditorTextInput:onTextInput(text)
    local cursor = clampCursor(self.value, self.cursor)
    local new_cursor = cursor + #text
    self:setValue(self.value:sub(1, cursor - 1) .. text .. self.value:sub(cursor))
    self.cursor = clampCursor(self.value, new_cursor)
    return true
end

function EditorTextInput:drawSelf()
    self.cursor = clampCursor(self.value, self.cursor)
    local font = self.font or EditorFont.get(16)
    love.graphics.setFont(font)
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    love.graphics.setColor(self.focused and 0.55 or 0.30, self.focused and 0.65 or 0.30, self.focused and 0.85 or 0.34, 1)
    love.graphics.rectangle("line", 0.5, 0.5, self.width - 1, self.height - 1)

    local value = self.value
    if value == "" and not self.focused then
        love.graphics.setColor(0.55, 0.55, 0.58, 1)
        value = self.placeholder
    else
        love.graphics.setColor(0.90, 0.90, 0.92, 1)
    end
    local text_y = math.floor((self.height - font:getHeight()) / 2)
    love.graphics.print(value, self.padding, text_y)
    if self.focused and math.floor(Kristal.getTime() * 2) % 2 == 0 then
        local cursor_x = self.padding + font:getWidth(self.value:sub(1, self.cursor - 1))
        love.graphics.line(cursor_x, 4, cursor_x, self.height - 4)
    end
end

return EditorTextInput
