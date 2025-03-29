local api, fn = vim.api, vim.fn

--- @class ClassSubView
--- @field windowId integer|nil
--- @field attachBuffer integer|nil
--- @field enter boolean
--- @field config table
local ClassView = {
    windowId = nil,
    attachBuffer = nil,
    enter = false,
    config = {},
}

function ClassView:New(...)
    local obj = {} -- 创建一个新的空表作为对象
    setmetatable(obj, self) -- 设置元表，使对象继承类的方法
    self.__index = self -- 设置索引元方法
    -- 初始化对象的属性
    obj:init(...) -- 可选：调用初始化函数
    return obj
end

-- 修改 window 绑定的 buffer
--- @param newBuffer integer
function ClassView:SwitchBuffer(newBuffer)
    self.attachBuffer = newBuffer
    if not self:Valid() then
        return
    end
    api.nvim_win_set_buf(self.windowId, self.attachBuffer)
end

function ClassView:Render()
    -- stylua: ignore
    if self:Valid() then return end
    self.windowId =
        api.nvim_open_win(self.attachBuffer, self.enter, self.config)
end

--- @param relative "cursor"|"editor"|"laststatus"|"mouse"|"tabline"|"win"|nil
function ClassView:Relative(relative)
    self.config.relative = relative
    if self:Valid() then
        api.nvim_win_set_config(self.windowId, self.config)
    end
end

-- destory window
function ClassView:Destory()
    if not self:Valid() then
        return
    end
    api.nvim_win_close(self.windowId, true)
    self.windowId = nil
end

-- whether the view is valid
function ClassView:Valid()
    if not self.windowId then
        return false
    end
    return api.nvim_win_is_valid(self.windowId)
end
