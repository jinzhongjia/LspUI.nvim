local api = vim.api
local ClassLsp = require("LspUI.layer.lsp")
local ClassMainView = require("LspUI.layer.main_view")
local ClassSubView = require("LspUI.layer.sub_view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

-- 添加全局单例实例
local _controller_instance = nil

---@class ClassController
---@field _lsp ClassLsp
---@field _mainView ClassMainView
---@field _subView ClassSubView
---@field _current_item {uri: string, buffer_id: integer, range: LspUIRange?}
---@field origin_win integer?
local ClassController = {
    ---@diagnostic disable-next-line: assign-type-mismatch
    _lsp = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _mainView = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _subView = nil,
    _current_item = {},
    _debounce_delay = 50, -- 50ms 的防抖延迟
}

ClassController.__index = ClassController

---@return ClassController
function ClassController:New()
    -- 如果存在全局实例，直接返回
    if _controller_instance then
        return _controller_instance
    end

    local obj = {}
    setmetatable(obj, self)

    obj._lsp = ClassLsp:New()
    obj._mainView = ClassMainView:New(false)
    obj._subView = ClassSubView:New(true)

    api.nvim_create_augroup("LspUI_SubView", { clear = true })

    api.nvim_create_augroup("LspUI_AutoClose", { clear = true })

    -- 保存为全局单例
    _controller_instance = obj
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

    -- 添加新变量用于收集语法高亮信息
    local syntax_regions = {}

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

        -- 确定文件类型
        local filetype = vim.filetype.match({ filename = file_full_name }) or ""

        -- 计算相对路径，用于extmark
        local rel_path = ""
        local norm_file_path =
            normalize_path(vim.fn.fnamemodify(file_full_name, ":p"))

        -- 在 _generateSubViewContent 函数中修改以下代码
        if norm_file_path:sub(1, #cwd) == cwd then
            -- 如果文件在工作目录下，显示相对路径
            local rel_to_cwd = file_full_name:sub(#vim.fn.getcwd() + 1)

            -- 去除可能存在的开头斜杠
            if rel_to_cwd:sub(1, 1) == "/" or rel_to_cwd:sub(1, 1) == "\\" then
                rel_to_cwd = rel_to_cwd:sub(2)
            end

            -- 获取相对路径的目录部分
            local rel_dir = vim.fn.fnamemodify(rel_to_cwd, ":h")

            -- 总是以 ./ 开头显示
            if rel_dir == "." then
                rel_path = " (./)" -- 文件在工作区根目录
            else
                rel_path = " (./" .. rel_dir .. ")" -- 文件在子目录
            end
        else
            -- 否则显示绝对目录路径
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

        -- 初始化该语言的语法高亮区域
        if not syntax_regions[filetype] and filetype ~= "" then
            syntax_regions[filetype] = {}
        end

        for _, row in pairs(uri_rows) do
            local line_code = vim.fn.trim(lines[row] or "")
            local code_fmt = string.format("   %s", line_code)

            -- 如果未折叠，添加到内容
            if not item.fold then
                -- 当前行在内容中的索引
                table.insert(content, code_fmt)

                if filetype ~= "" then
                    local line_content = content[#content] -- 获取刚添加的内容
                    table.insert(syntax_regions[filetype], {
                        line = #content - 1, -- 行号 (0-based)
                        col_start = 3, -- 开始列（跳过前导空格）
                        col_end = #line_content, -- 结束列（使用实际内容长度）
                    })
                end
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

    -- 应用语法高亮
    self._subView:ApplySyntaxHighlight(syntax_regions)

    -- 设置高亮
    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
    api.nvim_buf_clear_namespace(bufId, subViewNamespace, 0, -1)

    -- 对文件名行应用高亮
    for _, lnum in pairs(hl_lines) do
        vim.highlight.range(
            bufId,
            subViewNamespace,
            "Directory",
            { lnum - 1, 3 },
            { lnum - 1, -1 },
            { priority = vim.highlight.priorities.user }
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
        -- 获取当前缓冲区，用于后面的按键映射恢复
        local current_buf = self._mainView:GetBufID()

        -- 切换缓冲区前先暂时解除固定
        self._mainView:UnPinBuffer()

        -- 如果当前缓冲区有效，先恢复它的按键映射
        if
            current_buf
            and current_buf ~= self._lsp:GetData()[uri].buffer_id
        then
            self._mainView:RestoreKeyMappings(current_buf)
        end

        -- 切换主视图缓冲区
        local bufId = self._lsp:GetData()[uri].buffer_id
        self._mainView:SwitchBuffer(bufId)

        -- 为新缓冲区保存原始按键映射，然后设置新的按键映射
        self._mainView:SaveKeyMappings(bufId)
        self:_setupMainViewKeyBindings()

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

        -- 设置高亮
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

-- 公开API开始
---@param method_name string
---@param buffer_id integer
---@param params table
---@param origin_win integer?
-- 修改 ClassController:Go 方法
function ClassController:Go(method_name, buffer_id, params, origin_win)
    -- 检查现有视图状态
    local mainViewValid = self._mainView and self._mainView:Valid()

    -- 如果主视图有效，需要恢复当前缓冲区的按键映射
    if mainViewValid then
        local currentBuffer = self._mainView:GetBufID()
        if currentBuffer and api.nvim_buf_is_valid(currentBuffer) then
            self._mainView:RestoreKeyMappings(currentBuffer)
        end
    end

    -- 设置方法
    if not self._lsp:SetMethod(method_name) then
        return
    end

    self.origin_win = origin_win or api.nvim_get_current_win()

    -- 发起LSP请求
    self._lsp:Request(buffer_id, params, function(data)
        if not data or vim.tbl_isempty(data) then
           if method_name == ClassLsp.methods.incoming_calls.name then 
                notify.Info("No references found for this function/method")
            elseif method_name == ClassLsp.methods.outgoing_calls.name then
                notify.Info(
                    "No calls found from this function/method"
                )
            else
                notify.Info(string.format("Could not find %s", method_name))
            end
            return
        end

        -- 计算结果总数和URI数量
        local total_results = 0
        local uri_count = 0
        local single_uri, single_range
        local only_uri

        -- 遍历所有URI的结果
        for uri, item in pairs(data) do
            uri_count = uri_count + 1
            only_uri = uri -- 记录URI，如果只有一个文件会用到
            total_results = total_results + #item.range

            -- 如果只有一个结果，记录它的位置信息
            if total_results == 1 and #item.range == 1 then
                single_uri = uri
                single_range = item.range[1]
            elseif total_results > 1 then
                -- 一旦发现多于一个结果，仍继续计数，我们需要得到总结果数和URI数
                single_uri = nil
                single_range = nil
            end
        end

        -- 如果只有一个结果，直接跳转
        if total_results == 1 and single_uri and single_range then
            -- 执行标签栈
            tools.save_position_to_jumplist()

            -- 打开文件
            local uri_buffer_id = vim.uri_to_bufnr(single_uri)
            if tools.buffer_is_listed(uri_buffer_id) then
                vim.cmd(string.format("buffer %s", uri_buffer_id))
            else
                vim.cmd(
                    string.format(
                        "edit %s",
                        vim.fn.fnameescape(vim.uri_to_fname(single_uri))
                    )
                )
            end

            -- 设置光标位置
            api.nvim_win_set_cursor(0, {
                single_range.start.line + 1,
                single_range.start.character,
            })
            vim.cmd("norm! zz")

            notify.Info(
                string.format("Jumped to the only %s location", method_name)
            )
            return
        end

        -- 如果只有一个文件但有多个结果，自动展开该文件（适用于所有方法）
        if uri_count == 1 and only_uri then
            -- 确保该URI的fold状态为false（展开）
            if data[only_uri] then
                data[only_uri].fold = false
            end
        end

        -- 渲染视图，无论视图是否已存在
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
    -- 检查视图是否存在
    local mainViewValid = self._mainView and self._mainView:Valid()
    local subViewValid = self._subView and self._subView:Valid()

    -- 如果视图已存在，先保存其状态并清理
    if mainViewValid then
        -- 解除缓冲区固定
        self._mainView:UnPinBuffer()
    end

    if subViewValid then
        local bufId = self._subView:GetBufID()
        if bufId then
            -- 既然视图存在，只需清理而不销毁
            api.nvim_buf_clear_namespace(
                bufId,
                api.nvim_create_namespace("LspUISubView"),
                0,
                -1
            )
        end
    end

    -- 创建副视图或更新现有副视图
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

    -- 如果副视图不存在，渲染它
    if not subViewValid then
        self._subView:Render()
    end

    -- 获取第一个URI对应的缓冲区作为MainView的初始缓冲区
    local firstBuffer = nil
    for _, item in pairs(self._lsp:GetData()) do
        firstBuffer = item.buffer_id
        break
    end

    -- 创建或更新主视图
    if firstBuffer then
        self._mainView:SwitchBuffer(firstBuffer)

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

        -- 如果主视图不存在，渲染它
        if not mainViewValid then
            self._mainView:Render()
        end

        -- 设置主视图为固定状态
        self._mainView:PinBuffer()

        -- 设置或更新绑定关系
        self._mainView:BindView(self._subView)
        self._subView:SetZIndex(100)

        -- 初始化主视图键绑定
        self:_setupMainViewKeyBindings()
    else
        -- 如果找不到初始缓冲区，记录警告
       notify.Warn("No available buffer found to initialize main view") 
    end

    -- 设置自动关闭功能
    self:SetupAutoClose()
end

-- 添加新方法用于设置自动关闭功能
function ClassController:SetupAutoClose()
    -- 清除可能已存在的自动命令
    api.nvim_clear_autocmds({ group = "LspUI_AutoClose" })

    -- 如果两个视图都不存在，则不需要设置自动命令
    if not (self._mainView:Valid() or self._subView:Valid()) then
        return
    end

    local self_ref = self

    -- 创建监控WinEnter事件的自动命令
    api.nvim_create_autocmd("WinEnter", {
        group = "LspUI_AutoClose",
        callback = function()
            -- 获取当前窗口ID
            local current_win = api.nvim_get_current_win()

            -- 获取MainView和SubView的窗口ID
            local main_win = self_ref._mainView:GetWinID()
            local sub_win = self_ref._subView:GetWinID()

            -- 检查当前窗口是否是MainView或SubView
            if current_win ~= main_win and current_win ~= sub_win then
                -- 如果不是，则销毁视图
                self_ref:ActionQuit()
                return true -- 移除自动命令
            end
        end,
        desc = tools.command_desc(
            "Auto close views when cursor enters other windows"
        ),
    })

    return self
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

    if api.nvim_win_is_valid(self.origin_win) then
        api.nvim_win_call(self.origin_win, function()
            tools.save_position_to_jumplist()
        end)
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
    self._subView:Destroy() -- 会同时销毁绑定的mainView

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
        ---@diagnostic disable-next-line: param-type-mismatch
        and api.nvim_win_is_valid(self._subView:GetWinID())
    then
        ---@diagnostic disable-next-line: param-type-mismatch
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
                    ---@diagnostic disable-next-line: param-type-mismatch
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
    -- 先清除主视图的高亮
    if self._mainView:Valid() then
        self._mainView:ClearHighlight()
        self._mainView:UnPinBuffer()
    end

    -- 清除子视图的语法高亮
    if self._subView:Valid() then
        self._subView:ClearSyntaxHighlight()
    end

    -- 使用 Destroy 会同时销毁两个视图，因为它们是绑定的
    self._subView:Destroy()
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

    -- 在函数末尾添加
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

    self:SetupAutoClose()
end

---@param fold boolean 是否全部折叠
function ClassController:ActionFoldAll(fold)
    local current_uri = self._current_item.uri
    local data = self._lsp:GetData()
    local changed = false

    -- 修改所有项目的折叠状态
    for _, item in pairs(data) do
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
        ---@diagnostic disable-next-line: param-type-mismatch
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

return ClassController
