local api = vim.api
local fn = vim.fn
local ClassLsp = require("LspUI.layer.lsp")
local ClassMainView = require("LspUI.layer.main_view")
local ClassSubView = require("LspUI.layer.sub_view")
local config = require("LspUI.config")
local jump_history = require("LspUI.layer.jump_history")
local notify = require("LspUI.layer.notify")
local search = require("LspUI.layer.search")
local tools = require("LspUI.layer.tools")

---@class ClassController
---@field _lsp ClassLsp
---@field _mainView ClassMainView
---@field _subView ClassSubView
---@field _current_item {uri: string, buffer_id: integer, range: LspUIRange?}
---@field origin_win integer?
---@field _search_state table
---@field _virtual_scroll table
---@field _jump_history_state table
---@field _original_winbar string?
---@field _line_map table 行号到 URI 和 range 的映射表（性能优化：O(1) 查找）
local controller_singleton = nil

local ClassController = {
    ---@diagnostic disable-next-line: assign-type-mismatch
    _lsp = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _mainView = nil,
    ---@diagnostic disable-next-line: assign-type-mismatch
    _subView = nil,
    _current_item = {},
    _debounce_delay = 100, -- 100ms 的防抖延迟
    _search_state = nil, -- 搜索状态
    _jump_history_state = nil, -- 跳转历史状态
    _current_method_name = nil, -- 当前 LSP 方法名
    _virtual_scroll = nil, -- 虚拟滚动状态（在构造函数中初始化）
    _line_map = {}, -- 行号映射表（在构造函数中初始化）
}

ClassController.__index = ClassController

--- 获取全局控制器实例
--- @param create_if_missing boolean? 是否在不存在时创建实例，默认为 true
--- @return ClassController?
function ClassController.GetInstance(create_if_missing)
    if controller_singleton == nil and create_if_missing ~= false then
        controller_singleton = ClassController:New()
    end
    return controller_singleton
end

--- 重置全局控制器实例
function ClassController.ResetInstance()
    controller_singleton = nil
end

--- 判断控制器是否仍然活跃（任一视图存在即可）
--- @return boolean
function ClassController:IsActive()
    if not self then
        return false
    end
    if self._mainView and self._mainView:Valid() then
        return true
    end
    if self._subView and self._subView:Valid() then
        return true
    end
    return false
end

--- 统计总文件数和总行数
---@param data table LSP 数据
---@return integer, integer 文件数，总行数（展开后）
local function count_items(data)
    local file_count = 0
    local total_lines = 0

    for _, item in pairs(data) do
        file_count = file_count + 1
        total_lines = total_lines + 1 -- 文件标题行

        if not item.fold then
            total_lines = total_lines + #item.range -- 代码行
        end
    end

    return file_count, total_lines
end

local function capture_history_context(buffer_id, line)
    if not buffer_id or not api.nvim_buf_is_valid(buffer_id) then
        return nil
    end

    if not api.nvim_buf_is_loaded(buffer_id) then
        local ok = pcall(fn.bufload, buffer_id)
        if not ok or not api.nvim_buf_is_loaded(buffer_id) then
            return nil
        end
    end

    local ok, lines = pcall(api.nvim_buf_get_lines, buffer_id, line - 1, line, false)
    if not ok or not lines or not lines[1] then
        return nil
    end

    return vim.trim(lines[1])
end

---@return ClassController
function ClassController:New()
    -- 每次调用都创建新实例（修复单例状态污染问题）
    local obj = {}
    setmetatable(obj, self)

    obj._lsp = ClassLsp:New()
    obj._mainView = ClassMainView:New(false)
    obj._subView = ClassSubView:New(true)
    obj._search_state = search.new_state() -- 初始化搜索状态
    obj._line_map = {} -- 初始化行号映射表

    -- 初始化跳转历史（使用配置）
    local history_config = config.options.jump_history or {}
    local max_size = history_config.max_size or 50
    obj._jump_history_state = jump_history.new_state(max_size)
    obj._jump_history_state.enabled = history_config.enable ~= false

    -- 初始化虚拟滚动状态（使用配置）
    local vs_config = config.options.virtual_scroll or {}
    obj._virtual_scroll = {
        enabled = false,
        threshold = vs_config.threshold or 500,
        chunk_size = vs_config.chunk_size or 200,
        loaded_file_count = 0,
        total_file_count = 0,
        load_more_threshold = vs_config.load_more_threshold or 50,
        uri_list = {},
        uri_to_index = {}, -- URI 到索引的反向映射（性能优化）
        is_loading = false,
        -- 搜索过滤模式
        search_mode = false, -- 是否在搜索过滤模式
        matched_uri_list = {}, -- 匹配的 URI 列表（有序）
        loaded_match_count = 0, -- 已加载的匹配数
        total_match_count = 0, -- 总匹配数
    }

    api.nvim_create_augroup("LspUI_SubView", { clear = true })

    api.nvim_create_augroup("LspUI_AutoClose", { clear = true })

    return obj
end

--- 限制 SubView 高度不超过屏幕高度
---@private
---@param height integer 原始高度
---@return integer 限制后的高度
function ClassController:_limitSubViewHeight(height)
    local max_height = api.nvim_get_option_value("lines", {}) - 3
    if height > max_height then
        return max_height
    end
    return height
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
function ClassController:_generateSubViewContentVirtual(
    data,
    bufId,
    total_file_count
)
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

    -- 创建 URI 到 index 的反向映射（性能优化：O(1) 查找）
    local uri_to_index = {}
    for i, uri in ipairs(uri_list) do
        uri_to_index[uri] = i
    end
    self._virtual_scroll.uri_to_index = uri_to_index

    -- 初始只加载前 chunk_size 个文件
    local chunk_size = self._virtual_scroll.chunk_size
    local end_idx = math.min(chunk_size, total_file_count)

    -- 切片数据（保持顺序）
    local sliced_data = {}
    local ordered_uris = {}
    for i = 1, end_idx do
        local uri = uri_list[i]
        sliced_data[uri] = data[uri]
        table.insert(ordered_uris, uri)
    end

    -- 调用完整渲染函数渲染切片数据（传递有序 URI 列表）
    local width, height = self:_renderSubViewData(sliced_data, bufId, ordered_uris)

    -- 添加"加载更多"提示
    if end_idx < total_file_count then
        local remaining = total_file_count - end_idx
        api.nvim_set_option_value("modifiable", true, { buf = bufId })
        api.nvim_buf_set_lines(bufId, -1, -1, false, {
            "",
            string.format(
                "... (%d more files, scroll down to load)",
                remaining
            ),
        })
        api.nvim_set_option_value("modifiable", false, { buf = bufId })
        height = height + 2
    end

    self._virtual_scroll.loaded_file_count = end_idx

    return width, height
end

--- 生成内容数据（共用逻辑，被渲染和追加函数调用）
---@private
---@param data table LSP 数据
---@param start_line_offset integer 起始行偏移（用于计算行号）
---@param ordered_uris table|nil 可选的有序 URI 列表，如果提供则使用，否则自动排序
---@return string[], integer[], table[], table, integer 内容行、高亮行、extmarks、语法区域、最大宽度
function ClassController:_generateContentForData(data, start_line_offset, ordered_uris)
    local content = {}
    local hl_lines = {}
    local extmarks = {}
    local syntax_regions = {}
    local max_width = 0

    local function trim_line(str)
        if type(str) ~= "string" then
            return ""
        end
        return (str:gsub("^%s*(.-)%s*$", "%1"))
    end

    -- 只在初始渲染时清空映射表（start_line_offset == 0）
    -- 虚拟滚动追加时保留已有映射，累加新映射
    if start_line_offset == 0 then
        self._line_map = {}
    end

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

    local raw_cwd = vim.fn.getcwd()
    local cwd = normalize_path(raw_cwd)
    local cwd_len = #raw_cwd

    -- 如果没有提供有序列表，则对 URI 进行排序以确保一致的顺序
    local sorted_uris
    if ordered_uris then
        sorted_uris = ordered_uris
    else
        sorted_uris = {}
        for uri in pairs(data) do
            table.insert(sorted_uris, uri)
        end
        table.sort(sorted_uris)
    end

    -- 生成内容（按排序后的顺序遍历）
    for _, uri in ipairs(sorted_uris) do
        local item = data[uri]
        local file_full_name = vim.uri_to_fname(uri)
        local file_name = vim.fn.fnamemodify(file_full_name, ":t")
        local filetype = tools.detect_filetype(file_full_name)

        local rel_path = ""
        local norm_file_path =
            normalize_path(vim.fn.fnamemodify(file_full_name, ":p"))

        if norm_file_path:sub(1, #cwd) == cwd then
            local rel_to_cwd = file_full_name:sub(cwd_len + 1)
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

        local file_fmt =
            string.format(" %s %s", item.fold and "▶" or "▼", file_name)
        table.insert(content, file_fmt)
        table.insert(hl_lines, start_line_offset + #content)

        if rel_path ~= "" then
            table.insert(extmarks, {
                line = start_line_offset + #content - 1,
                text = rel_path,
                hl_group = "Comment",
            })
        end

        local file_fmt_len = api.nvim_strwidth(file_fmt)
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

        -- 为文件标题行建立映射（range 为 nil 表示这是文件标题行）
        local title_line_num = start_line_offset + #content
        self._line_map[title_line_num] = {
            uri = uri,
            range = nil,  -- 文件标题行没有具体的 range
        }

        -- 为每个代码行建立映射
        local range_index = 1
        for _, row in ipairs(uri_rows) do
            local original_line = lines[row] or ""
            local line_code = trim_line(original_line)
            local code_fmt = string.format("   %s", line_code)

            if not item.fold then
                table.insert(content, code_fmt)

                -- 为当前行建立映射（性能优化：O(1) 查找）
                local code_line_num = start_line_offset + #content
                if item.range[range_index] then
                    self._line_map[code_line_num] = {
                        uri = uri,
                        range = item.range[range_index],
                    }
                end
                range_index = range_index + 1

                if filetype and filetype ~= "" then
                    -- 计算源文件中被trim掉的前导空格数量
                    local leading_spaces = 0
                    if #original_line > 0 then
                        local first_non_space = original_line:find("%S")
                        if first_non_space then
                            leading_spaces = first_non_space - 1
                        else
                            leading_spaces = #original_line  -- 全是空格的行
                        end
                    end

                    local line_content = content[#content]
                    local region_data = {
                        line = start_line_offset + #content - 1,
                        col_start = 3,
                        col_end = #line_content,
                        source_buf = item.buffer_id,
                        source_line = row,
                        source_col_offset = leading_spaces,  -- 新增：源文件中的列偏移
                    }
                    table.insert(syntax_regions[filetype], region_data)
                end
            end
        end
    end

    return content, hl_lines, extmarks, syntax_regions, max_width
end

--- 渲染数据到 SubView（核心渲染逻辑，被完整渲染和虚拟渲染共用）
---@private
---@param data table LSP 数据
---@param bufId integer Buffer ID
---@param ordered_uris table|nil 可选的有序 URI 列表
function ClassController:_renderSubViewData(data, bufId, ordered_uris)
    -- 允许修改缓冲区
    api.nvim_set_option_value("modifiable", true, { buf = bufId })

    -- 清理旧的语法高亮，避免残留
    if self._subView then
        self._subView:ClearSyntaxHighlight()
    end

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

    -- 生成内容（使用提取的共用函数，传递有序 URI 列表）
    local content, hl_lines, extmarks, syntax_regions, max_width =
        self:_generateContentForData(data, 0, ordered_uris)

    -- 设置内容
    api.nvim_buf_set_lines(bufId, 0, -1, true, content)

    -- 应用语法高亮
    self._subView:ApplySyntaxHighlight(syntax_regions)

    -- 设置高亮
    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
    api.nvim_buf_clear_namespace(bufId, subViewNamespace, 0, -1)

    for _, lnum in ipairs(hl_lines) do
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
    local max_columns =
        math.floor(api.nvim_get_option_value("columns", {}) * 0.3)

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

    -- 防止重复注册 autocmd：每次重新绑定前先清理当前 buffer 下的组
    pcall(api.nvim_clear_autocmds, {
        group = "LspUI_SubView",
        buffer = buf,
    })

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

    if
        self._virtual_scroll.loaded_file_count
        >= self._virtual_scroll.total_file_count
    then
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

    -- 获取要加载的 URI（保持顺序）
    local new_data = {}
    local ordered_uris = {}
    for i = start_idx, end_idx do
        local uri = uri_list[i]
        if data[uri] then
            new_data[uri] = data[uri]
            table.insert(ordered_uris, uri)
        end
    end

    -- 移除旧的提示行
    api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    local line_count = api.nvim_buf_line_count(bufnr)
    if line_count >= 2 then
        api.nvim_buf_set_lines(bufnr, line_count - 2, line_count, false, {})
    end

    -- 生成新内容并追加（复用渲染逻辑，传递有序 URI 列表）
    local append_start_line = api.nvim_buf_line_count(bufnr)
    local width, height =
        self:_appendSubViewData(new_data, bufnr, append_start_line, ordered_uris)

    -- 添加新的提示（如果还有更多）
    if end_idx < total_count then
        local remaining = total_count - end_idx
        local tip_text
        if vs.search_mode then
            tip_text = string.format(
                "... (%d more matched files, scroll down to load)",
                remaining
            )
        else
            tip_text = string.format(
                "... (%d more files, scroll down to load)",
                remaining
            )
        end

        api.nvim_buf_set_lines(bufnr, -1, -1, false, {
            "",
            tip_text,
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

    -- 更新窗口大小，限制高度不超过屏幕高度
    local total_height = api.nvim_buf_line_count(bufnr)
    total_height = self:_limitSubViewHeight(total_height)
    self._subView:Size(width, total_height)
end

--- 一次性加载到指定索引（优化的批量加载，避免 UI 闪烁）
---@private
---@param target_index integer 目标索引
function ClassController:_loadItemsUpTo(target_index)
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
        uri_list = vs.matched_uri_list
        start_idx = vs.loaded_match_count + 1
        total_count = vs.total_match_count
        end_idx = math.min(target_index, total_count)
    else
        uri_list = vs.uri_list
        start_idx = vs.loaded_file_count + 1
        total_count = vs.total_file_count
        end_idx = math.min(target_index, total_count)
    end

    -- 如果已经加载了目标索引，直接返回
    if start_idx > end_idx then
        self._virtual_scroll.is_loading = false
        return
    end

    -- 一次性获取所有要加载的 URI（保持顺序）
    local new_data = {}
    local ordered_uris = {}
    for i = start_idx, end_idx do
        local uri = uri_list[i]
        if data[uri] then
            new_data[uri] = data[uri]
            table.insert(ordered_uris, uri)
        end
    end

    -- 移除旧的提示行
    api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    local line_count = api.nvim_buf_line_count(bufnr)
    if line_count >= 2 then
        api.nvim_buf_set_lines(bufnr, line_count - 2, line_count, false, {})
    end

    -- 生成新内容并追加（一次性追加所有内容，传递有序 URI 列表）
    local append_start_line = api.nvim_buf_line_count(bufnr)
    local width, height =
        self:_appendSubViewData(new_data, bufnr, append_start_line, ordered_uris)

    -- 添加新的提示（如果还有更多）
    if end_idx < total_count then
        local remaining = total_count - end_idx
        local tip_text
        if vs.search_mode then
            tip_text = string.format(
                "... (%d more matched files, scroll down to load)",
                remaining
            )
        else
            tip_text = string.format(
                "... (%d more files, scroll down to load)",
                remaining
            )
        end

        api.nvim_buf_set_lines(bufnr, -1, -1, false, {
            "",
            tip_text,
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

    -- 更新窗口大小，限制高度不超过屏幕高度
    local total_height = api.nvim_buf_line_count(bufnr)
    total_height = self:_limitSubViewHeight(total_height)
    self._subView:Size(width, total_height)
end

--- 追加数据到 SubView（用于虚拟滚动动态加载）
---@private
---@param data table LSP 数据
---@param bufId integer Buffer ID
---@param start_line integer 起始行号
---@param ordered_uris table|nil 可选的有序 URI 列表
function ClassController:_appendSubViewData(data, bufId, start_line, ordered_uris)
    local extmark_ns = api.nvim_create_namespace("LspUIPathExtmarks")

    -- 生成内容（使用提取的共用函数，传递有序 URI 列表）
    local content, hl_lines, extmarks, syntax_regions, max_width =
        self:_generateContentForData(data, start_line, ordered_uris)

    -- 追加内容
    api.nvim_buf_set_lines(bufId, start_line, start_line, false, content)

    -- 应用语法高亮
    self._subView:ApplySyntaxHighlight(syntax_regions)

    -- 设置高亮
    local subViewNamespace = api.nvim_create_namespace("LspUISubView")
    for _, lnum in ipairs(hl_lines) do
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
        local line_content = api.nvim_buf_get_lines(
            bufId,
            mark.line,
            mark.line + 1,
            false
        )[1] or ""
        api.nvim_buf_set_extmark(bufId, extmark_ns, mark.line, #line_content, {
            virt_text = { { mark.text, mark.hl_group } },
            virt_text_pos = "eol",
        })
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
    -- 使用行号映射表进行 O(1) 查找（性能优化）
    local mapping = self._line_map[lnum]
    if mapping then
        return mapping.uri, mapping.range
    end

    -- 如果映射表中没有找到，返回 nil（不应该发生，除非映射表未正确构建）
    return nil, nil
end

---@private
---@param uri string
---@param range LspUIRange? 当前选中的范围，用于定位折叠后光标位置
---@return integer lnum 光标应放置的行号
function ClassController:_getCursorPosForUri(uri, range)
    -- 使用行号映射表进行反向查找（性能优化：O(N) -> O(M)，M 是显示的行数）
    local fileHeaderLine = nil

    -- 遍历映射表查找匹配项
    for lnum, mapping in pairs(self._line_map) do
        if mapping.uri == uri then
            -- 如果是文件标题行（range 为 nil）
            if mapping.range == nil then
                fileHeaderLine = lnum
            end

            -- 如果指定了范围，查找匹配的范围行
            if range and mapping.range then
                if
                    mapping.range.start.line == range.start.line
                    and mapping.range.start.character == range.start.character
                then
                    return lnum
                end
            end
        end
    end

    -- 如果没有指定范围或找不到匹配的范围，返回文件标题行
    if fileHeaderLine then
        return fileHeaderLine
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

    local lsp_data = self._lsp:GetData()
    
    -- 对 URI 进行排序以确保顺序一致（与渲染时相同）
    local sorted_uris = {}
    for uri in pairs(lsp_data) do
        table.insert(sorted_uris, uri)
    end
    table.sort(sorted_uris)

    for _, uri in ipairs(sorted_uris) do
        local data = lsp_data[uri]
        lnum = lnum + 1
        if not data.fold then
            for _, val in ipairs(data.range) do
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
            if
                self._jump_history_state and self._jump_history_state.enabled
            then
                local history_item = jump_history.create_item({
                    uri = single_uri,
                    line = target_line,
                    col = target_col,
                    buffer_id = target_buf,
                    lsp_type = method_name,
                    context = capture_history_context(target_buf, target_line),
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
    height = self:_limitSubViewHeight(height)

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

        -- 保存原始 winbar（用于后续搜索状态更新）
        local winid = self._subView:GetWinID()
        if winid then
            self._original_winbar = vim.wo[winid].winbar or ""
        end
    end

    -- 获取第一个URI对应的缓冲区作为MainView的初始缓冲区
    -- 使用排序后的第一个 URI 以确保一致性
    local firstBuffer = nil
    local lsp_data = self._lsp:GetData()
    if lsp_data and not vim.tbl_isempty(lsp_data) then
        local sorted_uris = {}
        for uri in pairs(lsp_data) do
            table.insert(sorted_uris, uri)
        end
        table.sort(sorted_uris)
        
        if #sorted_uris > 0 then
            firstBuffer = lsp_data[sorted_uris[1]].buffer_id
        end
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
            context = capture_history_context(target_buf, target_line),
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
        -- 使用反向映射进行 O(1) 查找（性能优化）
        local uri_index = self._virtual_scroll.uri_to_index[uri]

        -- 如果该文件未加载，一次性加载到该位置（优化：避免循环调用和 UI 闪烁）
        if uri_index and uri_index > self._virtual_scroll.loaded_file_count then
            self:_loadItemsUpTo(uri_index)
        end
    end

    -- 切换折叠状态
    data[uri].fold = not data[uri].fold

    -- 重新生成SubView内容
    local width, height = self:_generateSubViewContent()
    height = self:_limitSubViewHeight(height)
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

    -- 对 URI 进行排序以确保顺序一致（与渲染时相同）
    local sorted_uris = {}
    for uri in pairs(data) do
        table.insert(sorted_uris, uri)
    end
    table.sort(sorted_uris)

    -- 查找下一个项目
    for _, uri in ipairs(sorted_uris) do
        local item = data[uri]
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

    -- 对 URI 进行排序以确保顺序一致（与渲染时相同）
    local sorted_uris = {}
    for uri in pairs(data) do
        table.insert(sorted_uris, uri)
    end
    table.sort(sorted_uris)

    -- 查找上一个项目
    for _, uri in ipairs(sorted_uris) do
        local item = data[uri]
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
        -- 使用排序后的第一个 URI 以确保一致性
        local firstBuffer = nil
        local lsp_data = self._lsp:GetData()
        if lsp_data and not vim.tbl_isempty(lsp_data) then
            local sorted_uris = {}
            for uri in pairs(lsp_data) do
                table.insert(sorted_uris, uri)
            end
            table.sort(sorted_uris)
            
            if #sorted_uris > 0 then
                firstBuffer = lsp_data[sorted_uris[1]].buffer_id
            end
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
        height = self:_limitSubViewHeight(height)

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
        height = self:_limitSubViewHeight(height)
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
    if
        not self._search_state.enabled
        or self._search_state.match_count == 0
    then
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
    if
        not self._search_state.enabled
        or self._search_state.match_count == 0
    then
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

    -- 设置 filetype 以触发语法高亮（通过 ftplugin）
    vim.bo[buf].filetype = "LspUIJumpHistory"

    -- 计算窗口大小
    local ui = api.nvim_list_uis()[1]
    -- 宽度：在小屏幕上使用 80%，但最大不超过 120 列（适合跳转历史的内容宽度）
    local width = math.min(math.floor(ui.width * 0.8), 120)
    local max_height = config.options.jump_history.win_max_height or 20
    local height = math.min(#lines, max_height)

    -- 居中位置
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

    -- 添加高亮
    local ns = api.nvim_create_namespace("LspUIJumpHistory")
    
    -- 高亮标题行（第1行）
    vim.highlight.range(
        buf,
        ns,
        "Title",
        { 0, 0 },
        { 0, -1 },
        { priority = vim.highlight.priorities.user }
    )
    
    -- 高亮分隔线（第2行和倒数第2行）
    vim.highlight.range(
        buf,
        ns,
        "Comment",
        { 1, 0 },
        { 1, -1 },
        { priority = vim.highlight.priorities.user }
    )
    
    if #lines > 2 then
        vim.highlight.range(
            buf,
            ns,
            "Comment",
            { #lines - 2, 0 },
            { #lines - 2, -1 },
            { priority = vim.highlight.priorities.user }
        )
    end
    
    -- 高亮历史项
    for i = 3, #lines - 2 do
        local line = lines[i]
        if line and line ~= "" then
            -- 时间戳高亮 [HH:MM:SS]
            local time_start, time_end = line:find("%[%d%d:%d%d:%d%d%]")
            if time_start then
                vim.highlight.range(
                    buf,
                    ns,
                    "Number",
                    { i - 1, time_start - 1 },
                    { i - 1, time_end },
                    { priority = vim.highlight.priorities.user }
                )
            end
            
            -- LSP 类型高亮（在第一个 │ 之前）
            local first_sep = line:find("│")
            if first_sep and time_end then
                vim.highlight.range(
                    buf,
                    ns,
                    "Function",
                    { i - 1, time_end + 1 },
                    { i - 1, first_sep - 1 },
                    { priority = vim.highlight.priorities.user }
                )
            end
            
            -- 文件路径高亮（两个 │ 之间）
            local second_sep = line:find("│", first_sep + 1)
            if first_sep and second_sep then
                vim.highlight.range(
                    buf,
                    ns,
                    "Directory",
                    { i - 1, first_sep + 1 },
                    { i - 1, second_sep - 1 },
                    { priority = vim.highlight.priorities.user }
                )
            end
            
            -- 代码上下文保持默认颜色（可以考虑添加语法高亮，但需要知道文件类型）
        end
    end
    
    -- 高亮底部快捷键提示（最后一行）
    if #lines > 0 then
        local help_line = lines[#lines]
        local highlight_keys = {
            { pattern = "<CR>", hl = "Special" },
            { pattern = "d", hl = "WarningMsg" },
            { pattern = "c", hl = "ErrorMsg" },
            { pattern = "q", hl = "Special" },
        }
        
        for _, key_info in ipairs(highlight_keys) do
            local start_pos = 1
            while true do
                local key_start, key_end = help_line:find(key_info.pattern, start_pos, true)
                if not key_start then break end
                
                vim.highlight.range(
                    buf,
                    ns,
                    key_info.hl,
                    { #lines - 1, key_start - 1 },
                    { #lines - 1, key_end },
                    { priority = vim.highlight.priorities.user + 1 }
                )
                start_pos = key_end + 1
            end
        end
    end

    -- 设置光标到最新记录（第3行，跳过标题）
    if #state.items > 0 then
        api.nvim_win_set_cursor(win, { 3, 0 })
    end

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
        local item_index = jump_history.get_item_index_from_display_line(
            line_num,
            #state.items
        )

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
                vim.cmd(
                    string.format("edit %s", vim.fn.fnameescape(item.file_path))
                )
            end

            -- 设置光标位置
            api.nvim_win_set_cursor(0, { item.line, item.col })
            vim.cmd("norm! zz")

            notify.Info(
                string.format(
                    "Jumped to history: %s:%d",
                    item.file_name,
                    item.line
                )
            )
        end
    end

    local function delete_history_item()
        local cursor = api.nvim_win_get_cursor(win)
        local line_num = cursor[1]

        local item_index = jump_history.get_item_index_from_display_line(
            line_num,
            #state.items
        )

        if item_index and jump_history.remove_item(state, item_index) then
            -- 刷新显示
            local new_lines = jump_history.get_display_lines(state)
            vim.bo[buf].modifiable = true
            api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
            vim.bo[buf].modifiable = false

            -- 调整光标位置
            local new_line = math.min(line_num, #new_lines - 2)
            if new_line < 3 then
                new_line = 3
            end
            api.nvim_win_set_cursor(win, { new_line, 0 })

            notify.Info("History item deleted")
        end
    end

    local function clear_all_history()
        -- 确认对话框
        local confirm =
            vim.fn.confirm("Clear all jump history?", "&Yes\n&No", 2)
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

            for _, row in ipairs(uri_rows) do
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

    -- 只渲染匹配的文件（保持顺序）
    local filtered_data = {}
    local ordered_uris = {}
    for i = 1, end_idx do
        local uri = matched_uris[i]
        if data[uri] then
            filtered_data[uri] = data[uri]
            table.insert(ordered_uris, uri)
        end
    end

    -- 渲染（传递有序 URI 列表）
    local width, height = self:_renderSubViewData(filtered_data, bufId, ordered_uris)

    -- 添加提示
    if end_idx < #matched_uris then
        api.nvim_set_option_value("modifiable", true, { buf = bufId })
        api.nvim_buf_set_lines(bufId, -1, -1, false, {
            "",
            string.format(
                "... (%d more matched files, scroll down to load)",
                #matched_uris - end_idx
            ),
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
            total = vs.total_match_count,
        }
    end

    local status =
        search.get_status_line(self._search_state, virtual_scroll_info)

    if not self._subView:Valid() then
        return
    end

    local winid = self._subView:GetWinID()

    -- 使用保存的原始 winbar 构建新的 winbar，而不是使用 gsub 移除
    local base_winbar = self._original_winbar or ""
    local current_winbar = base_winbar

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
