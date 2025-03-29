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

-- 修改 window 绑定的 buffer
--- @param newBuffer integer
function ClassView:SwitchBuffer(newBuffer)
    self._attachBuffer = newBuffer
    if not self:Valid() then
        return
    end
    api.nvim_win_set_buf(self._windowId, self._attachBuffer)
end

--- private function, not use
--- @private
function ClassView:update()
    if (not self:Valid()) or self._stop_update then
        return
    end
    api.nvim_win_set_config(self._windowId, self._config)
end

--- @return integer
function ClassView:Render()
    if not self:Valid() then
        self._windowId =
            api.nvim_open_win(self._attachBuffer, self._enter, self._config)
    end
    return self._windowId
end

--- @param relative "cursor"|"editor"|"laststatus"|"mouse"|"tabline"|"win"|nil
function ClassView:Relative(relative)
    self._config.relative = relative
    if self:Valid() then
        api.nvim_win_set_config(self._windowId, self._config)
    end
end

-- destory window
function ClassView:Destory()
    if not self:Valid() then
        return
    end
    if self._closeEvent then
        self._closeEvent()
    end
    api.nvim_win_close(self._windowId, true)
    self._windowId = nil
    self._attachBuffer = nil
end

-- whether the view is valid
function ClassView:Valid()
    if not self._windowId then
        return false
    end
    return api.nvim_win_is_valid(self._windowId)
end

--- @param callback fun()
function ClassView:CloseEvent(callback)
    self._closeEvent = callback
end

--- @param title string
--- @param pos "left"|"center"|"right"
function ClassView:Title(title, pos)
    self._config.title = title
    self._config.title_pos = pos
    self:update()
end

--- @param footer string
--- @param pos "left"|"center"|"right"
function ClassView:Footer(footer, pos)
    self._config.footer = footer
    self._config.footer_pos = pos
    self:update()
end

--- @param focusable boolean
function ClassView:Focusable(focusable)
    self._config.focusable = focusable
    self:update()
end

--- @param width integer
--- @param height integer
function ClassView:Size(width, height)
    if width < 1 then
        width = 1
    end
    if height < 1 then
        height = 1
    end
    self._config.width = width
    self._config.height = height
    self:update()
end

--- @param row number
--- @param col number
function ClassView:Pos(row, col)
    self._config.row = row
    self._config.col = col
    if not self:Valid() then
        return
    end
    self:update()
end

--- @param border "none"|"single"|"double"|"rounded"|"solid"|"shadow"|string[]
function ClassView:Border(border)
    if type(border) == "table" then
        assert(#border == 8, "border length must be 8")
    end
    self._config.border = border
    self:update()
end

--- @param hide boolean
function ClassView:Hide(hide)
    self._config.hide = hide
    self:update()
end

--- @param  style "minimal"
function ClassView:Style(style)
    self._config.style = style
    self:update()
end

--- @param anchor "NW"|"NE"|"SW"|"SE"
function ClassView:Anchor(anchor)
    self._config.anchor = anchor
    self:update()
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
function ClassView:Enter(enter)
    self._enter = enter
end

--- @param winhl string
function ClassView:Winhl(winhl)
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value("winhl", winhl, { win = self._windowId })
end

--- @param winbl number
function ClassView:Winbl(winbl)
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value("winbl", winbl, { win = self._windowId })
end

--- @param callback fun()
function ClassView:Call(callback)
    if not self:Valid() then
        return
    end
    api.nvim_win_call(self._windowId, callback)
end

--- @param name string
--- @param value any
function ClassView:Option(name, value)
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value(name, value, { win = self._windowId })
end

--- @param name string
--- @param value any
function ClassView:BufOption(name, value)
    if not self:Valid() then
        return
    end
    api.nvim_set_option_value(name, value, { buf = self._attachBuffer })
end

function ClassView:Focus()
    if not self:Valid() then
        return
    end
    api.nvim_set_current_win(self._windowId)
end

--- @param cb fun()
function ClassView:Updates(cb)
    self._stop_update = true
    cb()
    self._stop_update = false
    self:update()
end

return ClassView
