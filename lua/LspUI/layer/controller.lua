local api = vim.api
local ClassLsp = require("LspUI.layer.lsp")
local ClassMainView = require("LspUI.layer.main_view")
local ClassSubView = require("LspUI.layer.sub_view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")
local search = require("LspUI.layer.search")
local jump_history = require("LspUI.layer.jump_history")

-- 添加全局单例实例
local _controller_instance = nil

---@class ClassController
---@field _lsp ClassLsp
---@field _mainView ClassMainView
---@field _subView ClassSubView
---@field _current_item {uri: string, buffer_id: integer, range: LspUIRange?}
---@field origin_win integer?
---@field _search_state table
---@field _virtual_scroll table
---@field _jump_history_state table
local ClassController = {
    ---@diagnostic disable-next-line: assign-type-mismatch
    _lsp = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _mainView = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _subView = nil,
    _current_item = {},
    _debounce_delay = 50, -- 50ms 的防抖延迟
    _search_state = nil, -- 搜索状态
    _jump_history_state = nil, -- 跳转历史状态
    _current_method_name = nil, -- 当前 LSP 方法名
    _virtual_scroll = {
        enabled = false,            -- 是否启用虚拟滚动
        threshold = 500,            -- 超过此数量的项目启用虚拟滚动
        chunk_size = 200,           -- 每次渲染的文件数
        loaded_file_count = 0,      -- 已加载的文件数
        total_file_count = 0,       -- 总文件数
        load_more_threshold = 50,   -- 距离底部多少行时触发加载
        uri_list = {},              -- 有序的 URI 列表
        is_loading = false,         -- 是否正在加载
    },
}

ClassController.__index = ClassController

--- 统计总文件数和总行数
---@param data table LSP 数据
---@return integer, integer 文件数，总行数（展开后）
local function count_items(data)
    local file_count = 0
    local total_lines = 0
    
    for _, item in pairs(data) do
        file_count = file_count + 1
        total_lines = total_lines + 1  -- 文件标题行
        
        if not item.fold then
            total_lines = total_lines + #item.range  -- 代码行
        end
    end
    
    return file_count, total_lines
end

--- 将数据按 URI 排序并切片
---@param data table LSP 数据
---@param start_file integer 开始文件索引 (0-based)
---@param end_file integer 结束文件索引 (不包含)
---@return table 切片后的数据 {uri -> item}
local function slice_data_by_files(data, start_file, end_file)
    -- 先获取并排序所有 URI（确保顺序稳定）
    local uri_list = {}
    for uri in pairs(data) do
        table.insert(uri_list, uri)
    end
    table.sort(uri_list)
    
    -- 切片
    local sliced = {}
    for i = start_file + 1, math.min(end_file, #uri_list) do
        local uri = uri_list[i]
        sliced[uri] = data[uri]
    end
    
    return sliced, uri_list
end

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
    obj._search_state = search.new_state() -- 初始化搜索状态
    
    -- 初始化跳转历史（使用配置）
    local history_config = config.options.jump_history or {}
    local max_size = history_config.max_size or 50
    obj._jump_history_state = jump_history.new_state(max_size)
    obj._jump_history_state.enabled = history_config.enable ~= false
    
    -- 初始化虚拟滚动状态
    obj._virtual_scroll = {
        enabled = false,
        threshold = 500,
        chunk_size = 200,
        loaded_file_count = 0,
        total_file_count = 0,
        load_more_threshold = 50,
        uri_list = {},
        is_loading = false,
        -- 搜索过滤模式
        search_mode = false,           -- 是否在搜索过滤模式
        matched_uri_list = {},         -- 匹配的 URI 列表（有序）
        loaded_match_count = 0,        -- 已加载的匹配数
        total_match_count = 0,         -- 总匹配数
    }

    api.nvim_create_augroup("LspUI_SubView", { clear = true })

    api.nvim_create_augroup("LspUI_AutoClose", { clear = true })

    -- 保存为全局单例
    _controller_instance = obj
    return obj
end

--- 获取全局控制器实例
---@return ClassController?
function ClassController:GetInstance()
    return _controller_instance
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

    -- 统计文件数量
    local file_count, _ = count_items(data)
    
    -- 判断是否需要启用虚拟滚动
    local use_virtual_scroll = file_count > self._virtual_scroll.threshold
    
    if use_virtual_scroll then
        return self:_generateSubViewContentVirtual(data, bufId, file_count)
    else
        return self:_generateSubViewContentFull(data, bufId)
    end
end

--- 完整渲染（小列表）
---@private
function ClassController:_generateSubViewContentFull(data, bufId)
    -- 禁用虚拟滚动
    self._virtual_scroll.enabled = false
    
    -- 直接调用渲染函数
    return self:_renderSubViewData(data, bufId)
end

--- 虚拟渲染（大列表，分批加载）
---@private
function ClassController:_generateSubViewContentVirtual(data, bufId, total_file_count)
    -- 启用虚拟滚动
    self._virtual_scroll.enabled = true
    self._virtual_scroll.total_file_count = total_file_count
    
    -- 获取有序的 URI 列表
    local uri_list = {}
    for uri in pairs(data) do
        table.insert(uri_list, uri)
    end
    table.sort(uri_list)
    self._virtual_scroll.uri_list = uri_list
    
    -- 初始只加载前 chunk_size 个文件
    local chunk_size = self._virtual_scroll.chunk_size
    local end_idx = math.min(chunk_size, total_file_count)
    
    -- 切片数据
    local sliced_data = {}
    for i = 1, end_idx do
        local uri = uri_list[i]
        sliced_data[uri] = data[uri]
    end
    
    -- 调用完整渲染函数渲染切片数据
    local width, height = self:_renderSubViewData(sliced_data, bufId)
    
    -- 添加"加载更多"提示
    if end_idx < total_file_count then
        local remaining = total_file_count - end_idx
        api.nvim_set_option_value("modifiable", true, { buf = bufId })
        api.nvim_buf_set_lines(bufId, -1, -1, false, {
            "",
            string.format("... (%d more files, scroll down to load)", remaining)
        })
        api.nvim_set_option_value("modifiable", false, { buf = bufId })
        height = height + 2
    end
    
    self._virtual_scroll.loaded_file_count = end_idx
    
    return width, height
end

--- 渲染数据到 SubView（核心渲染逻辑，被完整渲染和虚拟渲染共用）
---@private
function ClassController:_renderSubViewData(data, bufId)
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
        local result = path:gsub("\\", "/")
        if vim.fn.has("win32") == 1 then
            result = result:lower()
        end
        if result:sub(-1) ~= "/" then
            result = result .. "/"
        end
        return result
    end

    local function normalize_display_path(path)
        return path:gsub("\\", "/")
    end

    local cwd = normalize_path(vim.fn.getcwd())

    -- 生成内容（与原逻辑相同）
    for uri, item in pairs(data) do
        local file_full_name = vim.uri_to_fname(uri)
        local file_name = vim.fn.fnamemodify(file_full_name, ":t")
        local filetype = tools.detect_filetype(file_full_name)

        local rel_path = ""
        local norm_file_path = normalize_path(vim.fn.fnamemodify(file_full_name, ":p"))

        if norm_file_path:sub(1, #cwd) == cwd then
            local rel_to_cwd = file_full_name:sub(#vim.fn.getcwd() + 1)
            if rel_to_cwd:sub(1, 1) == "/" or rel_to_cwd:sub(1, 1) == "\\" then
                rel_to_cwd = rel_to_cwd:sub(2)
            end
            rel_to_cwd = normalize_display_path(rel_to_cwd)
            local rel_dir = vim.fn.fnamemodify(rel_to_cwd, ":h")
            rel_dir = normalize_display_path(rel_dir)
            if rel_dir == "." then
                rel_path = " (./)"
            else
                rel_path = " (./" .. rel_dir .. ")"
            end
        else
            local dir = vim.fn.fnamemodify(file_full_name, ":h")
            dir = normalize_display_path(dir)
            rel_path = " (" .. dir .. ")"
        end

        local file_fmt = string.format(" %s %s", item.fold and "▶" or "▼", file_name)
        table.insert(content, file_fmt)
        table.insert(hl_lines, #content)

        if rel_path ~= "" then
            table.insert(extmarks, {
                line = #content - 1,
                text = rel_path,
                hl_group = "Comment",
            })
        end

        local file_fmt_len = vim.fn.strdisplaywidth(file_fmt)
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        local uri_rows = {}
        for _, range in ipairs(item.range) do
            table.insert(uri_rows, range.start.line)
        end

        local lines = tools.GetUriLines(item.buffer_id, uri, uri_rows)

        if not syntax_regions[filetype] and filetype ~= "" then
            syntax_regions[filetype] = {}
        end

        for _, row in pairs(uri_rows) do
            local line_code = vim.fn.trim(lines[row] or "")
            local code_fmt = string.format("   %s", line_code)

            if not item.fold then
                table.insert(content, code_fmt)

                if filetype and filetype ~= "" then
                    local line_content = content[#content]
                    local region_data = {
                        line = #content - 1,
                        col_start = 3,
                        col_end = #line_content,
                    }
                    table.insert(syntax_regions[filetype], region_data)
                end
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
        if mark.line >= 0 and mark.line < #content then
            local line_content = content[mark.line + 1] or ""
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
    local max_columns = math.floor(api.nvim_get_option_value("columns", {}) * 0.3)

    if max_columns > res_width then
        res_width = max_columns
    end

    return res_width, #content + 1
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
        -- 搜索功能键绑定
        ["/"] = function()
            self:ActionSearch()
        end,
        ["n"] = function()
            self:ActionSearchNext()
        end,
        ["N"] = function()
            self:ActionSearchPrev()
        end,
        ["<ESC>"] = function()
            -- ESC 只在搜索启用时清除搜索，否则不做任何操作
            if self._search_state.enabled then
                self:ActionClearSearch()
            end
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
    
    -- 检查是否需要加载更多（虚拟滚动）
    if self._virtual_scroll.enabled then
        self:_checkAndLoadMore()
    end
end

--- 检查并加载更多内容（虚拟滚动）
---@private
function ClassController:_checkAndLoadMore()
    -- 如果已经全部加载或正在加载，跳过
    if self._virtual_scroll.is_loading then
        return
    end
    
    if self._virtual_scroll.loaded_file_count >= self._virtual_scroll.total_file_count then
        return
    end
    
    local winid = self._subView:GetWinID()
    local bufnr = self._subView:GetBufID()
    
    if not winid or not bufnr then
        return
    end
    
    -- 获取当前光标位置和总行数
    local cursor_line = api.nvim_win_get_cursor(winid)[1]
    local total_lines = api.nvim_buf_line_count(bufnr)
    
    -- 如果距离底部小于阈值，触发加载
    if total_lines - cursor_line < self._virtual_scroll.load_more_threshold then
        self:_loadMoreItems()
    end
end

--- 加载更多项目（虚拟滚动）
---@private
function ClassController:_loadMoreItems()
    if self._virtual_scroll.is_loading then
        return
    end
    
    self._virtual_scroll.is_loading = true
    
    local vs = self._virtual_scroll
    local data = self._lsp:GetData()
    local bufnr = self._subView:GetBufID()
    
    if not bufnr then
        self._virtual_scroll.is_loading = false
        return
    end
    
    -- 根据是否在搜索模式选择不同的加载策略
    local start_idx, end_idx, uri_list, total_count
    
    if vs.search_mode then
        -- 搜索过滤模式:从匹配列表加载
        uri_list = vs.matched_uri_list
        start_idx = vs.loaded_match_count + 1
        total_count = vs.total_match_count
        end_idx = math.min(start_idx + vs.chunk_size - 1, total_count)
    else
        -- 普通虚拟滚动模式:从完整列表加载
        uri_list = vs.uri_list
        start_idx = vs.loaded_file_count + 1
        total_count = vs.total_file_count
        end_idx = math.min(start_idx + vs.chunk_size - 1, total_count)
    end
    
    -- 获取要加载的 URI
    local new_data = {}
    for i = start_idx, end_idx do
        local uri = uri_list[i]
        if data[uri] then
            new_data[uri] = data[uri]
        end
    end
    
    -- 移除旧的提示行
    api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    local line_count = api.nvim_buf_line_count(bufnr)
    if line_count >= 2 then
        api.nvim_buf_set_lines(bufnr, line_count - 2, line_count, false, {})
    end
    
    -- 生成新内容并追加（复用渲染逻辑）
    local append_start_line = api.nvim_buf_line_count(bufnr)
    local width, height = self:_appendSubViewData(new_data, bufnr, append_start_line)
    
    -- 添加新的提示（如果还有更多）
    if end_idx < total_count then
        local remaining = total_count - end_idx
        local tip_text = vs.search_mode
            and string.format("... (%d more matched files, scroll down to load)", remaining)
            or string.format("... (%d more files, scroll down to load)", remaining)
            
        api.nvim_buf_set_lines(bufnr, -1, -1, false, {
            "",
            tip_text
        })
    end
    
    api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    
    -- 更新状态
    if vs.search_mode then
        vs.loaded_match_count = end_idx
    else
        vs.loaded_file_count = end_idx
    end
    vs.is_loading = false
    
    -- 重新应用搜索高亮(如果在搜索模式)
    if self._search_state.enabled then
        self:_reapplySearchHighlight()
    end
    
    -- 更新状态显示
    self:_updateSearchStatus()
    
    -- 更新窗口大小
    local total_height = api.nvim_buf_line_count(bufnr)
    self._subView:Size(width, total_height)
end

--- 追加数据到 SubView（用于虚拟滚动动态加载）
---@private
function ClassController:_appendSubViewData(data, bufId, start_line)
    -- 这个函数类似 _renderSubViewData，但是追加内容而不是替换
    local extmark_ns = api.nvim_create_namespace("LspUIPathExtmarks")
    local hl_lines = {}
    local content = {}
    local extmarks = {}
    local max_width = 30  -- 默认最小宽度
    local syntax_regions = {}
    
    -- 复用路径处理函数
    local function normalize_path(path)
        local result = path:gsub("\\", "/")
        if vim.fn.has("win32") == 1 then
            result = result:lower()
        end
        if result:sub(-1) ~= "/" then
            result = result .. "/"
        end
        return result
    end
    
    local function normalize_display_path(path)
        return path:gsub("\\", "/")
    end
    
    local cwd = normalize_path(vim.fn.getcwd())
    
    -- 生成内容
    for uri, item in pairs(data) do
        local file_full_name = vim.uri_to_fname(uri)
        local file_name = vim.fn.fnamemodify(file_full_name, ":t")
        local filetype = tools.detect_filetype(file_full_name)
        
        local rel_path = ""
        local norm_file_path = normalize_path(vim.fn.fnamemodify(file_full_name, ":p"))
        
        if norm_file_path:sub(1, #cwd) == cwd then
            local rel_to_cwd = file_full_name:sub(#vim.fn.getcwd() + 1)
            if rel_to_cwd:sub(1, 1) == "/" or rel_to_cwd:sub(1, 1) == "\\" then
                rel_to_cwd = rel_to_cwd:sub(2)
            end
            rel_to_cwd = normalize_display_path(rel_to_cwd)
            local rel_dir = vim.fn.fnamemodify(rel_to_cwd, ":h")
            rel_dir = normalize_display_path(rel_dir)
            if rel_dir == "." then
                rel_path = " (./)"
            else
                rel_path = " (./" .. rel_dir .. ")"
            end
        else
            local dir = vim.fn.fnamemodify(file_full_name, ":h")
            dir = normalize_display_path(dir)
            rel_path = " (" .. dir .. ")"
        end
        
        local file_fmt = string.format(" %s %s", item.fold and "▶" or "▼", file_name)
        table.insert(content, file_fmt)
        table.insert(hl_lines, start_line + #content)
        
        if rel_path ~= "" then
            table.insert(extmarks, {
                line = start_line + #content - 1,
                text = rel_path,
                hl_group = "Comment",
            })
        end
        
        local file_fmt_len = vim.fn.strdisplaywidth(file_fmt)
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end
        
        local uri_rows = {}
        for _, range in ipairs(item.range) do
            table.insert(uri_rows, range.start.line)
        end
        
        local lines = tools.GetUriLines(item.buffer_id, uri, uri_rows)
        
        if not syntax_regions[filetype] and filetype ~= "" then
            syntax_regions[filetype] = {}
        end
        
        for _, row in pairs(uri_rows) do
            local line_code = vim.fn.trim(lines[row] or "")
            local code_fmt = string.format("   %s", line_code)
            
            if not item.fold then
                table.insert(content, code_fmt)
                
                if filetype and filetype ~= "" then
                    local line_content = content[#content]
                    local region_data = {
                        line = start_line + #content - 1,
                        col_start = 3,
                        col_end = #line_content,
                    }
                    table.insert(syntax_regions[filetype], region_data)
                end
            end
        end
    end
    
    -- 追加内容
    api.nvim_buf_set_lines(bufId, start_line, start_line, false, content)
    
    -- 应用语法高亮
    self._subView:ApplySyntaxHighlight(syntax_regions)
    
    -- 设置高亮
    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
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
    
    -- 添加 extmark
    for _, mark in ipairs(extmarks) do
        local line_content = api.nvim_buf_get_lines(bufId, mark.line, mark.line + 1, false)[1] or ""
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
    
    local res_width = max_width + 2 > 30 and 30 or max_width + 2
    return res_width, #content
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

    -- 保存当前方法名（用于历史记录）
    self._current_method_name = method_name

    self.origin_win = origin_win or api.nvim_get_current_win()

    -- 发起LSP请求
    self._lsp:Request(buffer_id, params, function(data)
        if not data or vim.tbl_isempty(data) then
            if method_name == ClassLsp.methods.incoming_calls.name then
                notify.Info("No references found for this function/method")
            elseif method_name == ClassLsp.methods.outgoing_calls.name then
                notify.Info("No calls found from this function/method")
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

        -- 如果只有一个结果，检查是否就是当前位置
        if total_results == 1 and single_uri and single_range then
            -- 检查是否为当前位置 (相同文件和光标在范围内)
            local current_uri = vim.uri_from_bufnr(buffer_id)
            local is_same_file = tools.compare_uri(current_uri, single_uri)

            local is_current_position = false
            if is_same_file then
                local cursor_line = params.position.line
                local cursor_char = params.position.character

                -- 优先检查选择范围，如果没有则使用完整范围
                local check_range = {
                    start = single_range.selection_start or single_range.start,
                    finish = single_range.selection_finish
                        or single_range.finish,
                }

                -- 检查光标是否在范围内
                if
                    cursor_line >= check_range.start.line
                    and cursor_line <= check_range.finish.line
                then
                    if
                        cursor_line == check_range.start.line
                        and cursor_line == check_range.finish.line
                    then
                        -- 单行范围：检查字符位置
                        is_current_position = cursor_char
                                >= check_range.start.character
                            and cursor_char <= check_range.finish.character
                    elseif cursor_line == check_range.start.line then
                        -- 起始行：光标需要在起始字符之后
                        is_current_position = cursor_char
                            >= check_range.start.character
                    elseif cursor_line == check_range.finish.line then
                        -- 结束行：光标需要在结束字符之前
                        is_current_position = cursor_char
                            <= check_range.finish.character
                    else
                        -- 中间行：光标在范围内
                        is_current_position = true
                    end
                end
            end

            if is_current_position then
                notify.Info(
                    string.format("This is the only %s position", method_name)
                )
                return
            end

            -- 准备跳转信息
            local target_line = single_range.selection_start.line + 1
            local target_col = single_range.selection_start.character
            local target_buf = vim.uri_to_bufnr(single_uri)

            -- 获取配置
            local history_config = config.options.jump_history or {}
            local smart_config = history_config.smart_jumplist or {}

            -- 1️⃣ 记录到原生 jumplist（智能判断）
            tools.smart_save_to_jumplist(target_buf, target_line, {
                min_distance = smart_config.min_distance or 5,
                cross_file_only = smart_config.cross_file_only or false,
            })

            -- 2️⃣ 记录到增强历史（如果启用）
            if self._jump_history_state and self._jump_history_state.enabled then
                local history_item = jump_history.create_item({
                    uri = single_uri,
                    line = target_line,
                    col = target_col,
                    buffer_id = target_buf,
                    lsp_type = method_name,
                })
                jump_history.add_item(self._jump_history_state, history_item)
            end

            -- 打开文件
            if tools.buffer_is_listed(target_buf) then
                vim.cmd(string.format("buffer %s", target_buf))
            else
                vim.cmd(
                    string.format(
                        "edit %s",
                        vim.fn.fnameescape(vim.uri_to_fname(single_uri))
                    )
                )
            end

            -- 设置光标位置 - 使用选择范围而不是整个范围
            api.nvim_win_set_cursor(0, { target_line, target_col })
            
            -- 3️⃣ 确保目标位置也被记录
            tools.save_target_to_jumplist()
            
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
            :Border(config.options.pos_keybind.secondary_border)
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
        self._subView:PinBuffer()
        -- Set nowrap option to prevent text wrapping
        self._subView:Option("wrap", false)
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
                :Border(config.options.pos_keybind.main_border)
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

    -- 准备跳转目标信息
    local target_line = item.range.selection_start.line + 1
    local target_col = item.range.selection_start.character
    local target_buf = item.buffer_id

    -- 获取配置
    local history_config = config.options.jump_history or {}
    local smart_config = history_config.smart_jumplist or {}

    -- 1️⃣ 记录到原生 jumplist（智能判断）
    if api.nvim_win_is_valid(self.origin_win) then
        api.nvim_win_call(self.origin_win, function()
            tools.smart_save_to_jumplist(target_buf, target_line, {
                min_distance = smart_config.min_distance or 5,
                cross_file_only = smart_config.cross_file_only or false,
            })
        end)
    end

    -- 2️⃣ 记录到增强历史（如果启用）
    if self._jump_history_state and self._jump_history_state.enabled then
        local history_item = jump_history.create_item({
            uri = item.uri,
            line = target_line,
            col = target_col,
            buffer_id = target_buf,
            lsp_type = self._current_method_name or "unknown",
        })
        jump_history.add_item(self._jump_history_state, history_item)
    end

    -- 清除高亮
    if self._mainView:Valid() then
        self._mainView:ClearHighlight()
    end

    -- 关闭视图前先解除固定
    if self._mainView:Valid() then
        self._mainView:UnPinBuffer()
    end

    -- 关闭视图
    self._subView:Destroy()

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

    -- 设置光标位置 - 使用选择范围
    api.nvim_win_set_cursor(0, { target_line, target_col })
    
    -- 3️⃣ 确保目标位置也被记录到 jumplist
    tools.save_target_to_jumplist()
    
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
    
    -- 如果启用了虚拟滚动，需要确保该文件已加载
    if self._virtual_scroll.enabled then
        local uri_index = nil
        for i, u in ipairs(self._virtual_scroll.uri_list) do
            if u == uri then
                uri_index = i
                break
            end
        end
        
        -- 如果该文件未加载，需要先加载到该位置
        if uri_index and uri_index > self._virtual_scroll.loaded_file_count then
            -- 加载到该文件为止
            while self._virtual_scroll.loaded_file_count < uri_index and 
                  self._virtual_scroll.loaded_file_count < self._virtual_scroll.total_file_count do
                self:_loadMoreItems()
            end
        end
    end

    -- 切换折叠状态
    data[uri].fold = not data[uri].fold

    -- 重新生成SubView内容
    local width, height = self:_generateSubViewContent()
    self._subView:Size(width, height)
    
    -- 重新应用搜索高亮（如果搜索已启用）
    self:_reapplySearchHighlight()

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
                    :Border(config.options.pos_keybind.main_border)
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
                :Border(config.options.pos_keybind.secondary_border)
                :Style("minimal")
                :Relative("editor")
                :Size(width, height)
                :Pos(0, api.nvim_get_option_value("columns", {}) - width - 2)
                :Winbl(config.options.pos_keybind.transparency)
                :Title(self._lsp:GetMethod().name, "center")
        end)

        -- 渲染视图
        self._subView:Render()
        self._subView:PinBuffer()
        -- Set nowrap option to prevent text wrapping
        self._subView:Option("wrap", false)

        self._subView:SetZIndex(100)

        -- 恢复键映射
        self:_setupSubViewKeyBindings()
        
        -- 重新应用搜索高亮
        self:_reapplySearchHighlight()

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
        
        -- 重新应用搜索高亮
        self:_reapplySearchHighlight()

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

-- ============================================
-- 搜索功能
-- ============================================

--- 进入搜索模式
function ClassController:ActionSearch()
    local bufnr = self._subView:GetBufID()
    if not bufnr then
        return
    end

    local vs = self._virtual_scroll
    
    -- 虚拟滚动模式下搜索全部数据
    if vs.enabled then
        -- 获取当前数据
        local data = self._lsp:GetData()
        
        if not data then
            return
        end
        
        -- 进入搜索输入
        search.enter_search_mode(
            bufnr,
            self._search_state,
            -- 搜索变化回调
            function(state)
                if state.pattern and state.pattern ~= "" then
                    -- 搜索全部数据并切换到过滤模式
                    local matched_uris = self:_searchInAllData(state.pattern)
                    
                    vs.search_mode = true
                    vs.matched_uri_list = matched_uris
                    vs.loaded_match_count = 0
                    vs.total_match_count = #matched_uris
                    
                    -- 重新渲染 (只显示匹配的文件)
                    self:_generateSubViewContentSearchFiltered(data, bufnr)
                    
                    -- 重新应用搜索高亮
                    self:_reapplySearchHighlight()
                end
                
                self:_updateSearchStatus()
                
                -- 跳转到第一个匹配
                if state.match_count > 0 then
                    self:ActionSearchNext()
                end
            end,
            -- 退出回调
            function(state)
                -- 退出搜索模式,恢复完整视图
                if vs.search_mode then
                    vs.search_mode = false
                    vs.matched_uri_list = {}
                    vs.loaded_match_count = 0
                    vs.total_match_count = 0
                    
                    -- 重新生成完整内容
                    local data_full = self._lsp:GetData()
                    
                    if data_full then
                        -- 重新计算并渲染
                        vs.loaded_file_count = 0
                        self:_generateSubViewContent(data_full)
                    end
                end
                
                self:_updateSearchStatus()
            end
        )
    else
        -- 非虚拟滚动模式,使用原有逻辑
        search.enter_search_mode(
            bufnr,
            self._search_state,
            -- 搜索变化回调
            function(state)
                self:_updateSearchStatus()
                -- 跳转到第一个匹配
                if state.match_count > 0 then
                    self:ActionSearchNext()
                end
            end,
            -- 退出回调
            function(state)
                self:_updateSearchStatus()
            end
        )
    end
end

--- 跳转到下一个匹配
function ClassController:ActionSearchNext()
    if not self._search_state.enabled or self._search_state.match_count == 0 then
        return
    end

    local winid = self._subView:GetWinID()
    if not winid then
        return
    end

    local current_line = api.nvim_win_get_cursor(winid)[1] - 1
    local next_line = search.next_match(self._search_state, current_line)

    if next_line then
        api.nvim_win_set_cursor(winid, { next_line + 1, 0 })
        vim.cmd("norm! zz") -- 居中显示
    end
end

--- 跳转到上一个匹配
function ClassController:ActionSearchPrev()
    if not self._search_state.enabled or self._search_state.match_count == 0 then
        return
    end

    local winid = self._subView:GetWinID()
    if not winid then
        return
    end

    local current_line = api.nvim_win_get_cursor(winid)[1] - 1
    local prev_line = search.prev_match(self._search_state, current_line)

    if prev_line then
        api.nvim_win_set_cursor(winid, { prev_line + 1, 0 })
        vim.cmd("norm! zz") -- 居中显示
    end
end

--- 清除搜索
function ClassController:ActionClearSearch()
    local bufnr = self._subView:GetBufID()
    if bufnr then
        search.clear_search(bufnr, self._search_state)
        self:_updateSearchStatus()
    end
end

-- ============================================
-- 跳转历史功能
-- ============================================

--- 显示跳转历史列表
function ClassController:ActionShowHistory()
    local state = self._jump_history_state
    
    if not state or not state.enabled then
        notify.Info("Jump history is not enabled")
        return
    end
    
    -- 获取显示内容
    local lines = jump_history.get_display_lines(state)
    
    -- 创建浮动窗口
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    
    -- 计算窗口大小
    local width = 100
    local height = math.min(#lines, 20)
    
    -- 居中位置
    local ui = api.nvim_list_uis()[1]
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = (ui.width - width) / 2,
        row = (ui.height - height) / 2,
        style = "minimal",
        border = "rounded",
        title = " Jump History ",
        title_pos = "center",
    }
    
    local win = api.nvim_open_win(buf, true, win_opts)
    vim.wo[win].winhl = "Normal:Normal,FloatBorder:FloatBorder"
    
    -- 设置光标到最新记录（第3行，跳过标题）
    if #state.items > 0 then
        api.nvim_win_set_cursor(win, {3, 0})
    end
    
    -- 设置语法高亮
    vim.cmd([[
        syntax match HistoryTime /\[\d\d:\d\d:\d\d\]/
        syntax match HistoryType /│\s*\zs[a-zA-Z_]\+\ze\s*│/
        syntax match HistoryFile /│\s*\zs[^│]\+\.\w\+:\d\+\ze\s*│/
        syntax match HistorySeparator /[─│]/
        
        highlight default link HistoryTime Comment
        highlight default link HistoryType Keyword
        highlight default link HistoryFile Directory
        highlight default link HistorySeparator Comment
    ]])
    
    -- 绑定快捷键
    local function close_window()
        if api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
        end
    end
    
    local function jump_to_history()
        local cursor = api.nvim_win_get_cursor(win)
        local line_num = cursor[1]
        
        -- 获取对应的历史项索引
        local item_index = jump_history.get_item_index_from_display_line(line_num, #state.items)
        
        if item_index and state.items[item_index] then
            local item = state.items[item_index]
            
            -- 关闭历史窗口
            close_window()
            
            -- 跳转到历史位置
            local target_buf = item.buffer_id
            if not api.nvim_buf_is_valid(target_buf) then
                target_buf = vim.uri_to_bufnr(item.uri)
            end
            
            -- 打开文件
            if tools.buffer_is_listed(target_buf) then
                vim.cmd(string.format("buffer %s", target_buf))
            else
                vim.cmd(string.format("edit %s", vim.fn.fnameescape(item.file_path)))
            end
            
            -- 设置光标位置
            api.nvim_win_set_cursor(0, {item.line, item.col})
            vim.cmd("norm! zz")
            
            notify.Info(string.format("Jumped to history: %s:%d", item.file_name, item.line))
        end
    end
    
    local function delete_history_item()
        local cursor = api.nvim_win_get_cursor(win)
        local line_num = cursor[1]
        
        local item_index = jump_history.get_item_index_from_display_line(line_num, #state.items)
        
        if item_index and jump_history.remove_item(state, item_index) then
            -- 刷新显示
            local new_lines = jump_history.get_display_lines(state)
            vim.bo[buf].modifiable = true
            api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
            vim.bo[buf].modifiable = false
            
            -- 调整光标位置
            local new_line = math.min(line_num, #new_lines - 2)
            if new_line < 3 then new_line = 3 end
            api.nvim_win_set_cursor(win, {new_line, 0})
            
            notify.Info("History item deleted")
        end
    end
    
    local function clear_all_history()
        -- 确认对话框
        local confirm = vim.fn.confirm("Clear all jump history?", "&Yes\n&No", 2)
        if confirm == 1 then
            jump_history.clear_history(state)
            
            -- 刷新显示
            local new_lines = jump_history.get_display_lines(state)
            vim.bo[buf].modifiable = true
            api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
            vim.bo[buf].modifiable = false
            
            notify.Info("Jump history cleared")
        end
    end
    
    -- 键盘映射
    local opts = { noremap = true, silent = true, buffer = buf }
    
    vim.keymap.set("n", "<CR>", jump_to_history, opts)
    vim.keymap.set("n", "o", jump_to_history, opts)
    vim.keymap.set("n", "q", close_window, opts)
    vim.keymap.set("n", "<ESC>", close_window, opts)
    vim.keymap.set("n", "d", delete_history_item, opts)
    vim.keymap.set("n", "c", clear_all_history, opts)
    vim.keymap.set("n", "j", "j", opts)
    vim.keymap.set("n", "k", "k", opts)
    vim.keymap.set("n", "gg", "gg", opts)
    vim.keymap.set("n", "G", "G", opts)
end

--- 重新应用搜索高亮（在重新生成内容后调用）
---@private
function ClassController:_reapplySearchHighlight()
    if not self._search_state.enabled or self._search_state.pattern == "" then
        return
    end
    
    local bufnr = self._subView:GetBufID()
    if not bufnr then
        return
    end
    
    -- 重新应用搜索匹配和高亮
    search.update_matches(bufnr, self._search_state, true)
    self:_updateSearchStatus()
end

--- 在完整 LSP 数据中搜索匹配的文件（用于虚拟滚动场景）
---@private
---@param pattern string 搜索模式
---@return table 匹配的 URI 列表（有序）
function ClassController:_searchInAllData(pattern)
    local data = self._lsp:GetData()
    local matched_uris = {}
    local pattern_lower = pattern:lower()
    
    -- 遍历所有文件
    for uri, item in pairs(data) do
        local has_match = false
        
        -- 检查文件名是否匹配
        local file_full_name = vim.uri_to_fname(uri)
        local file_name = vim.fn.fnamemodify(file_full_name, ":t")
        
        if file_name:lower():find(pattern_lower, 1, true) then
            has_match = true
        else
            -- 检查代码行是否匹配
            local uri_rows = {}
            for _, range in ipairs(item.range) do
                table.insert(uri_rows, range.start.line)
            end
            
            local lines = tools.GetUriLines(item.buffer_id, uri, uri_rows)
            
            for _, row in pairs(uri_rows) do
                local line_code = lines[row] or ""
                if line_code:lower():find(pattern_lower, 1, true) then
                    has_match = true
                    break
                end
            end
        end
        
        if has_match then
            table.insert(matched_uris, uri)
        end
    end
    
    -- 排序保持顺序稳定
    table.sort(matched_uris)
    
    return matched_uris
end

--- 虚拟滚动 + 搜索过滤模式渲染
---@private
---@param data table LSP 数据
---@param bufId integer Buffer ID
---@return integer, integer 宽度和高度
function ClassController:_generateSubViewContentSearchFiltered(data, bufId)
    local vs = self._virtual_scroll
    local matched_uris = vs.matched_uri_list
    local chunk_size = vs.chunk_size
    local end_idx = math.min(vs.loaded_match_count + chunk_size, #matched_uris)
    
    -- 如果是第一次加载，从头开始
    if vs.loaded_match_count == 0 then
        end_idx = math.min(chunk_size, #matched_uris)
    end
    
    -- 只渲染匹配的文件
    local filtered_data = {}
    for i = 1, end_idx do
        local uri = matched_uris[i]
        if data[uri] then
            filtered_data[uri] = data[uri]
        end
    end
    
    -- 渲染
    local width, height = self:_renderSubViewData(filtered_data, bufId)
    
    -- 添加提示
    if end_idx < #matched_uris then
        api.nvim_set_option_value("modifiable", true, { buf = bufId })
        api.nvim_buf_set_lines(bufId, -1, -1, false, {
            "",
            string.format("... (%d more matched files, scroll down to load)", 
                         #matched_uris - end_idx)
        })
        api.nvim_set_option_value("modifiable", false, { buf = bufId })
        height = height + 2
    end
    
    vs.loaded_match_count = end_idx
    vs.total_match_count = #matched_uris
    
    return width, height
end

--- 更新搜索状态显示
function ClassController:_updateSearchStatus()
    local vs = self._virtual_scroll
    local virtual_scroll_info = nil
    
    -- 如果是虚拟滚动搜索过滤模式,传递信息
    if vs.enabled and vs.search_mode and vs.total_match_count > 0 then
        virtual_scroll_info = {
            loaded = vs.loaded_match_count,
            total = vs.total_match_count
        }
    end
    
    local status = search.get_status_line(self._search_state, virtual_scroll_info)
    
    if not self._subView:Valid() then
        return
    end

    local winid = self._subView:GetWinID()
    local current_winbar = vim.wo[winid].winbar or ""
    
    -- 移除旧的搜索状态
    current_winbar = current_winbar:gsub("%s*%[Search:.-]%s*", "")
    
    -- 添加新的搜索状态
    if status ~= "" then
        if current_winbar ~= "" then
            current_winbar = current_winbar .. " " .. status
        else
            current_winbar = status
        end
    end
    
    vim.wo[winid].winbar = current_winbar
end

return ClassController
