---@class EditorTilePalette : EditorControl
---@overload fun(editor: table, options?: table): EditorTilePalette
local EditorTilePalette, super = Class(EditorControl)

function EditorTilePalette:init(editor, options)
    options = options or {}
    super.init(self, 0, 0, 500, 220)
    self.editor = editor
    self.show_tools = options.show_tools ~= false
    self.on_selection = options.on_selection
    self.document = nil
    self.scroll_row = 0
    self.scroll_column = 0
    self.random_mode = false
    self.selection_start = nil
    self.selection_end = nil
    self.stamp = {}
    self.clip = true
    self.random_toggle = self:addChild(EditorCheckbox("Random", false, function(value) self.random_mode = value end))
    self.flip_x_button = self:addChild(EditorButton("Flip X", function() self:flipStamp(true) end))
    self.flip_y_button = self:addChild(EditorButton("Flip Y", function() self:flipStamp(false) end))
    self.rotate_button = self:addChild(EditorButton("Rotate", function() self:rotateStamp() end))
    self.scrollbar = self:addChild(EditorScrollbar({ width = 12,
        on_changed = function(value) self.scroll_row = self:getMaxScroll() * value end }))
    self.horizontal_scrollbar = self:addChild(EditorScrollbar({ height = 12, horizontal = true,
        on_changed = function(value) self.scroll_column = self:getMaxHorizontalScroll() * value end }))
    self.random_toggle.visible = self.show_tools
    self.flip_x_button.visible = self.show_tools
    self.flip_y_button.visible = self.show_tools
    self.rotate_button.visible = self.show_tools
end

function EditorTilePalette:getContentTop()
    return self.show_tools and 40 or 4
end

function EditorTilePalette:setTilesetDocument(document)
    if self.document == document then return end
    self.document = document
    self.scroll_row, self.scroll_column = 0, 0
    self.selection_start, self.selection_end = nil, nil
    self.stamp = {}
    if document and document:getTileCount() > 0 then self:setSelection(0, 0) end
end

function EditorTilePalette:getColumns()
    return self.document and self.document:getColumns() or 1
end

function EditorTilePalette:getCellSize()
    if not self.document then return 40, 40 end
    return self.document:getPaletteTileSize()
end

function EditorTilePalette:getVisibleColumns()
    local cell_width = self:getCellSize()
    return math.max(1, math.floor(math.max(0, self.width - 20) / cell_width))
end

function EditorTilePalette:getMaxHorizontalScroll()
    return math.max(0, self:getColumns() - self:getVisibleColumns())
end

function EditorTilePalette:getRowCount()
    local count = self.document and self.document:getTileCount() or 0
    return math.ceil(count / self:getColumns())
end

function EditorTilePalette:getVisibleRows()
    local _, cell_height = self:getCellSize()
    local horizontal_height = self:getMaxHorizontalScroll() > 0 and 12 or 0
    return math.max(1, math.floor(math.max(0,
        self.height - self:getContentTop() - 4 - horizontal_height) / cell_height))
end

function EditorTilePalette:getMaxScroll()
    return math.max(0, self:getRowCount() - self:getVisibleRows())
end

function EditorTilePalette:getTileAt(x, y)
    local content_top = self:getContentTop()
    if not self.document or y < content_top then return nil end
    local cell_width, cell_height = self:getCellSize()
    local column = math.floor((x - 4) / cell_width + self.scroll_column)
    local row = math.floor((y - content_top) / cell_height + self.scroll_row)
    if x >= self.width - 12 or column < 0 or column >= self:getColumns() or row < 0 then return nil end
    local id = row * self:getColumns() + column
    return id < self.document:getTileCount() and id or nil
end

function EditorTilePalette:setSelection(first, last, notify)
    if first == nil then return false end
    last = last or first
    self.selection_start, self.selection_end = first, last
    local columns = self:getColumns()
    local first_x, first_y = first % columns, math.floor(first / columns)
    local last_x, last_y = last % columns, math.floor(last / columns)
    local min_x, max_x = math.min(first_x, last_x), math.max(first_x, last_x)
    local min_y, max_y = math.min(first_y, last_y), math.max(first_y, last_y)
    self.stamp = {}
    for row = min_y, max_y do
        local stamp_row = {}
        for column = min_x, max_x do
            local id = row * columns + column
            table.insert(stamp_row, id < self.document:getTileCount() and id or false)
        end
        table.insert(self.stamp, stamp_row)
    end
    local tile = self.document:getTile(last)
    if tile and notify ~= false then
        self.editor:setSelectedTile(tile)
        if self.on_selection then self.on_selection(tile, self) end
    end
    return true
end

function EditorTilePalette:setSelectedTile(tile)
    if not tile or tile.document ~= self.document then return false end
    if self.selection_start == tile.id and self.selection_end == tile.id then return true end
    return self:setSelection(tile.id, tile.id, false)
end

function EditorTilePalette:getStamp()
    return TableUtils.copy(self.stamp, true)
end

function EditorTilePalette:getRandomTile()
    local weighted, total = {}, 0
    for _, row in ipairs(self.stamp) do
        for _, id in ipairs(row) do
            if id ~= false then
                local weight = math.max(0, self.document:getTileProbability(id) or 1)
                total = total + weight
                table.insert(weighted, { id = id, limit = total })
            end
        end
    end
    if total <= 0 then return nil end
    local choice = love.math.random() * total
    for _, entry in ipairs(weighted) do if choice <= entry.limit then return entry.id end end
    return weighted[#weighted] and weighted[#weighted].id
end

function EditorTilePalette:getPaintTile(column, row)
    if self.random_mode then return self:getRandomTile() end
    if #self.stamp == 0 then return nil end
    local stamp_row = self.stamp[(row % #self.stamp) + 1]
    return stamp_row and stamp_row[(column % #stamp_row) + 1] or nil
end

function EditorTilePalette:flipStamp(horizontal)
    if horizontal then
        for _, row in ipairs(self.stamp) do
            local reversed = {}
            for index = #row, 1, -1 do table.insert(reversed, row[index]) end
            for index, value in ipairs(reversed) do row[index] = value end
        end
    else
        local reversed = {}
        for index = #self.stamp, 1, -1 do table.insert(reversed, self.stamp[index]) end
        self.stamp = reversed
    end
end

function EditorTilePalette:rotateStamp()
    local result = {}
    local height, width = #self.stamp, self.stamp[1] and #self.stamp[1] or 0
    for x = 1, width do
        result[x] = {}
        for y = height, 1, -1 do table.insert(result[x], self.stamp[y][x]) end
    end
    self.stamp = result
end

function EditorTilePalette:onMousePressed(x, y, button)
    if button ~= 1 then return false end
    local id = self:getTileAt(x, y)
    if id == nil then return false end
    self.drag_selecting = true
    self:setSelection(id, id)
    return true
end

function EditorTilePalette:onMouseMoved(x, y)
    if not self.drag_selecting then return false end
    local id = self:getTileAt(x, y)
    if id ~= nil then self:setSelection(self.selection_start, id) end
    return true
end

function EditorTilePalette:onMouseReleased(_, _, button)
    if button ~= 1 or not self.drag_selecting then return false end
    self.drag_selecting = false
    return true
end

function EditorTilePalette:onWheelMoved(x, y)
    if Input.keyDown("shift") or x ~= 0 then
        local movement = x ~= 0 and x or y
        self.scroll_column = MathUtils.clamp(self.scroll_column - movement * 2,
            0, self:getMaxHorizontalScroll())
    else
        self.scroll_row = MathUtils.clamp(self.scroll_row - y * 2, 0, self:getMaxScroll())
    end
    return true
end

function EditorTilePalette:update(dt)
    if self.show_tools then
        self.random_toggle:setBounds(8, 7, 92, 28)
        self.flip_x_button:setBounds(108, 7, 68, 28)
        self.flip_y_button:setBounds(182, 7, 68, 28)
        self.rotate_button:setBounds(256, 7, 68, 28)
    end
    local cell_width, cell_height = self:getCellSize()
    self.scroll_y = self.scroll_row * cell_height
    self.scroll_row = MathUtils.clamp(self.scroll_row, 0, self:getMaxScroll())
    self.scroll_column = MathUtils.clamp(self.scroll_column, 0, self:getMaxHorizontalScroll())
    local rows = self:getRowCount()
    self.scrollbar.page = rows == 0 and 1 or MathUtils.clamp(self:getVisibleRows() / rows, 0, 1)
    local maximum = self:getMaxScroll()
    self.scrollbar.value = maximum == 0 and 0 or self.scroll_row / maximum
    local horizontal_visible = self:getMaxHorizontalScroll() > 0
    self.horizontal_scrollbar.visible = horizontal_visible
    local content_top = self:getContentTop()
    self.scrollbar:setBounds(self.width - 12, content_top, 12,
        math.max(0, self.height - content_top - (horizontal_visible and 12 or 0)))
    if horizontal_visible then
        local visible_columns = self:getVisibleColumns()
        self.horizontal_scrollbar.page = MathUtils.clamp(visible_columns / self:getColumns(), 0, 1)
        local horizontal_maximum = self:getMaxHorizontalScroll()
        self.horizontal_scrollbar.value = horizontal_maximum == 0 and 0
            or self.scroll_column / horizontal_maximum
        self.horizontal_scrollbar:setBounds(4, self.height - 12,
            math.max(0, self.width - 16), 12)
    end
    super.update(self, dt)
end

function EditorTilePalette:drawSelf()
    Draw.setColor(0.065, 0.065, 0.075, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    if not self.document then
        Draw.setColor(0.55, 0.55, 0.58, 1)
        love.graphics.print("No tileset selected", 8, self:getContentTop() + 8)
        return
    end
    local columns = self:getColumns()
    local cell_width, cell_height = self:getCellSize()
    local first_row = math.floor(self.scroll_row)
    local last_row = math.min(self:getRowCount() - 1, first_row + self:getVisibleRows())
    local first_column = math.floor(self.scroll_column)
    local last_column = math.min(columns - 1, first_column + self:getVisibleColumns())
    local selection = {}
    for _, row in ipairs(self.stamp) do for _, id in ipairs(row) do if id ~= false then selection[id] = true end end end
    for row = first_row, last_row do
        for column = first_column, last_column do
            local id = row * columns + column
            if id < self.document:getTileCount() then
                local x = 4 + (column - self.scroll_column) * cell_width
                local y = self:getContentTop() + (row - self.scroll_row) * cell_height
                Draw.setColor(0.11, 0.11, 0.13, 1)
                love.graphics.rectangle("fill", x, y, cell_width, cell_height)
                if self.document.tileset then
                    Draw.setColor(1, 1, 1, 1)
                    self.document.tileset:drawGridTile(id, x, y, cell_width, cell_height)
                else
                    Draw.setColor(0.78, 0.78, 0.82, 1)
                    love.graphics.print(tostring(id), x + 4, y + 3)
                end
                if selection[id] then
                    Draw.setColor(0.20, 0.48, 0.88, 0.42)
                    love.graphics.rectangle("fill", x, y, cell_width, cell_height)
                    Draw.setColor(0.48, 0.76, 1, 1)
                    love.graphics.rectangle("line", x + 0.5, y + 0.5, cell_width - 1, cell_height - 1)
                else
                    Draw.setColor(0.26, 0.26, 0.30, 0.7)
                    love.graphics.rectangle("line", x + 0.5, y + 0.5, cell_width - 1, cell_height - 1)
                end
            end
        end
    end
end

return EditorTilePalette
