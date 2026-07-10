---@class EditorMapView : EditorGameView
---@overload fun(editor?: table, document?: EditorMapDocument): EditorMapView
local EditorMapView, super = Class(EditorGameView)

function EditorMapView:init(editor, document)
    super.init(self, editor, document)
    self.is_game_preview = false
    self.is_map_view = true
end

function EditorMapView:setCanvas() end
function EditorMapView:setTileEditingMode() end

function EditorMapView:getDocumentBounds()
    local primary = self:getPrimaryEntry()
    if not primary then return 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT end
    local min_x, min_y = primary.x, primary.y
    local max_x = primary.x + (primary.width or SCREEN_WIDTH)
    local max_y = primary.y + (primary.height or SCREEN_HEIGHT)
    for _, entry in ipairs(self.document.maps) do
        min_x = math.min(min_x, entry.x)
        min_y = math.min(min_y, entry.y)
        max_x = math.max(max_x, entry.x + (entry.width or 0))
        max_y = math.max(max_y, entry.y + (entry.height or 0))
    end
    return min_x, min_y, max_x, max_y
end

function EditorMapView:centerCanvas()
    local primary = self:getPrimaryEntry()
    local primary_x, primary_y = primary and primary.x or 0, primary and primary.y or 0
    local min_x, min_y, max_x, max_y = self:getDocumentBounds()
    local width, height = (max_x - min_x) * self.view_zoom, (max_y - min_y) * self.view_zoom
    self:setCanvasPosition((self.width - width) / 2 - (min_x - primary_x) * self.view_zoom,
        (self.height - height) / 2 - (min_y - primary_y) * self.view_zoom)
end

function EditorMapView:getCanvasDisplayCenter()
    local primary = self:getPrimaryEntry()
    return self.canvas_x + (primary and primary.width or SCREEN_WIDTH) * self.view_zoom / 2,
        self.canvas_y + (primary and primary.height or SCREEN_HEIGHT) * self.view_zoom / 2
end

function EditorMapView:getMapCoordinates(x, y)
    local primary = self:getPrimaryEntry()
    return (x - self.canvas_x) / self.view_zoom + (primary and primary.x or 0),
        (y - self.canvas_y) / self.view_zoom + (primary and primary.y or 0)
end

function EditorMapView:drawDocument()
    local document = self.document
    local primary = self:getPrimaryEntry()
    if not document or not primary then return end
    love.graphics.push()
    love.graphics.translate(self.canvas_x, self.canvas_y)
    love.graphics.scale(self.view_zoom, self.view_zoom)
    love.graphics.translate(-primary.x, -primary.y)
    for _, entry in ipairs(document.maps) do
        love.graphics.push()
        love.graphics.translate(entry.x, entry.y)
        document:drawPreview(entry)
        love.graphics.pop()
    end
    love.graphics.setLineWidth(2 / self.view_zoom)
    Draw.setColor(1, 1, 1, 0.4)
    for _, entry in ipairs(document.maps) do
        if entry.width and entry.height then
            Draw.setColor(1, 1, 1, 0.4)
            love.graphics.rectangle("line", entry.x, entry.y, entry.width, entry.height)
            if self.editor and self.editor.show_tile_grid then
                self:drawTileGrid(entry.x, entry.y, entry.width, entry.height,
                    entry.tile_width, entry.tile_height)
            end
        end
    end
    love.graphics.pop()
end

function EditorMapView:drawPreview()
    self:drawDocument()
    self:drawCursorAndCoordinates()
end

function EditorMapView:drawSelf()
    Draw.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    self:drawPreview()
    self:drawScaleReadout()
    Draw.setColor(1, 1, 1, 1)
end

function EditorMapView:onFocus()
    if self.editor and not self.editor.suppress_panel_activation then
        self.editor:activateMapDocument(self.document, { select_panel = false })
    end
end

function EditorMapView:onMousePressed(x, y, button, presses)
    if self.editor and not self.editor.suppress_panel_activation
        and self.editor.active_document ~= self.document then
        self.editor:activateMapDocument(self.document, { select_panel = false })
    end
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:onMousePressed(x, y, button, presses)
    end
    return super.onMousePressed(self, x, y, button, presses)
end

function EditorMapView:onMouseMoved(x, y, dx, dy)
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:onMouseMoved(x, y, dx, dy)
    end
    return super.onMouseMoved(self, x, y, dx, dy)
end

function EditorMapView:onMouseReleased(x, y, button, presses)
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:onMouseReleased(x, y, button, presses)
    end
    return super.onMouseReleased(self, x, y, button, presses)
end

function EditorMapView:onWheelMoved(x, y)
    if self.editor and self.editor.live_document == self.document then
        self.editor:activateMapDocument(self.document, { select_panel = false })
        return self.editor.game_preview:onWheelMoved(x, y)
    end
    return super.onWheelMoved(self, x, y)
end

function EditorMapView:getCursorType(x, y)
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:getCursorType(x, y)
    end
    return super.getCursorType(self, x, y)
end

return EditorMapView
