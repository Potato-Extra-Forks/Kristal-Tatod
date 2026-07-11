---@class EditorMapView : EditorGameView
---@overload fun(editor?: table, document?: EditorMapDocument): EditorMapView
local EditorMapView, super = Class(EditorGameView)

function EditorMapView:init(editor, document)
    super.init(self, editor, document)
    self.is_game_preview = false
    self.is_map_view = true
    self.explosions = {}
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

function EditorMapView:addExplosion(world_x, world_y)
    table.insert(self.explosions, { x = world_x, y = world_y, time = 0 })
    Assets.playSound("badexplosion")
end

function EditorMapView:update(dt)
    for index = #self.explosions, 1, -1 do
        local effect = self.explosions[index]
        effect.time = effect.time + dt
        if effect.time >= 0.8 then table.remove(self.explosions, index) end
    end
    super.update(self, dt)
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
    self:drawObjectLinks()
    self:drawSelectedObject()
    self:drawSelectionMarquee()
    self:drawShapePreview()
    self:drawExplosions()
    love.graphics.pop()
end

local function drawDashedLine(x1, y1, x2, y2, dash)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return end
    local nx, ny = dx / length, dy / length
    for distance = 0, length, dash * 2 do
        local finish = math.min(length, distance + dash)
        love.graphics.line(x1 + nx * distance, y1 + ny * distance,
            x1 + nx * finish, y1 + ny * finish)
    end
end

function EditorMapView:drawObjectLinks()
    love.graphics.setLineWidth(2 / self.view_zoom)
    Draw.setColor(0.45, 0.78, 1, 0.9)
    for _, selection in ipairs(self.editor and self.editor:getSelectedMapObjects(self.document) or {}) do
        local x1, y1 = self.document:getObjectWorldCenter(selection)
        for _, target in ipairs(self.document:getObjectLinks(selection)) do
            local x2, y2 = self.document:getObjectWorldCenter(target)
            drawDashedLine(x1, y1, x2, y2, 8 / self.view_zoom)
        end
    end
    local selection = self.editor and self.editor.selected_map_object
    local drag = self.editor and self.editor.object_reference_drag
    if selection and selection.document == self.document and drag and drag.source == selection then
        local x1, y1 = self.document:getObjectWorldCenter(selection)
        local mouse_x, mouse_y = love.mouse.getPosition()
        local local_x, local_y = self:toLocal(mouse_x, mouse_y)
        local x2, y2 = self:getMapCoordinates(local_x, local_y)
        drawDashedLine(x1, y1, x2, y2, 8 / self.view_zoom)
    end
end

function EditorMapView:getSelectionBounds(selections)
    selections = selections or (self.editor and self.editor:getSelectedMapObjects(self.document)) or {}
    local min_x, min_y, max_x, max_y
    for _, selection in ipairs(selections) do
        local left, top, right, bottom = self.document:getObjectWorldBounds(selection)
        min_x, min_y = min_x and math.min(min_x, left) or left, min_y and math.min(min_y, top) or top
        max_x, max_y = max_x and math.max(max_x, right) or right, max_y and math.max(max_y, bottom) or bottom
    end
    return min_x, min_y, max_x, max_y
end

function EditorMapView:getRotationHandle(selections)
    local min_x, min_y, max_x = self:getSelectionBounds(selections)
    if not min_x then return nil end
    return (min_x + max_x) / 2, min_y - 22 / self.view_zoom
end

function EditorMapView:isRotationHandleAt(world_x, world_y)
    local selections = self.editor and self.editor:getSelectedMapObjects(self.document) or {}
    if #selections == 0 then return false end
    local handle_x, handle_y = self:getRotationHandle(selections)
    local distance = 9 / self.view_zoom
    return math.abs(world_x - handle_x) <= distance and math.abs(world_y - handle_y) <= distance
end

function EditorMapView:drawSelectedObject()
    local selections = self.editor and self.editor:getSelectedMapObjects(self.document) or {}
    if #selections == 0 then return end
    love.graphics.setLineWidth(2 / self.view_zoom)
    Draw.setColor(1, 0.86, 0.2, 1)
    for _, selection in ipairs(selections) do
        local x, y = self.document:getObjectWorldPosition(selection)
        local width, height = selection.data.width or 0, selection.data.height or 0
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.rotate(math.rad(selection.data.rotation or 0))
        if width == 0 and height == 0 then
            love.graphics.circle("line", 0, 0, 8 / self.view_zoom)
        else
            love.graphics.rectangle("line", 0, 0, width, height)
            if #selections == 1 then
                local handle = 7 / self.view_zoom
                love.graphics.rectangle("fill", width - handle / 2, height - handle / 2, handle, handle)
            end
        end
        love.graphics.pop()
    end
    local min_x, min_y, max_x, max_y = self:getSelectionBounds(selections)
    if #selections > 1 then
        Draw.setColor(1, 0.86, 0.2, 0.7)
        love.graphics.rectangle("line", min_x, min_y, max_x - min_x, max_y - min_y)
    end
    local handle_x, handle_y = self:getRotationHandle(selections)
    Draw.setColor(1, 0.86, 0.2, 0.8)
    love.graphics.line((min_x + max_x) / 2, min_y, handle_x, handle_y)
    love.graphics.circle("fill", handle_x, handle_y, 5 / self.view_zoom)
end

function EditorMapView:drawSelectionMarquee()
    local drag = self.selection_marquee
    if not drag then return end
    local x, y = math.min(drag.start_x, drag.current_x), math.min(drag.start_y, drag.current_y)
    local width, height = math.abs(drag.current_x - drag.start_x), math.abs(drag.current_y - drag.start_y)
    Draw.setColor(0.3, 0.62, 1, 0.16)
    love.graphics.rectangle("fill", x, y, width, height)
    Draw.setColor(0.48, 0.76, 1, 0.95)
    love.graphics.setLineWidth(1 / self.view_zoom)
    love.graphics.rectangle("line", x, y, width, height)
end

function EditorMapView:drawShapePreview()
    if self.polygon_build then
        local coordinates = {}
        for _, point in ipairs(self.polygon_build.points) do
            table.insert(coordinates, point.x)
            table.insert(coordinates, point.y)
        end
        if self.polygon_build.current_x then
            table.insert(coordinates, self.polygon_build.current_x)
            table.insert(coordinates, self.polygon_build.current_y)
        end
        love.graphics.setLineWidth(2 / self.view_zoom)
        Draw.setColor(0.48, 0.78, 1, 0.9)
        if #coordinates >= 4 then love.graphics.line(coordinates) end
        return
    end
    local drag = self.shape_drag
    if not drag then return end
    local x, y = math.min(drag.start_x, drag.current_x), math.min(drag.start_y, drag.current_y)
    local width, height = math.abs(drag.current_x - drag.start_x), math.abs(drag.current_y - drag.start_y)
    love.graphics.setLineWidth(2 / self.view_zoom)
    Draw.setColor(0.48, 0.78, 1, 0.9)
    if drag.shape == "ellipse" then
        love.graphics.ellipse("line", x + width / 2, y + height / 2, width / 2, height / 2)
    elseif drag.shape == "line" then
        love.graphics.line(drag.start_x, drag.start_y, drag.current_x, drag.current_y)
    else
        love.graphics.rectangle("line", x, y, width, height)
    end
end

function EditorMapView:finishPolygon()
    local build = self.polygon_build
    self.polygon_build = nil
    if not build or #build.points < 3 then return false end
    local object, layer_or_reason, map_id = self.document:addPolygonObject(build.map_id, build.points)
    if not object then
        self.editor:cancelHistoryTransaction()
        self.editor:addWarning(layer_or_reason, nil, "shape_placement")
        return false
    end
    local selection = self.document:getObjectSelection(map_id, layer_or_reason, object)
    selection.view = self
    self.editor:selectMapObject(selection)
    self.editor:markHistoryChanged()
    self.editor:commitHistoryTransaction()
    return true
end

function EditorMapView:drawExplosions()
    local frames = Assets.getFrames("misc/realistic_explosion")
    if not frames or #frames == 0 then return end
    for _, effect in ipairs(self.explosions) do
        local frame = frames[math.min(#frames, math.floor(effect.time / 0.8 * #frames) + 1)]
        Draw.setColor(1, 1, 1, 1)
        Draw.draw(frame, effect.x, effect.y, 0, 2, 2, frame:getWidth() / 2, frame:getHeight() / 2)
    end
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
    if button == 1 or button == 2 then
        local world_x, world_y = self:getMapCoordinates(x, y)
        local tool = self.editor.active_tool
        if button == 1 and tool == "select" and self:isRotationHandleAt(world_x, world_y) then
            local selections = self.editor:getSelectedMapObjects(self.document)
            local min_x, min_y, max_x, max_y = self:getSelectionBounds(selections)
            local center_x, center_y = (min_x + max_x) / 2, (min_y + max_y) / 2
            local snapshots = {}
            for _, selected in ipairs(selections) do
                local object_x, object_y = self.document:getObjectWorldCenter(selected)
                table.insert(snapshots, {
                    selection = selected,
                    rotation = selected.data.rotation or 0,
                    center_x = object_x,
                    center_y = object_y
                })
            end
            self.rotation_drag = {
                center_x = center_x, center_y = center_y,
                start_angle = math.atan2(world_y - center_y, world_x - center_x),
                snapshots = snapshots
            }
            self.editor:beginHistoryTransaction("Rotate Objects", self.document)
            return true
        end
        local selection = self.document:findObjectAt(world_x, world_y)
        if selection then selection.view = self end
        if button == 2 then
            if selection then
                local global_x, global_y = self:getGlobalPosition()
                return self.editor:openMapObjectContext(selection, global_x + x, global_y + y)
            end
            return false
        end
        if tool == "select" and self.editor.placement_event_id then
            return self.editor:placeEvent(self, self.editor.placement_event_id, world_x, world_y)
        elseif tool == "shape" and self.editor.shape_mode ~= "point"
            and self.editor.shape_mode ~= "polygon" then
            self.shape_drag = { shape = self.editor.shape_mode, start_x = world_x, start_y = world_y,
                current_x = world_x, current_y = world_y }
            self.editor:beginHistoryTransaction("Create Shape", self.document)
            return true
        elseif tool == "shape" and self.editor.shape_mode == "point" then
            local entry = self.document:getMapAt(world_x, world_y) or self.document:getPrimaryMap()
            if not Input.ctrl() then
                world_x = MathUtils.round(world_x / (entry.tile_width or 40)) * (entry.tile_width or 40)
                world_y = MathUtils.round(world_y / (entry.tile_height or 40)) * (entry.tile_height or 40)
            end
            self.editor:beginHistoryTransaction("Create Point", self.document)
            local object, layer_or_reason, map_id = self.document:addShapeObject("point", entry.id, world_x, world_y, 0, 0)
            if not object then
                self.editor:cancelHistoryTransaction()
                self.editor:addWarning(layer_or_reason, nil, "shape_placement")
                return true
            end
            local point_selection = self.document:getObjectSelection(map_id, layer_or_reason, object)
            point_selection.view = self
            self.editor:selectMapObject(point_selection)
            self.editor:markHistoryChanged()
            self.editor:commitHistoryTransaction()
            return true
        elseif tool == "shape" and self.editor.shape_mode == "polygon" then
            local entry = self.document:getMapAt(world_x, world_y) or self.document:getPrimaryMap()
            if not Input.ctrl() then
                world_x = MathUtils.round(world_x / (entry.tile_width or 40)) * (entry.tile_width or 40)
                world_y = MathUtils.round(world_y / (entry.tile_height or 40)) * (entry.tile_height or 40)
            end
            if not self.polygon_build then
                self.polygon_build = { map_id = entry.id, points = {} }
                self.editor:beginHistoryTransaction("Create Polygon", self.document)
            end
            table.insert(self.polygon_build.points, { x = world_x, y = world_y })
            if presses and presses >= 2 then return self:finishPolygon() end
            return true
        elseif tool == "eraser" then
            self.editor:selectMapObject(selection)
            return selection and self.editor:deleteSelectedMapObject(false) or true
        end
        if selection and tool == "select" then
            if Input.shift() then
                self.editor:selectMapObject(selection, true)
                return true
            elseif not self.editor:isMapObjectSelected(selection) then
                self.editor:selectMapObject(selection)
            end
            local selections = self.editor:getSelectedMapObjects(self.document)
            local object_x, object_y = self.document:getObjectWorldPosition(selection)
            local width, height = selection.data.width or 0, selection.data.height or 0
            local rotation = -math.rad(selection.data.rotation or 0)
            local dx, dy = world_x - object_x, world_y - object_y
            local local_x = dx * math.cos(rotation) - dy * math.sin(rotation)
            local local_y = dx * math.sin(rotation) + dy * math.cos(rotation)
            local handle_distance = 10 / self.view_zoom
            local resize = #selections == 1 and (width ~= 0 or height ~= 0)
                and math.abs(local_x - width) <= handle_distance
                and math.abs(local_y - height) <= handle_distance
            local snapshots = {}
            for _, selected in ipairs(selections) do
                table.insert(snapshots, {
                    selection = selected,
                    x = selected.data.x or 0,
                    y = selected.data.y or 0,
                    width = selected.data.width or 0,
                    height = selected.data.height or 0
                })
            end
            self.object_drag = {
                selection = selection,
                selections = snapshots,
                resize = resize,
                start_x = world_x,
                start_y = world_y,
                object_x = selection.data.x or 0,
                object_y = selection.data.y or 0,
                width = selection.data.width or 0,
                height = selection.data.height or 0
            }
            self.editor:beginHistoryTransaction(resize and "Resize Object" or "Move Objects", self.document)
            return true
        end
        if not selection and tool == "select" then
            local entry = self.document:getMapAt(world_x, world_y)
            local edge = 7 / self.view_zoom
            local on_edge = entry and (math.abs(world_x - entry.x) <= edge
                or math.abs(world_x - entry.x - entry.width) <= edge
                or math.abs(world_y - entry.y) <= edge
                or math.abs(world_y - entry.y - entry.height) <= edge)
            if on_edge then
                self.map_drag = { entry = entry, start_x = world_x, start_y = world_y,
                    entry_x = entry.x, entry_y = entry.y }
                self.editor:beginHistoryTransaction("Move Map", self.document)
                return true
            end
            self.selection_marquee = {
                start_x = world_x, start_y = world_y,
                current_x = world_x, current_y = world_y,
                additive = Input.shift()
            }
            return true
        end
        if tool == "select" or tool == "link" then return true end
    end
    return super.onMousePressed(self, x, y, button, presses)
end

function EditorMapView:onMouseMoved(x, y, dx, dy)
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:onMouseMoved(x, y, dx, dy)
    end
    local world_x, world_y = self:getMapCoordinates(x, y)
    if self.polygon_build then
        self.polygon_build.current_x, self.polygon_build.current_y = world_x, world_y
        return true
    end
    if self.shape_drag then
        self.shape_drag.current_x, self.shape_drag.current_y = world_x, world_y
        return true
    end
    if self.selection_marquee then
        self.selection_marquee.current_x, self.selection_marquee.current_y = world_x, world_y
        return true
    end
    if self.rotation_drag then
        local drag = self.rotation_drag
        local angle = math.atan2(world_y - drag.center_y, world_x - drag.center_x)
        local delta = math.deg(angle - drag.start_angle)
        if not Input.ctrl() then delta = MathUtils.round(delta / 15) * 15 end
        local radians = math.rad(delta)
        local invalidated = {}
        for _, snapshot in ipairs(drag.snapshots) do
            local selection = snapshot.selection
            local relative_x, relative_y = snapshot.center_x - drag.center_x, snapshot.center_y - drag.center_y
            local center_x = drag.center_x + relative_x * math.cos(radians) - relative_y * math.sin(radians)
            local center_y = drag.center_y + relative_x * math.sin(radians) + relative_y * math.cos(radians)
            local rotation = snapshot.rotation + delta
            local object_rotation = math.rad(rotation)
            local half_width, half_height = (selection.data.width or 0) / 2, (selection.data.height or 0) / 2
            local top_left_x = center_x - half_width * math.cos(object_rotation) + half_height * math.sin(object_rotation)
            local top_left_y = center_y - half_width * math.sin(object_rotation) - half_height * math.cos(object_rotation)
            selection.data.x = top_left_x - selection.entry.x - (selection.layer.offsetx or 0)
            selection.data.y = top_left_y - selection.entry.y - (selection.layer.offsety or 0)
            selection.data.rotation = rotation % 360
            invalidated[selection.map_id] = true
        end
        for map_id in pairs(invalidated) do self.document:invalidatePreview(map_id) end
        self.editor:markHistoryChanged()
        return true
    end
    if self.object_drag then
        local drag = self.object_drag
        local data = drag.selection.data
        local delta_x, delta_y = world_x - drag.start_x, world_y - drag.start_y
        local tile_width = drag.selection.entry.tile_width or 40
        local tile_height = drag.selection.entry.tile_height or 40
        local function snap(value, size)
            return Input.ctrl() and value or MathUtils.round(value / size) * size
        end
        if drag.resize then
            data.width = math.max(0, snap(drag.width + delta_x, tile_width))
            data.height = math.max(0, snap(drag.height + delta_y, tile_height))
        else
            if not Input.ctrl() then
                delta_x = MathUtils.round(delta_x / tile_width) * tile_width
                delta_y = MathUtils.round(delta_y / tile_height) * tile_height
            end
            local invalidated = {}
            for _, snapshot in ipairs(drag.selections) do
                snapshot.selection.data.x = snapshot.x + delta_x
                snapshot.selection.data.y = snapshot.y + delta_y
                invalidated[snapshot.selection.map_id] = true
            end
            for map_id in pairs(invalidated) do self.document:invalidatePreview(map_id) end
            self.editor:markHistoryChanged()
            return true
        end
        self.document:invalidatePreview(drag.selection.map_id)
        self.editor:markHistoryChanged()
        return true
    end
    if self.map_drag then
        local drag = self.map_drag
        local x2, y2 = drag.entry_x + world_x - drag.start_x, drag.entry_y + world_y - drag.start_y
        if not Input.ctrl() then
            x2 = MathUtils.round(x2 / (drag.entry.tile_width or 40)) * (drag.entry.tile_width or 40)
            y2 = MathUtils.round(y2 / (drag.entry.tile_height or 40)) * (drag.entry.tile_height or 40)
        end
        self.document:setMapPosition(drag.entry.id, x2, y2)
        self.editor:markHistoryChanged()
        return true
    end
    return super.onMouseMoved(self, x, y, dx, dy)
end

function EditorMapView:onMouseReleased(x, y, button, presses)
    if self.editor and self.editor.live_document == self.document then
        return self.editor.game_preview:onMouseReleased(x, y, button, presses)
    end
    if button == 1 and self.shape_drag then
        local drag = self.shape_drag
        self.shape_drag = nil
        local x1, y1 = math.min(drag.start_x, drag.current_x), math.min(drag.start_y, drag.current_y)
        local x2, y2 = math.max(drag.start_x, drag.current_x), math.max(drag.start_y, drag.current_y)
        local entry = self.document:getMapAt(x1, y1) or self.document:getPrimaryMap()
        local tile_width, tile_height = entry.tile_width or 40, entry.tile_height or 40
        if not Input.ctrl() then
            x1, y1 = MathUtils.round(x1 / tile_width) * tile_width, MathUtils.round(y1 / tile_height) * tile_height
            x2, y2 = MathUtils.round(x2 / tile_width) * tile_width, MathUtils.round(y2 / tile_height) * tile_height
        end
        local object, layer_or_reason, map_id = self.document:addShapeObject(drag.shape, entry.id, x1, y1, x2 - x1, y2 - y1)
        if object then
            local selection = self.document:getObjectSelection(map_id, layer_or_reason, object)
            selection.view = self
            self.editor:selectMapObject(selection)
            self.editor:markHistoryChanged()
            self.editor:commitHistoryTransaction()
        else
            self.editor:cancelHistoryTransaction()
            self.editor:addWarning(layer_or_reason, nil, "shape_placement")
        end
        return true
    end
    if button == 1 and self.object_drag then
        self.object_drag = nil
        self.editor:commitHistoryTransaction()
        self.editor:selectMapObjects(self.editor:getSelectedMapObjects(), self.editor.selected_map_object)
        return true
    end
    if button == 1 and self.rotation_drag then
        self.rotation_drag = nil
        self.editor:commitHistoryTransaction()
        self.editor:selectMapObjects(self.editor:getSelectedMapObjects(), self.editor.selected_map_object)
        return true
    end
    if button == 1 and self.selection_marquee then
        local drag = self.selection_marquee
        self.selection_marquee = nil
        local selections = self.document:findObjectsInRect(
            drag.start_x, drag.start_y, drag.current_x, drag.current_y)
        for _, selection in ipairs(selections) do selection.view = self end
        if drag.additive then
            local combined = self.editor:getSelectedMapObjects()
            for _, selection in ipairs(selections) do table.insert(combined, selection) end
            self.editor:selectMapObjects(combined, selections[1] or self.editor.selected_map_object)
        else
            self.editor:selectMapObjects(selections, selections[1])
        end
        return true
    end
    if button == 1 and self.map_drag then
        self.map_drag = nil
        self.editor:commitHistoryTransaction()
        return true
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
    if self.object_drag or self.map_drag or self.dragging_canvas then return "grab" end
    if self.rotation_drag then return "resize_all" end
    if self.editor and self.editor.active_tool == "link" then return "link" end
    if self.editor and (self.editor.placement_event_id or self.editor.active_tool == "shape") then
        return "crosshair"
    end
    local world_x, world_y = self:getMapCoordinates(x, y)
    if self.editor and self.editor.active_tool == "select" and self:isRotationHandleAt(world_x, world_y) then
        return "resize_all"
    end
    local selection = self.document:findObjectAt(world_x, world_y)
    if selection then
        local selected = self.editor and self.editor.selected_map_object
        local selections = self.editor and self.editor:getSelectedMapObjects(self.document) or {}
        if #selections == 1 and selected and selected.data == selection.data then
            local object_x, object_y = self.document:getObjectWorldPosition(selection)
            local width, height = selection.data.width or 0, selection.data.height or 0
            local rotation = -math.rad(selection.data.rotation or 0)
            local dx, dy = world_x - object_x, world_y - object_y
            local local_x = dx * math.cos(rotation) - dy * math.sin(rotation)
            local local_y = dx * math.sin(rotation) + dy * math.cos(rotation)
            local distance = 10 / self.view_zoom
            if (width ~= 0 or height ~= 0) and math.abs(local_x - width) <= distance
                and math.abs(local_y - height) <= distance then
                return "resize_diag_l"
            end
        end
        return "select"
    end
    return super.getCursorType(self, x, y)
end

function EditorMapView:onKeyPressed(key, is_repeat)
    if not is_repeat and key == "escape" and self.editor and self.editor.placement_event_id then
        self.editor.placement_event_id = nil
        return true
    end
    if not is_repeat and self.polygon_build then
        if key == "escape" then
            self.polygon_build = nil
            self.editor:cancelHistoryTransaction()
            return true
        end
        if key == "return" or key == "kpenter" then return self:finishPolygon() end
    end
    return super.onKeyPressed(self, key, is_repeat)
end

return EditorMapView
