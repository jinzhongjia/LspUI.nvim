-- lua/LspUI/layer/controller.lua (修复版本)
local api = vim.api
local ClassLsp = require("LspUI.layer.lsp")
local ClassMainView = require("LspUI.layer.main_view")
local ClassSubView = require("LspUI.layer.sub_view")
local config = require("LspUI.config")
local lib_notify = require("LspUI.layer.notify")
local lib_util = require("LspUI.lib.util")
local tools = require("LspUI.layer.tools")

---@class ClassController
---@field _lsp ClassLsp
---@field _mainView ClassMainView
---@field _subView ClassSubView
---@field _current_item {uri: string, buffer_id: integer, range: LspUIRange?}
---@field _push_tagstack function|nil
local ClassController = {
    ---@diagnostic disable-next-line: assign-type-mismatch
    _lsp = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _mainView = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _subView = nil,
    _current_item = {},
    _push_tagstack = nil,
    _debounce_delay = 50, -- 50ms 的防抖延迟
}

ClassController.__index = ClassController

---@return ClassController
function ClassController:New()
    local obj = {}
    setmetatable(obj, self)

    obj._lsp = ClassLsp:New()
    obj._mainView = ClassMainView:New(false)
    obj._subView = ClassSubView:New(true)

    api.nvim_create_augroup("LspUI_SubView", { clear = true })

    return obj
end

---@private
---@return integer width, integer height
function ClassController:_generateSubViewContent()
    local data = self._lsp:GetData()
    local bufId = self._subView:GetBufID()

    if not bufId or not api.nvim_buf_is_valid(bufId) then
        bufId = api.nvim_create_buf(false, true)
        self._subView:SwitchBuffer(bufId)
    end

    -- 允许修改缓冲区
    api.nvim_set_option_value("modifiable", true, { buf = bufId })

    -- 设置文件类型
    local method = self._lsp:GetMethod()
    api.nvim_set_option_value(
        "filetype",
        string.format("LspUI-%s", method.name),
        { buf = bufId }
    )

    -- 先清空缓冲区，避免与旧内容冲突
    api.nvim_buf_set_lines(bufId, 0, -1, true, {})

    -- 创建命名空间用于extmark，并清除旧的extmark
    local extmark_ns = api.nvim_create_namespace("LspUIPathExtmarks")
    api.nvim_buf_clear_namespace(bufId, extmark_ns, 0, -1)

    -- 初始化变量
    local hl_lines = {} -- 需要高亮的行
    local content = {} -- 要添加的内容
    local extmarks = {} -- 存储要添加的extmark信息 {line, text, hl_group}
    local max_width = 0

    -- 统一路径格式的辅助函数
    local function normalize_path(path)
        -- 统一使用正斜杠作为路径分隔符
        local result = path:gsub("\\", "/")
        -- Windows 系统转为小写以进行不区分大小写的比较
        if vim.fn.has("win32") == 1 then
            result = result:lower()
        end
        -- 确保路径以斜杠结束
        if result:sub(-1) ~= "/" then
            result = result .. "/"
        end
        return result
    end

    -- 获取并规范化当前工作目录
    local cwd = normalize_path(vim.fn.getcwd())

    -- 生成内容
    for uri, item in pairs(data) do
        -- 文件名格式化
        local file_full_name = vim.uri_to_fname(uri)
        local file_name = vim.fn.fnamemodify(file_full_name, ":t")

        -- 计算相对路径，用于extmark
        local rel_path = ""
        local norm_file_path =
            normalize_path(vim.fn.fnamemodify(file_full_name, ":p"))

        if norm_file_path:sub(1, #cwd) == cwd then
            -- 如果文件在工作目录下，显示相对路径
            rel_path = file_full_name:sub(#vim.fn.getcwd() + 1) -- +1 是为了去掉路径分隔符
            rel_path = vim.fn.fnamemodify(rel_path, ":h")
            if rel_path ~= "." and rel_path ~= "" then
                rel_path = " (" .. rel_path .. ")"
            else
                rel_path = ""
            end
        else
            -- 否则显示目录路径
            local dir = vim.fn.fnamemodify(file_full_name, ":h")
            rel_path = " (" .. dir .. ")"
        end

        -- 构建文件行格式
        local file_fmt =
            string.format(" %s %s", item.fold and "▶" or "▼", file_name)

        -- 添加到内容
        table.insert(content, file_fmt)
        table.insert(hl_lines, #content) -- 记录需要高亮的行号

        -- 存储extmark信息，等内容全部添加完后再设置
        if rel_path ~= "" then
            table.insert(extmarks, {
                line = #content - 1, -- 行号从0开始
                text = rel_path,
                hl_group = "Comment",
            })
        end

        -- 更新最大宽度
        local file_fmt_len = vim.fn.strdisplaywidth(file_fmt)
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        -- 收集行号
        local uri_rows = {}
        for _, range in ipairs(item.range) do
            table.insert(uri_rows, range.start.line)
        end

        -- 获取代码行内容
        local lines = tools.GetUriLines(item.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = vim.fn.trim(lines[row] or "")
            local code_fmt = string.format("   %s", line_code)

            -- 如果未折叠，添加到内容
            if not item.fold then
                table.insert(content, code_fmt)
            end

            -- 更新最大宽度
            local code_fmt_length = vim.fn.strdisplaywidth(code_fmt)
            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    -- 设置内容
    api.nvim_buf_set_lines(bufId, 0, -1, true, content)

    -- 设置高亮
    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
    api.nvim_buf_clear_namespace(bufId, subViewNamespace, 0, -1)

    -- 对文件名行应用高亮
    for _, lnum in pairs(hl_lines) do
        vim.api.nvim_buf_add_highlight(
            bufId,
            subViewNamespace,
            "Directory",
            lnum - 1, -- 行号从0开始
            3,
            -1
        )
    end

    -- 添加所有extmark
    for _, mark in ipairs(extmarks) do
        -- 检查行是否有效
        if mark.line >= 0 and mark.line < #content then
            local line_content = content[mark.line + 1] or "" -- +1因为lua索引从1开始
            api.nvim_buf_set_extmark(
                bufId,
                extmark_ns,
                mark.line,
                #line_content,
                {
                    virt_text = { { mark.text, mark.hl_group } },
                    virt_text_pos = "eol",
                }
            )
        end
    end

    -- 禁止修改
    api.nvim_set_option_value("modifiable", false, { buf = bufId })

    -- 计算适当的宽度
    local res_width = max_width + 2 > 30 and 30 or max_width + 2
    local max_columns =
        math.floor(api.nvim_get_option_value("columns", {}) * 0.3)

    -- 确保宽度至少满足工作区路径显示需要
    if max_columns > res_width then
        res_width = max_columns
    end

    return res_width, #content + 1 -- 高度就是内容行数+1
end

---@private
function ClassController:_setupSubViewKeyBindings()
    local buf = self._subView:GetBufID()
    if not buf then
        return
    end

    local keyBindings = {
        [config.options.pos_keybind.secondary.jump] = function()
            self:ActionJump()
        end,
        [config.options.pos_keybind.secondary.jump_tab] = function()
            self:ActionJump("tabe")
        end,
        [config.options.pos_keybind.secondary.jump_split] = function()
            self:ActionJump("split")
        end,
        [config.options.pos_keybind.secondary.jump_vsplit] = function()
            self:ActionJump("vsplit")
        end,
        [config.options.pos_keybind.secondary.toggle_fold] = function()
            self:ActionToggleFold()
        end,
        [config.options.pos_keybind.secondary.next_entry] = function()
            self:ActionNextEntry()
        end,
        [config.options.pos_keybind.secondary.prev_entry] = function()
            self:ActionPrevEntry()
        end,
        [config.options.pos_keybind.secondary.quit] = function()
            self:ActionQuit()
        end,
        [config.options.pos_keybind.secondary.hide_main] = function()
            self:ActionToggleMainView()
        end,
        [config.options.pos_keybind.secondary.fold_all] = function()
            self:ActionFoldAll(true)
        end,
        [config.options.pos_keybind.secondary.expand_all] = function()
            self:ActionFoldAll(false)
        end,
        [config.options.pos_keybind.secondary.enter] = function()
            self:ActionEnterMainView()
        end,
    }

    for key, callback in pairs(keyBindings) do
        api.nvim_buf_set_keymap(buf, "n", key, "", {
            nowait = true,
            noremap = true,
            callback = callback,
        })
    end

    -- 设置光标移动事件
    self._subView:BufAutoCmd("CursorMoved", "LspUI_SubView", function()
        self:_debouncedCursorMoved()
    end, "跟踪光标移动")
end

---@private
function ClassController:_setupMainViewKeyBindings()
    local buf = self._mainView:GetBufID()
    if not buf then
        return
    end
    self._mainView:SaveKeyMappings(buf)

    local keyBindings = {
        [config.options.pos_keybind.main.back] = function()
            self:ActionBackToSubView()
        end,
        [config.options.pos_keybind.main.hide_secondary] = function()
            self:ActionToggleSubView()
        end,
    }

    for key, callback in pairs(keyBindings) do
        api.nvim_buf_set_keymap(buf, "n", key, "", {
            nowait = true,
            noremap = true,
            callback = callback,
        })
    end
end

---@private
function ClassController:_onCursorMoved()
    local lnum = vim.fn.line(".")
    local uri, range = self:_getLspPositionByLnum(lnum)

    if not uri then
        return
    end

    -- 设置当前项目，即使没有range（表示是文件路径行）
    self._current_item = {
        uri = uri,
        buffer_id = self._lsp:GetData()[uri].buffer_id,
        range = range,
        is_file_header = (range == nil),
    }

    -- 只有当选中了具体代码行且主视图有效时才更新主视图
    if range and self._mainView:Valid() then
        -- 切换缓冲区前先暂时解除固定
        self._mainView:UnPinBuffer()

        -- 切换主视图缓冲区
        local bufId = self._lsp:GetData()[uri].buffer_id
        self._mainView:SwitchBuffer(bufId)

        -- 切换后重新固定
        self._mainView:PinBuffer()

        -- 设置光标位置
        local win = self._mainView:GetWinID()
        if win then
            api.nvim_win_set_cursor(
                win,
                { range.start.line + 1, range.start.character }
            )

            -- 居中显示
            api.nvim_win_call(win, function()
                vim.cmd("norm! zv")
                vim.cmd("norm! zz")
            end)
        end

        -- 添加这行：设置高亮
        self._mainView:SetHighlight({ range })
    end
end

--- @private
function ClassController:_debouncedCursorMoved()
    -- 清除之前的定时器
    if self._debounce_timer then
        vim.fn.timer_stop(self._debounce_timer)
        self._debounce_timer = nil
    end

    -- 创建新的定时器
    self._debounce_timer = vim.fn.timer_start(self._debounce_delay, function()
        -- 在主线程中执行
        vim.schedule(function()
            -- 确保视图仍然有效
            if self._subView:Valid() then
                self:_onCursorMoved()
            end
        end)
    end)
end

---@private
---@param lnum integer
---@return string? uri, LspUIRange? range
function ClassController:_getLspPositionByLnum(lnum)
    local data = self._lsp:GetData()
    local currentLine = 1

    for uri, item in pairs(data) do
        -- 文件标题行
        if currentLine == lnum then
            return uri, nil
        end
        currentLine = currentLine + 1

        -- 文件内容行
        if not item.fold then
            for _, range in ipairs(item.range) do
                if currentLine == lnum then
                    return uri, range
                end
                currentLine = currentLine + 1
            end
        end
    end

    return nil, nil
end

---@private
---@param uri string
---@param range LspUIRange? 当前选中的范围，用于定位折叠后光标位置
---@return integer lnum 光标应放置的行号
function ClassController:_getCursorPosForUri(uri, range)
    local currentLine = 1
    local data = self._lsp:GetData()
    local fileHeaderLine = nil

    for currentUri, item in pairs(data) do
        -- 记录文件标题行
        fileHeaderLine = currentLine
        currentLine = currentLine + 1

        if currentUri == uri then
            if not range then
                -- 没有指定范围，返回文件标题行
                return fileHeaderLine
            end

            -- 如果文件被折叠了，直接返回文件标题行
            if item.fold then
                return fileHeaderLine
            end

            -- 文件未折叠，继续查找匹配的范围行
            for _, itemRange in ipairs(item.range) do
                if
                    itemRange.start.line == range.start.line
                    and itemRange.start.character == range.start.character
                then
                    return currentLine
                end
                currentLine = currentLine + 1
            end

            -- 如果没找到匹配的范围，返回文件标题行
            return fileHeaderLine
        end

        -- 如果不是目标URI，跳过其范围行
        if not item.fold then
            currentLine = currentLine + #item.range
        end
    end

    -- 默认返回第一行
    return 1
end

-- 公开API开始
---@param method_name string
---@param buffer_id integer
---@param params table
function ClassController:Go(method_name, buffer_id, params)
    -- 设置方法
    if not self._lsp:SetMethod(method_name) then
        return
    end

    -- 保存标签栈
    self._push_tagstack = lib_util.create_push_tagstack(0)

    -- 发起LSP请求
    self._lsp:Request(buffer_id, params, function(data)
        if not data or vim.tbl_isempty(data) then
            lib_notify.Info(string.format("找不到%s", method_name))
            return
        end

        -- 初始化视图
        self:RenderViews()

        -- 绑定键映射
        self:_setupSubViewKeyBindings()

        -- 设置光标位置
        local win = self._subView:GetWinID()
        if win then
            api.nvim_set_current_win(win)
            local lnum = self:_findPositionFromParams(params)
            api.nvim_win_set_cursor(win, { lnum, 0 })

            -- 手动触发一次光标移动处理
            self:_onCursorMoved()
        end
    end)
end

function ClassController:RenderViews()
    -- 创建副视图
    local width, height = self:_generateSubViewContent()

    self._subView:Updates(function()
        self._subView
            :Border("single")
            :Style("minimal")
            :Relative("editor")
            :Size(width, height)
            :Pos(0, api.nvim_get_option_value("columns", {}) - width - 2)
            :Winbl(config.options.pos_keybind.transparency)
            :Title(self._lsp:GetMethod().name, "center")
    end)

    self._subView:Render()

    -- 获取第一个URI对应的缓冲区作为MainView的初始缓冲区
    local firstBuffer = nil
    for _, item in pairs(self._lsp:GetData()) do
        firstBuffer = item.buffer_id
        break
    end

    -- 创建主视图，确保设置了初始缓冲区
    if firstBuffer then
        self._mainView:SwitchBuffer(firstBuffer)

        self._mainView:Updates(function()
            self
                ._mainView
                :Border("none")
                -- :Style("minimal")
                :Relative("editor")
                :Size(
                    api.nvim_get_option_value("columns", {}) - 2,
                    api.nvim_get_option_value("lines", {}) - 2
                )
                :Pos(0, 0)
                :Winbl(config.options.pos_keybind.transparency)
        end)

        self._mainView:Render()

        -- 添加：设置主视图为固定状态
        self._mainView:PinBuffer()

        -- 建立双向绑定
        self._mainView:BindView(self._subView)
        self._subView:SetZIndex(100)

        -- 初始化主视图键绑定
        self:_setupMainViewKeyBindings()
    else
        -- 如果找不到初始缓冲区，记录警告
        lib_notify.Warn("找不到可用的缓冲区来初始化主视图")
    end
end

---@param cmd string|nil 可选的跳转命令
function ClassController:ActionJump(cmd)
    if not self._current_item.uri then
        return
    end

    -- 保存当前项目
    local item = self._current_item

    -- 如果是文件路径行（没有range），则执行折叠操作
    if not item.range then
        self:ActionToggleFold()
        return
    end

    -- 执行标签栈
    if self._push_tagstack then
        self._push_tagstack()
    end

    -- 清除高亮 - 添加这一行确保高亮被清除
    if self._mainView:Valid() then
        self._mainView:ClearHighlight()
    end

    -- 关闭视图前先解除固定
    if self._mainView:Valid() then
        self._mainView:UnPinBuffer()
    end

    -- 关闭视图
    self._subView:Destory() -- 会同时销毁绑定的mainView

    -- 执行跳转
    if cmd then
        if cmd == "tabe" then
            vim.cmd("tab split")
        else
            vim.cmd(cmd)
        end
    end

    -- 打开文件
    if tools.buffer_is_listed(item.buffer_id) then
        vim.cmd(string.format("buffer %s", item.buffer_id))
    else
        vim.cmd(
            string.format(
                "edit %s",
                vim.fn.fnameescape(vim.uri_to_fname(item.uri))
            )
        )
    end

    -- 设置光标位置
    api.nvim_win_set_cursor(0, {
        item.range.start.line + 1,
        item.range.start.character,
    })
    vim.cmd("norm! zz")
end

function ClassController:ActionToggleFold()
    if not self._current_item.uri then
        return
    end

    -- 保存当前状态，包括当前的范围
    local uri = self._current_item.uri
    local currentRange = self._current_item.range
    local data = self._lsp:GetData()

    if not data[uri] then
        return
    end

    -- 切换折叠状态
    data[uri].fold = not data[uri].fold

    -- 重新生成SubView内容
    local width, height = self:_generateSubViewContent()
    self._subView:Size(width, height)

    -- 设置光标位置到适当的行
    local lnum = self:_getCursorPosForUri(uri, currentRange)
    if
        self._subView:GetWinID()
        and api.nvim_win_is_valid(self._subView:GetWinID())
    then
        api.nvim_win_set_cursor(self._subView:GetWinID(), { lnum, 0 })

        -- 手动触发一次光标移动处理更新当前项
        self:_onCursorMoved()
    end
end

function ClassController:ActionNextEntry()
    if not self._current_item.uri then
        return
    end

    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local found = false
    local line = 1

    -- 查找下一个项目
    for uri, item in pairs(data) do
        if found then
            ---@diagnostic disable-next-line: param-type-mismatch
            api.nvim_win_set_cursor(self._subView:GetWinID(), { line, 0 })
            return
        end

        line = line + 1
        if not item.fold then
            line = line + #item.range
        end

        if uri == current_uri then
            found = true
        end
    end
end

function ClassController:ActionPrevEntry()
    if not self._current_item.uri then
        return
    end

    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local line = 1
    local prev_line = 1

    -- 查找上一个项目
    for uri, item in pairs(data) do
        if uri == current_uri then
            if prev_line < line then
                api.nvim_win_set_cursor(
                    self._subView:GetWinID(),
                    { prev_line, 0 }
                )
            end
            return
        end

        prev_line = line
        line = line + 1
        if not item.fold then
            line = line + #item.range
        end
    end
end

function ClassController:ActionQuit()
    if self._mainView:Valid() then
        self._mainView:UnPinBuffer()
    end
    -- 使用 Destory 会同时销毁两个视图，因为它们是绑定的
    self._subView:Destory()
end
function ClassController:ActionToggleMainView()
    if not self._mainView:Valid() then
        -- 如果数据存在则重新渲染
        local firstBuffer = nil
        for _, item in pairs(self._lsp:GetData()) do
            firstBuffer = item.buffer_id
            break
        end

        if firstBuffer then
            self._mainView:SwitchBuffer(firstBuffer)

            -- 更新配置
            self._mainView:Updates(function()
                self._mainView
                    :Border("none")
                    :Relative("editor")
                    :Size(
                        api.nvim_get_option_value("columns", {}) - 2,
                        api.nvim_get_option_value("lines", {}) - 2
                    )
                    :Pos(0, 0)
                    :Winbl(config.options.pos_keybind.transparency)
            end)

            self._mainView:Render()
            self:_setupMainViewKeyBindings()

            -- 确保 z-index 正确
            if self._subView:Valid() then
                self._subView:SetZIndex(100)
            end

            -- 添加：如果当前有选中的range，恢复高亮
            if self._current_item and self._current_item.range then
                self._mainView:SetHighlight({ self._current_item.range })
            end
        end
    else
        -- 保存当前配置后隐藏
        self._mainView:SaveCurrentConfig():HideView()
    end
end
function ClassController:ActionToggleSubView()
    if not self._subView:Valid() then
        -- 先完全重新生成内容
        local width, height = self:_generateSubViewContent()

        -- 更新配置
        self._subView:Updates(function()
            self._subView
                :Border("single")
                :Style("minimal")
                :Relative("editor")
                :Size(width, height)
                :Pos(0, api.nvim_get_option_value("columns", {}) - width - 2)
                :Winbl(config.options.pos_keybind.transparency)
                :Title(self._lsp:GetMethod().name, "center")
        end)

        -- 渲染视图
        self._subView:Render()

        self._subView:SetZIndex(100)

        -- 恢复键映射
        self:_setupSubViewKeyBindings()

        -- 恢复光标位置
        if self._current_item and self._current_item.uri then
            local lnum = self:_getCursorPosForUri(self._current_item.uri)
            local win = self._subView:GetWinID()
            if win then
                api.nvim_win_set_cursor(win, { lnum, 0 })
            end
        end
    else
        -- 保存当前配置后隐藏
        self._subView:SaveCurrentConfig():HideView()
    end
end

---@param fold boolean 是否全部折叠
function ClassController:ActionFoldAll(fold)
    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local changed = false

    -- 修改所有项目的折叠状态
    for uri, item in pairs(data) do
        if item.fold ~= fold then
            item.fold = fold
            changed = true
        end
    end

    if changed then
        -- 重新渲染
        local width, height = self:_generateSubViewContent()
        self._subView:Size(width, height)

        -- 恢复光标位置
        local lnum = self:_getCursorPosForUri(current_uri)
        api.nvim_win_set_cursor(self._subView:GetWinID(), { lnum, 0 })
    end
end

function ClassController:ActionEnterMainView()
    if self._mainView:Valid() then
        self._mainView:Focus()
    end
end

function ClassController:ActionBackToSubView()
    if self._subView:Valid() then
        self._subView:Focus()
    end
end

---@private
---@param params table
---@return integer
function ClassController:_findPositionFromParams(params)
    local lnum = 0
    local param_uri = params.textDocument.uri

    local file_lnum = nil
    local code_lnum = nil
    local tmp = nil

    for uri, data in pairs(self._lsp:GetData()) do
        lnum = lnum + 1
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum + 1
                if tools.compare_uri(uri, param_uri) then
                    if not file_lnum then
                        file_lnum = lnum
                    end
                    if val.start.line == params.position.line then
                        if tmp then
                            if
                                math.abs(
                                    val.start.character
                                        - params.position.character
                                ) < tmp
                            then
                                tmp = math.abs(
                                    val.start.character
                                        - params.position.character
                                )
                                code_lnum = lnum
                            end
                        else
                            tmp = math.abs(
                                val.start.character - params.position.character
                            )
                            code_lnum = lnum
                        end
                    end
                end
            end
        end
    end

    if code_lnum then
        return code_lnum
    end
    if file_lnum then
        return file_lnum
    end

    local method = self._lsp:GetMethod()
    if method and method.fold then
        return 1
    end
    return 2
end

return ClassController
