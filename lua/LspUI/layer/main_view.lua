local api = vim.api
local ClassView = require("LspUI.layer.view")

--- @class ClassMainView: ClassView
--- @field _old_winbar table 存储每个缓冲区原始的winbar设置
local ClassMainView = {}

setmetatable(ClassMainView, ClassView)
ClassMainView.__index = ClassMainView

--- 创建一个新的MainView实例
--- @param createBuf boolean 是否创建新的缓冲区
--- @return ClassMainView
function ClassMainView:New(createBuf)
    --- @type ClassView
    local view = ClassView:New(createBuf)
    local obj = setmetatable(view, self)
    obj._old_winbar = {}

    -- 注释明确告诉类型系统这是返回ClassMainView
    --- @cast obj ClassMainView

    -- 设置MainView默认配置
    obj._config.relative = "editor"
    obj._config.style = "minimal"
    obj._config.border = "rounded"

    -- 设置MainView大小为编辑器大小
    local width = api.nvim_get_option_value("columns", {})
    local height = api.nvim_get_option_value("lines", {}) - 2 -- 减去状态栏和命令行
    obj:Size(width, height)
    obj:Pos(0, 0)

    return obj
end

--- 渲染MainView，调整窗口大小为编辑器当前大小
--- @return ClassMainView
function ClassMainView:Render()
    -- 设置窗口大小为编辑器当前大小
    local width = api.nvim_get_option_value("columns", {})
    local height = api.nvim_get_option_value("lines", {}) - 2
    self:Size(width, height)

    -- 调用父类的Render方法
    ClassView.Render(self)

    -- 设置zindex为低值，确保在SubView下方
    if self:Valid() then
        api.nvim_win_set_config(self._windowId, { zindex = 50 })
    end

    return self
end

--- 设置winbar
--- @param winbar string
--- @return ClassMainView
function ClassMainView:SetWinbar(winbar)
    if not self:Valid() then
        return self
    end

    api.nvim_set_option_value("winbar", winbar, { win = self._windowId })
    return self
end

--- 重写SwitchBuffer方法，处理winbar的保存和恢复
--- @param newBuffer integer
--- @return ClassMainView
function ClassMainView:SwitchBuffer(newBuffer)
    -- 保存当前buffer的winbar（如果存在）
    if self:Valid() and self._attachBuffer then
        -- 查找当前buffer所有的窗口
        for _, win in ipairs(api.nvim_list_wins()) do
            if api.nvim_win_is_valid(win) and win ~= self._windowId then
                local buf = api.nvim_win_get_buf(win)
                if buf == self._attachBuffer then
                    -- 存储原始winbar
                    local original_winbar =
                        api.nvim_get_option_value("winbar", { win = win })
                    if original_winbar and original_winbar ~= "" then
                        self._old_winbar[self._attachBuffer] = original_winbar
                    end
                    break
                end
            end
        end
    end

    -- 调用父类方法切换buffer
    ClassView.SwitchBuffer(self, newBuffer)

    -- 为新buffer应用之前保存的winbar设置（如果有）
    if self:Valid() and self._old_winbar[newBuffer] then
        local winbar = self._old_winbar[newBuffer]
        api.nvim_set_option_value("winbar", winbar, { win = self._windowId })
    end

    return self
end

--- 重写Destory方法，恢复原始winbar
--- @return ClassMainView
function ClassMainView:Destory()
    if self:Valid() and self._attachBuffer then
        -- 恢复当前buffer的原始winbar设置
        local current_buf = self._attachBuffer
        if self._old_winbar[current_buf] then
            -- 查找该buffer的所有窗口并恢复winbar
            for _, win in ipairs(api.nvim_list_wins()) do
                if api.nvim_win_is_valid(win) and win ~= self._windowId then
                    local buf = api.nvim_win_get_buf(win)
                    if buf == current_buf then
                        api.nvim_set_option_value(
                            "winbar",
                            self._old_winbar[current_buf],
                            { win = win }
                        )
                    end
                end
            end
        end
    end

    -- 调用父类的销毁方法
    ClassView.Destory(self)
    return self
end

--- 调整MainView大小以适应编辑器大小变化
--- @return ClassMainView
function ClassMainView:Resize()
    local width = api.nvim_get_option_value("columns", {})
    local height = api.nvim_get_option_value("lines", {}) - 2

    self:Size(width, height)
    return self
end

--- 设置MainView和SubView的z-index层级关系
--- @param subView ClassSubView SubView实例
--- @return ClassMainView
function ClassMainView:SetZIndex(subView)
    if not self:Valid() or not subView:Valid() then
        return self
    end
    -- 确保MainView的zindex较低
    api.nvim_win_set_config(self._windowId, { zindex = 50 })
    -- 添加nil检查
    local winID = subView:GetWinID()
    if winID then -- 确保winID不是nil
        -- 确保SubView的zindex较高
        api.nvim_win_set_config(winID, { zindex = 100 })
    end
    return self
end

return ClassMainView
