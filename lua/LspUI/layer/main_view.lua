local api = vim.api
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")

--- @class ClassMainView: ClassView
--- @field _old_winbar table 存储每个缓冲区原始的winbar设置
local ClassMainView = {}

setmetatable(ClassMainView, ClassView)
ClassMainView.__index = ClassMainView
ClassMainView._keymap_history = {}
ClassMainView._namespace = api.nvim_create_namespace("LspUI_main")

--- 创建一个新的MainView实例
--- @param createBuf boolean 是否创建新的缓冲区
--- @return ClassMainView
function ClassMainView:New(createBuf)
    --- @type ClassView
    local view = ClassView:New(createBuf)
    local obj = setmetatable(view, self)
    obj._old_winbar = {}
    obj._config = {}
    obj._keymap_history = {}

    -- 注释明确告诉类型系统这是返回ClassMainView
    --- @cast obj ClassMainView

    -- 设置MainView默认配置
    obj._config.relative = "editor"
    -- obj._config.style = ""
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

--- @param newBuffer integer
--- @return ClassMainView
function ClassMainView:SwitchBuffer(newBuffer)
    -- 清除当前缓冲区的高亮
    if self:Valid() and self._attachBuffer then
        self:ClearHighlight()
    end

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

    -- 确保缓冲区被加载
    if not api.nvim_buf_is_loaded(newBuffer) then
        vim.fn.bufload(newBuffer)
    end

    -- 触发BufRead事件确保语法高亮
    api.nvim_buf_call(newBuffer, function()
        if api.nvim_get_option_value("filetype", { buf = newBuffer }) == "" then
            vim.cmd("do BufRead")
        end
    end)

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

        -- 恢复当前buffer的键映射
        if self._keymap_history and self._keymap_history[current_buf] then
            ---@diagnostic disable-next-line: param-type-mismatch
            self:RestoreKeyMappings(current_buf)
        end
    end

    -- 对所有保存的键映射执行恢复
    if self._keymap_history then
        for buf_id, _ in pairs(self._keymap_history) do
            if
                api.nvim_buf_is_valid(buf_id)
                and buf_id ~= self._attachBuffer
            then
                self:RestoreKeyMappings(buf_id)
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

--- 保存当前缓冲区的按键映射
--- @param buf_id integer 缓冲区ID
--- @return ClassMainView
function ClassMainView:SaveKeyMappings(buf_id)
    if not buf_id or not api.nvim_buf_is_valid(buf_id) then
        return self
    end

    local keybinds = {
        config.options.pos_keybind.main.back,
        config.options.pos_keybind.main.hide_secondary,
    }

    self._keymap_history[buf_id] = {}

    for _, key in ipairs(keybinds) do
        self._keymap_history[buf_id][key] = vim.fn.maparg(key, "n", false, true)
    end

    return self
end

--- 恢复缓冲区的键映射
--- @param buf_id integer 缓冲区ID
--- @return ClassMainView
function ClassMainView:RestoreKeyMappings(buf_id)
    if
        not buf_id
        or not api.nvim_buf_is_valid(buf_id)
        or not self._keymap_history[buf_id]
    then
        return self
    end

    for key, map_info in pairs(self._keymap_history[buf_id]) do
        -- 先删除当前映射
        pcall(api.nvim_buf_del_keymap, buf_id, "n", key)

        -- 如果有原始映射，则恢复
        if not vim.tbl_isempty(map_info) then
            vim.fn.mapset("n", false, map_info)
        end
    end

    -- 清理存储
    self._keymap_history[buf_id] = nil

    return self
end

--- 清除主视图中的所有高亮
--- @return ClassMainView
function ClassMainView:ClearHighlight()
    if not self:BufVaild() then
        return self
    end

    api.nvim_buf_clear_namespace(self._attachBuffer, self._namespace, 0, -1)
    return self
end

--- 在主视图中高亮指定范围
--- @param ranges LspUIRange[] 要高亮的范围数组
--- @param hlGroup string? 高亮组名称，默认为 "Search"
--- @return ClassMainView
function ClassMainView:SetHighlight(ranges, hlGroup)
    if not self:BufVaild() then
        return self
    end

    hlGroup = hlGroup or "Search"

    -- 先清除旧的高亮
    self:ClearHighlight()

    -- 为每个范围添加高亮
    for _, range in ipairs(ranges) do
        for row = range.start.line, range.finish.line do
            local start_col = 0
            local end_col = -1

            if row == range.start.line then
                start_col = range.start.character
            end

            if row == range.finish.line then
                end_col = range.finish.character
            end

            api.nvim_buf_add_highlight(
                self._attachBuffer,
                self._namespace,
                hlGroup,
                row,
                start_col,
                end_col
            )
        end
    end

    return self
end

-- 添加到 ClassMainView
--- @return ClassMainView
function ClassMainView:PinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfixbuf", true, { win = self._windowId })
    return self
end

--- @return ClassMainView
function ClassMainView:UnPinBuffer()
    if not self:Valid() then
        return self
    end
    api.nvim_set_option_value("winfixbuf", false, { win = self._windowId })
    return self
end

return ClassMainView
