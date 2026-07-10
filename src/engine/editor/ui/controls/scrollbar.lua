---@class EditorScrollbar : EditorControl
---@overload fun(options?: table): EditorScrollbar
local EditorScrollbar, super = Class(EditorControl)

function EditorScrollbar:init(options)
    options = options or {}
    super.init(self, options.x, options.y, options.width or 12, options.height or 100)
    self.value = MathUtils.clamp(options.value or 0, 0, 1)
    self.page = MathUtils.clamp(options.page or 0.2, 0, 1)
    self.on_changed = options.on_changed
    self.cursor_type = "select"
    self.dragging = false
    self.drag_offset = 0
end

function EditorScrollbar:setValue(value, silent)
    value = MathUtils.clamp(value or 0, 0, 1)
    if self.value == value then return end
    self.value = value
    if not silent and self.on_changed then self.on_changed(value, self) end
end

function EditorScrollbar:getThumbRect()
    local thumb_h = math.max(18, self.height * self.page)
    thumb_h = math.min(self.height, thumb_h)
    local travel = math.max(0, self.height - thumb_h)
    return 0, travel * self.value, self.width, thumb_h
end

function EditorScrollbar:onMousePressed(_, y, button)
    if button ~= 1 then return false end
    local _, thumb_y, _, thumb_h = self:getThumbRect()
    if y >= thumb_y and y < thumb_y + thumb_h then
        self.drag_offset = y - thumb_y
    else
        self.drag_offset = thumb_h / 2
        self:setValue((y - self.drag_offset) / math.max(1, self.height - thumb_h))
    end
    self.dragging = true
    return true
end

function EditorScrollbar:onMouseMoved(_, y)
    if not self.dragging then return end
    local _, _, _, thumb_h = self:getThumbRect()
    self:setValue((y - self.drag_offset) / math.max(1, self.height - thumb_h))
end

function EditorScrollbar:onMouseReleased(_, _, button)
    if button == 1 and self.dragging then
        self.dragging = false
        return true
    end
end

function EditorScrollbar:onWheelMoved(_, y)
    self:setValue(self.value - y * math.max(0.03, self.page * 0.25))
    return true
end

function EditorScrollbar:drawSelf()
    love.graphics.setColor(0.09, 0.09, 0.10, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    local thumb_x, thumb_y, thumb_w, thumb_h = self:getThumbRect()
    love.graphics.setColor(self.dragging and 0.62 or 0.42, self.dragging and 0.65 or 0.44, self.dragging and 0.72 or 0.50, 1)
    love.graphics.rectangle("fill", thumb_x + 2, thumb_y + 2, thumb_w - 4, math.max(1, thumb_h - 4), 2)
end

return EditorScrollbar
