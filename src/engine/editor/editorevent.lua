---@class EditorEvent : Class
---@overload fun(data?: table, options?: table): EditorEvent
local EditorEvent = Class()

function EditorEvent:registerProperty(id, property_type, options)
    return self.property_set:registerProperty(id, property_type, options)
end

function EditorEvent:registerPropertyGroup(id, options)
    return self.property_set:registerGroup(id, options)
end

--- Editor events are deliberately plain classes. They are rendered directly
--- by map previews and never receive a parent, stage, World, or Game instance.
function EditorEvent:init(data, options)
    data = data or {}
    options = options or {}
    self.data = data
    data.properties = data.properties or {}
    data.__editor_property_types = data.__editor_property_types or {}
    self.properties = data.properties
    self.property_types = data.__editor_property_types
    self.property_set = EditorPropertySet(data.properties, data.__editor_property_types)
    self:registerProperty("uid", "string", { name = "Unique ID" })
    self:registerProperty("cond", "string", { name = "Load Condition" })
    self:registerProperty("flagcheck", "string", { name = "Load Flag" })
    self:registerProperty("flagvalue", "value", { name = "Load Flag Value" })
    self.id = options.event_id
    self.layer = options.depth or 0
    self.layer_uid = options.layer_uid
    self.layer_type = options.layer_type
    self.layer_color = options.layer_color or { 1, 1, 1, 1 }
    self.x = (data.x or 0) + (options.offset_x or 0)
    self.y = (data.y or 0) + (options.offset_y or 0)
    self.width = data.width or 0
    self.height = data.height or 0
    self.rotation = math.rad(data.rotation or 0)
    self.visible = data.visible ~= false
    self.sprite = self:getPreviewSprite(options.sprite)
end

function EditorEvent:getPreviewSprite(sprite)
    local properties = self.data.properties or {}
    sprite = sprite or self.editor_sprite
    if not sprite and self.sprite_property then sprite = properties[self.sprite_property] end
    if not sprite and self.getEditorSprite then
        local success, result = pcall(self.getEditorSprite, self, self.data)
        if success then sprite = result end
    end
    return sprite
end

function EditorEvent:getTexture()
    local frames = self.sprite and Assets.getFramesOrTexture(self.sprite)
    if frames and frames[1] then return frames[1], false end
    if self.width == 0 and self.height == 0 then
        return Assets.getTexture("editor/marker"), true
    end
    return nil, false
end

function EditorEvent:draw(alpha)
    if not self.visible then return end
    alpha = alpha or 1
    local texture, marker = self:getTexture()
    if not texture then return end
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.rotation)
    if marker then
        local color = self.layer_color
        Draw.setColor(color[1] or 1, color[2] or 1, color[3] or 1, (color[4] or 1) * alpha)
    else
        Draw.setColor(1, 1, 1, alpha)
    end
    if marker then
        Draw.draw(texture, 0, 0, 0, 2, 2, texture:getWidth() / 2, texture:getHeight())
    elseif self.width ~= 0 or self.height ~= 0 then
        Draw.draw(texture, self.width / 2, self.height / 2, 0, 2, 2,
            texture:getWidth() / 2, texture:getHeight() / 2)
    else
        Draw.draw(texture, 0, 0, 0, 2, 2)
    end
    love.graphics.pop()
    Draw.setColor(1, 1, 1, 1)
end

function EditorEvent:drawBounds(alpha)
    if self.width == 0 and self.height == 0 then return end
    alpha = alpha or 1
    local previous_width = love.graphics.getLineWidth()
    local color = self.layer_color
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.rotation)
    love.graphics.setLineWidth(1)
    Draw.setColor(color[1] or 1, color[2] or 1, color[3] or 1,
        math.min(color[4] or 1, 0.9) * alpha)
    love.graphics.rectangle("line", 0, 0, self.width, self.height)
    love.graphics.pop()
    love.graphics.setLineWidth(previous_width)
    Draw.setColor(1, 1, 1, 1)
end

return EditorEvent
