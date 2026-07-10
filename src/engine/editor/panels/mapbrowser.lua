---@class EditorMapBrowser : EditorControl
---@overload fun(editor: table): EditorMapBrowser
local EditorMapBrowser, super = Class(EditorControl)

local function uniqueName(parent, base)
    local used = {}
    for _, child in ipairs(parent.children) do used[child.name:lower()] = true end
    if not used[base:lower()] then return base end
    local index = 2
    while used[(base .. " " .. index):lower()] do index = index + 1 end
    return base .. " " .. index
end

function EditorMapBrowser:init(editor)
    super.init(self, 0, 0, 240, 400)
    self.editor = editor
    self.search = self:addChild(EditorSearchBar({
        placeholder = "Search maps...",
        on_changed = function(value) self.tree:setFilter(value) end
    }))
    self.new_map_button = self:addChild(EditorButton("New Map", function() self:createMap() end))
    self.new_folder_button = self:addChild(EditorButton("New Folder", function() self:createFolder() end))
    self.tree = self:addChild(EditorTreeList({
        on_activate = function(node) self:activateNode(node) end,
        on_drag_outside = function(node, tree, x, y) self:dropOutside(node, tree, x, y) end,
        on_drag_move = function(node, tree, x, y) self:updateDockPreview(node, tree, x, y) end,
        on_drag_end = function() self.editor.dockspace.dock_preview = nil end,
        on_request_focus = function(control) self.editor.dockspace:setFocus(control) end
    }))
    self.list = self.tree
    self:refresh()
end

function EditorMapBrowser:updateDockPreview(node, tree, x, y)
    if node.type ~= "map" or not node.registry_id then
        self.editor.dockspace.dock_preview = nil
        return
    end
    local tree_x, tree_y = tree:getGlobalPosition()
    self.editor.dockspace.dock_preview = self.editor:getMapPanelDropTarget(tree_x + x, tree_y + y)
end

function EditorMapBrowser:getRegisteredMapIds()
    local ids, seen = {}, {}
    for id in pairs(Registry.map_data or {}) do
        seen[id] = true
        table.insert(ids, id)
    end
    for id in pairs(Registry.maps or {}) do
        if not seen[id] then table.insert(ids, id) end
    end
    table.sort(ids)
    return ids
end

function EditorMapBrowser:refresh()
    self.tree:clear()
    local folders = { [""] = self.tree.root }
    local maps = {}
    for _, id in ipairs(self:getRegisteredMapIds()) do
        local parts = StringUtils.split(id, "/", true)
        local parent, path = self.tree.root, ""
        for index = 1, #parts - 1 do
            local name = parts[index]
            path = path == "" and name or (path .. "/" .. name)
            if not folders[path] then
                folders[path] = self.tree:createFolder(parent, name, { virtual = false })
            end
            parent = folders[path]
        end
        local node = self.tree:createMap(parent, parts[#parts] or id, {
            registry_id = id,
            virtual = false
        })
        maps[id] = node
    end
    self.tree:sort()
    local current_id = Game.world and Game.world.map and Game.world.map.id
    if current_id and maps[current_id] then self.tree:selectNode(maps[current_id]) end
end

function EditorMapBrowser:createFolder()
    local parent = self.tree:getInsertionParent()
    local node = self.tree:createFolder(parent, uniqueName(parent, "New Folder"), { virtual = true })
    self.tree:beginRename(node)
    return node
end

function EditorMapBrowser:createMap()
    local parent = self.tree:getInsertionParent()
    local node = self.tree:createMap(parent, uniqueName(parent, "New Map"), { virtual = true })
    self.tree:beginRename(node)
    return node
end

function EditorMapBrowser:activateNode(node)
    if not node or node.type ~= "map" then return false end
    if node.registry_id then return self.editor:openMap(node.registry_id) end
    self.editor:addWarning("New map '" .. node.name .. "' is visual-only until map creation is implemented",
        nil, "map_tree")
    return true
end

function EditorMapBrowser:dropOutside(node, tree, x, y)
    if node.type ~= "map" or not node.registry_id then return false end
    local tree_x, tree_y = tree:getGlobalPosition()
    local target = self.editor:getMapPanelDropTarget(tree_x + x, tree_y + y)
    if target then return self.editor:openMapTab(node.registry_id, target) end
    return false
end

function EditorMapBrowser:update(dt)
    local padding, gap = 8, 8
    local content_width = math.max(0, self.width - padding * 2)
    local button_width = math.max(0, (content_width - gap) / 2)
    self.search:setBounds(padding, padding, content_width, 28)
    self.new_map_button:setBounds(padding, 44, button_width, 28)
    self.new_folder_button:setBounds(padding + button_width + gap, 44, button_width, 28)
    self.tree:setBounds(padding, 80, content_width, math.max(0, self.height - 88))
    super.update(self, dt)
end

return EditorMapBrowser
