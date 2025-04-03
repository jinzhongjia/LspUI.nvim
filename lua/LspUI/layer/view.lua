local api, fn = vim.api, vim.fn

--- @class ClassView
--- @field _windowId integer|nil
--- @field _attachBuffer integer|nil
--- @field _enter boolean
--- @field _config table
--- @field _closeEvent fun()|nil
local ClassView = {
    _windowId = nil,
    _attachBuffer = nil,
    _enter = false,
    _config = {},
    _closeEvent = nil,
    _stop_update = false,
}

ClassView.__index = ClassView

--- @param create_buf boolean
--- @return ClassView
function ClassView:New(create_buf)
    local obj = {} -- 创建一个新的空表作为对象
    setmetatable(obj, self) -- 设置元表，使对象继承类的方法
    -- 初始化对象的属性
    if create_buf then
        self._attachBuffer = api.nvim_create_buf(false, true)
    end
    return obj
end

local function command_desc(desc)
    return "[LspUI]: " .. desc
end

-- 修改 window 绑定的 buffer
--- @param newBuffer integer
--- @return ClassView
function ClassView:SwitchBuffer(newBuffer)
    self._attachBuffer = newBuffer
    if not self:Valid() then
        return self
    end
    api.nvim_win_set_buf(self._windowId, self._attachBuffer)
    return self
end

--- private function, not use
--- @return ClassView
--- @private
function ClassView:update()
    if (not self:Valid()) or self._stop_update then
        return self
    end
    api.nvim_win_set_config(self._windowId, self._config)
    return self
end

--- @return ClassView
function ClassView:Render()
    if not self:Valid() then
        self._windowId =
            api.nvim_open_win(self._attachBuffer, self._enter, self._config)
    end
    return self
end

--- @param relative "cursor"|"editor"|"laststatus"|"mouse"|"tabline"|"win"|nil
--- @return ClassView
function ClassView:Relative(relative)
    self._config.relative = relative
    if self:Valid() then
        api.nvim_win_set_config(self._windowId, self._config)
    end
    return self
end

-- destory window
--- @return ClassView
function ClassView:Destory()
    if not self:Valid() then
        return self
    end
    if self._closeEvent then
        self._closeEvent()
    end
    api.nvim_win_close(self._windowId, true)
    self._windowId = nil
    self._attachBuffer = nil
    return self
end

-- whether the view is valid
--- @return boolean
function ClassView:Valid()
    if not self._windowId then
        return false
    end
    return api.nvim_win_is_valid(self._windowId)
end

--- @param callback fun()
--- @return ClassView
function ClassView:CloseEvent(callback)
    self._closeEvent = callback
    return self
end

--- @param title string
--- @param pos "left"|"center"|"right"
--- @return ClassView
function ClassView:Title(title, pos)
    self._config.title = title
    self._config.title_pos = pos
    self:update()
    return self
end

--- @param footer string
--- @param pos "left"|"center"|"right"
--- @return ClassView
function ClassView:Footer(footer, pos)
    self._config.footer = footer
    self._config.footer_pos = pos
    self:update()
    return self
end

--- @param focusable boolean
--- @return ClassView
function ClassView:Focusable(focusable)
    self._config.focusable = focusable
    self:update()
    return self
end

--- @param width integer|nil
--- @param height integer|nil
--- @return ClassView
function ClassView:Size(width, height)
    if width then
        if width < 1 then
            width = 1
        end
        self._config.width = width
    end
    if height then
        if height < 1 then
            height = 1
        end
        self._config.height = height
    end
    self:update()
    return self
end

--- @param row number
--- @param col number
--- @return ClassView
function ClassView:Pos(row, col)
    self._config.row = row
    self._config.col = col
    if not self:Valid() then
        return self
    end
    self:update()
    return self
end

--- @param border "none"|"single"|"double"|"rounded"|"solid"|"shadow"|string[]
--- @return ClassView
function ClassView:Border(border)
    if type(border) == "table" then
        assert(#border == 8, "border length must be 8")
    end
    self._config.border = border
    self:update()
    return self
end

--- @param hide boolean
--- @return ClassView
function ClassView:Hide(hide)
    self._config.hide = hide
    self:update()
    return self
end

--- @param  style "minimal"
--- @return ClassView
function ClassView:Style(style)
    self._config.style = style
    self:update()
    return self
end

--- @param anchor "NW"|"NE"|"SW"|"SE"
--- @return ClassView
function ClassView:Anchor(anchor)
    self._config.anchor = anchor
    self:update()
    return self
end

--- @return integer|nil
function ClassView:GetBufID()
    return self._attachBuffer
end

--- @return integer|nil
function ClassView:GetWinID()
    return self._windowId
end

--- @param enter boolean
--- @return ClassView
function ClassView:Enter(enter)
    self._enter = enter
    return self
end

--- @param winhl string
--- @return ClassView
function ClassView:Winhl(winhl)
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winhl", winhl, { win = self._windowId })
    return self
end

--- @param winbl number
--- @return ClassView
function ClassView:Winbl(winbl)
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winbl", winbl, { win = self._windowId })
    return self
end

--- @param callback fun()
--- @return ClassView
function ClassView:Call(callback)
    if not self:Valid() then
        return self
    end
    api.nvim_win_call(self._windowId, callback)
    return self
end

--- @param name string
--- @param value any
--- @return ClassView
function ClassView:Option(name, value)
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value(name, value, { win = self._windowId })
    return self
end

--- @param name string
--- @param value any
--- @return ClassView
function ClassView:BufOption(name, value)
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value(name, value, { buf = self._attachBuffer })
    return self
end

--- @return ClassView
function ClassView:Focus()
    if not self:Valid() then
        return self
    end
    api.nvim_set_current_win(self._windowId)
    return self
end

--- @param cb fun()
--- @return ClassView
function ClassView:Updates(cb)
    self._stop_update = true
    cb()
    self._stop_update = false
    self:update()
    return self
end

--- @param start integer
--- @param end_ integer
--- @param content string[]
--- @return ClassView
function ClassView:BufContent(start, end_, content)
    local invalid = not api.nvim_buf_is_valid(self._attachBuffer)
    if invalid then
        return self
    end
    api.nvim_buf_set_lines(self._attachBuffer, start, end_, true, content)
    return self
end

--- @param cb fun()
--- @return ClassView
function ClassView:BufCall(cb)
    local invalid = not api.nvim_buf_is_valid(self._attachBuffer)
    if invalid then
        return self
    end

    api.nvim_buf_call(self._attachBuffer, cb)
    return self
end

--- @param mode string
--- @param key string
--- @param cb fun()
--- @param desc string
--- @return ClassView
function ClassView:KeyMap(mode, key, cb, desc)
    local invalid = not api.nvim_buf_is_valid(self._attachBuffer)
    if invalid then
        return self
    end
    api.nvim_buf_set_keymap(self._attachBuffer, mode, key, "", {
        nowait = true,
        noremap = true,
        callback = cb,
        desc = command_desc(desc),
    })
    return self
end

--- @return ClassView
function ClassView:AutoCmd()
    return self
end

--- @param event string|string[]
--- @param group string|integer|nil
--- @param cb fun()
--- @param desc string
--- @return ClassView
function ClassView:BufAutoCmd(event, group, cb, desc)
    local invalid = not api.nvim_buf_is_valid(self._attachBuffer)
    if invalid then
        return self
    end

    api.nvim_create_autocmd(event, {
        group = group,
        buffer = self._attachBuffer,
        callback = cb,
        desc = command_desc(desc),
    })
    return self
end

return ClassView
