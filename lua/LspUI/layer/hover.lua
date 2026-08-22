-- lua/LspUI/layer/hover.lua
local api, lsp, fn = vim.api, vim.lsp, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local ClassLsp = require("LspUI.layer.lsp")
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

--- @alias hover_tuple { client: vim.lsp.Client, buffer_id: integer, width: integer, height: integer }

--- @class ClassHover
--- @field private _view ClassView|nil
--- @field private _hover_tuples hover_tuple[]
--- @field private _current_index integer
--- @field private _enter_lock boolean
--- @field private _autocmd_group integer|nil
--- @field private _key_bindings table|nil
local ClassHover = {
    _view = nil,
    _hover_tuples = {},
    _current_index = 1,
    _enter_lock = false,
    _autocmd_group = nil,
    _key_bindings = nil,
}

ClassHover.__index = ClassHover

--- @return ClassHover
function ClassHover:New()
    local obj = {}
    setmetatable(obj, self)
    return obj
end

--- Apply Treesitter markdown highlighting (same as neovim native hover)
--- @param bufnr integer
--- @param winnr integer
local function apply_treesitter_highlight(bufnr, winnr)
    vim.wo[winnr].conceallevel = 2
    -- 与 neovim 原生 hover 保持一致：光标所在行不做 conceal。
    -- 若设为 "n"，`[text](url)` 的 URL 段在光标行也会被隐藏，
    -- 用户既看不到链接目标，光标也无法落到被 conceal 的区间上，导致 `gx` 不可用。
    vim.wo[winnr].concealcursor = ""
    vim.wo[winnr].foldenable = false
    vim.wo[winnr].smoothscroll = true
    -- Disable legacy syntax to avoid loading syntax/markdown.vim chain
    -- which may fail if dtd.vim is missing
    vim.bo[bufnr].syntax = ""
    vim.bo[bufnr].filetype = "markdown"
    -- Use treesitter only for highlighting
    pcall(vim.treesitter.start, bufnr)
end

--- 判断是否为 markdown 主题分隔线（GFM thematic break）
--- @param line string
--- @return boolean
local function is_separator_line(line)
    -- 最多 3 个前导空格，其后为 >=3 个同种 - * _，中间只允许空白
    local body = line:match("^ ? ? ?([-*_][-*_%s]*)$")
    if not body then
        return false
    end
    local delim = body:sub(1, 1)
    local count = 0
    for char in body:gmatch("%S") do
        if char ~= delim then
            return false
        end
        count = count + 1
    end
    return count >= 3
end

--- 归一化 LSP 返回的 markdown，行为对齐 vim.lsp.util._normalize_markdown：
--- 1. 去掉 \r 与首尾空行  2. 连续空行折叠为一行  3. 分隔线展开为等宽横线（并吃掉相邻空行）
--- @param lines string[]
--- @param width integer
--- @return string[]
local function normalize_markdown(lines, width)
    local raw = table.concat(lines, "\n"):gsub("\r", "")
    local source = vim.split(raw, "\n", { trimempty = true })
    local divider = string.rep("─", width)

    local result = {}
    local index = 1
    while index <= #source do
        local line = source[index]
        if line:match("^%s*$") then
            -- 折叠连续空行
            if #result > 0 and result[#result] ~= "" then
                result[#result + 1] = ""
            end
        elseif is_separator_line(line) then
            if result[#result] == "" then
                result[#result] = nil
            end
            result[#result + 1] = divider
            -- 吃掉分隔线后紧跟的空行
            while source[index + 1] and source[index + 1]:match("^%s*$") do
                index = index + 1
            end
        else
            result[#result + 1] = line
        end
        index = index + 1
    end

    while #result > 0 and result[#result] == "" do
        result[#result] = nil
    end
    return result
end

--- Create a hover buffer from markdown lines
--- @param markdown_lines string[]
--- @return integer buffer_id
--- @return integer width
--- @return integer height
local function create_hover_buffer(markdown_lines)
    -- 先按原始内容估算宽度，再用该宽度归一化（分隔线需要知道最终宽度）
    local width = 0
    for _, str in ipairs(markdown_lines) do
        width = math.max(width, fn.strdisplaywidth(str))
    end
    width = math.min(width, math.floor(tools.get_max_width() * 0.5))
    width = math.max(width, 1)

    markdown_lines = normalize_markdown(markdown_lines, width)

    local new_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(new_buffer, 0, -1, true, markdown_lines)
    vim.bo[new_buffer].bufhidden = "wipe"
    vim.bo[new_buffer].modifiable = false

    local height =
        math.min(#markdown_lines, math.floor(tools.get_max_height() * 0.6))

    return new_buffer, width, math.max(height, 1)
end

--- markdown 中承载链接的节点类型
local link_node_types = {
    inline_link = true,
    image = true,
    full_reference_link = true,
    collapsed_reference_link = true,
    shortcut_link = true,
    uri_autolink = true,
    email_autolink = true,
}

--- 收集 buffer 内的链接引用定义：`[label]: url`
--- @param bufnr integer
--- @return table<string, string>
local function collect_link_refs(bufnr)
    local refs = {}
    for _, line in ipairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local label, dest = line:match("^%s*%[([^%]]+)%]:%s*(%S+)")
        if label then
            refs[label:lower()] = dest
        end
    end
    return refs
end

--- 在指定行里找出包含 col 的裸 URL
--- @param line string
--- @param col integer 0-based
--- @return string|nil
local function find_bare_url(line, col)
    local init = 1
    while true do
        local s, e = line:find("%a[%w+.-]*://[^%s)%]>,\"']+", init)
        if not s then
            return nil
        end
        if col >= s - 1 and col <= e - 1 then
            return (line:sub(s, e):gsub("[.,:;!?]+$", ""))
        end
        init = e + 1
    end
end

--- 解析光标处的链接目标。
--- 兼容行内链接、图片、autolink，以及 treesitter 未提供 url 元数据的引用式链接。
--- @param bufnr integer
--- @param winnr integer
--- @return string|nil
local function resolve_url_at_cursor(bufnr, winnr)
    local cursor = api.nvim_win_get_cursor(winnr)
    local row, col = cursor[1] - 1, cursor[2]

    -- markdown 的行内内容位于 markdown_inline 注入树中，
    -- vim.treesitter.get_node 不会下潜到注入树，需要手动取注入树的节点
    local node = (function()
        local has_parser, parser =
            pcall(vim.treesitter.get_parser, bufnr, nil, { error = false })
        if not has_parser or not parser then
            return nil
        end
        local range = { row, col, row, col }
        local ok = pcall(parser.parse, parser, { row, row + 1 })
        if not ok then
            return nil
        end
        local ok_tree, result = pcall(function()
            local language_tree = parser:language_for_range(range)
            local tree = language_tree:tree_for_range(range)
            return tree
                and tree:root():named_descendant_for_range(row, col, row, col)
        end)
        return ok_tree and result or nil
    end)()

    while node do
        local node_type = node:type()
        if link_node_types[node_type] then
            if node_type == "uri_autolink" or node_type == "email_autolink" then
                local text = vim.treesitter.get_node_text(node, bufnr)
                text = text:sub(2, -2) -- 去掉两侧的 < >
                return node_type == "email_autolink" and ("mailto:" .. text)
                    or text
            end

            for child in node:iter_children() do
                if child:type() == "link_destination" then
                    return vim.treesitter.get_node_text(child, bufnr)
                end
            end

            -- 引用式链接：用 label 去查 `[label]: url`
            local refs = collect_link_refs(bufnr)
            for child in node:iter_children() do
                local child_type = child:type()
                if child_type == "link_label" or child_type == "link_text" then
                    local label = vim.treesitter
                        .get_node_text(child, bufnr)
                        :gsub("^%[", "")
                        :gsub("%]$", "")
                    local url = refs[label:lower()]
                    if url then
                        return url
                    end
                end
            end
        end
        node = node:parent()
    end

    local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    return line and find_bare_url(line, col) or nil
end

-- 暴露给测试与复用（不依赖实例状态）
ClassHover.NormalizeMarkdown = normalize_markdown
ClassHover.ResolveUrlAtCursor = resolve_url_at_cursor

--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil
function ClassHover:GetClients(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = hover_feature })
    return vim.tbl_isempty(clients) and nil or clients
end

--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param callback fun(hover_tuples: hover_tuple[])
function ClassHover:GetHovers(clients, buffer_id, callback)
    local lsp_instance = ClassLsp:New()
    local ready, reason = lsp_instance:CheckClientsReady(clients)
    if not ready then
        notify.Warn(reason or "LSP client not ready")
        return
    end

    self._hover_tuples = {}
    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)
    local pending = #clients

    for _, client in ipairs(clients) do
        client:request(
            hover_feature,
            params,
            function(err, result, _, lsp_config)
                lsp_config = lsp_config or {}

                if err and lsp_config.silent ~= true then
                    notify.Warn(
                        string.format(
                            "server %s, err code is %d, err msg is %s",
                            client.name,
                            err.code,
                            err.message
                        )
                    )
                elseif result and result.contents then
                    local markdown_lines =
                        lsp.util.convert_input_to_markdown_lines(
                            result.contents
                        )
                    local buf, width, height =
                        create_hover_buffer(markdown_lines)
                    table.insert(self._hover_tuples, {
                        client = client,
                        buffer_id = buf,
                        width = width,
                        height = height,
                    })
                end

                pending = pending - 1
                if pending == 0 then
                    callback(self._hover_tuples)
                end
            end,
            buffer_id
        )
    end
end

--- @param hover_tuple hover_tuple
--- @param total integer
--- @param options table|nil
--- @return ClassView
function ClassHover:Render(hover_tuple, total, options)
    options = options or {}
    self._current_index = 1

    local title = total > 1 and string.format("hover[1/%d]", total) or "hover"

    local view = ClassView:New(false)
        :SwitchBuffer(hover_tuple.buffer_id)
        :Title(title, "right")
        :Size(hover_tuple.width, hover_tuple.height)
        :Relative("cursor")
        :Border(config.options.hover.border)
        :Style("minimal")
        :Focusable(true)
        :Enter(false)
        :Anchor("NW")
        :Pos(1, 1)
        :Render()
        :Winhl("Normal:Normal")
        :Option("wrap", true)
        :Option("linebreak", true)
        :Option("breakindent", true)
        :Winbl(options.transparency or 0)

    local winnr = view:GetWinID()
    if winnr then
        apply_treesitter_highlight(hover_tuple.buffer_id, winnr)
        self:FitHeight(hover_tuple)
    end

    self._view = view
    return view
end

--- 按 treesitter conceal / wrap 之后的真实文本高度调整窗口高度，
--- 避免代码块反引号被 conceal 后留下空行，或长行折行后内容被截断。
--- @param hover_tuple hover_tuple
function ClassHover:FitHeight(hover_tuple)
    local winnr = self._view and self._view:GetWinID()
    if not winnr then
        return
    end
    local max_height = math.max(1, math.floor(tools.get_max_height() * 0.6))
    local ok, result =
        pcall(api.nvim_win_text_height, winnr, { max_height = max_height })
    if ok and result.all > 0 then
        hover_tuple.height = math.min(result.all, max_height)
        self._view:Size(hover_tuple.width, hover_tuple.height)
    end
end

--- @param forward boolean
function ClassHover:NextRender(forward)
    if not self._view or #self._hover_tuples <= 1 then
        return
    end

    local total = #self._hover_tuples
    if forward then
        self._current_index = self._current_index % total + 1
    else
        self._current_index = (self._current_index - 2) % total + 1
    end

    local hover_tuple = self._hover_tuples[self._current_index]
    self._view:SwitchBuffer(hover_tuple.buffer_id)

    local winnr = self._view:GetWinID()
    if winnr then
        apply_treesitter_highlight(hover_tuple.buffer_id, winnr)
        self:FitHeight(hover_tuple)
    end

    local title = string.format("hover[%d/%d]", self._current_index, total)
    self._view:Updates(function()
        self._view:Size(hover_tuple.width, hover_tuple.height)
        self._view:Title(title, "right")
    end)

    -- keymap 是 buffer 局部的，切换 buffer 后需要重新绑定
    if self._key_bindings then
        self:SetKeyBindings(self._key_bindings)
    end
end

--- @param key_bindings { next: string, prev: string, quit: string, open_url: string? }
function ClassHover:SetKeyBindings(key_bindings)
    if not self._view then
        return
    end

    self._key_bindings = key_bindings

    self._view:KeyMap("n", key_bindings.next, function()
        self:NextRender(true)
    end, "next hover")

    self._view:KeyMap("n", key_bindings.prev, function()
        self:NextRender(false)
    end, "prev hover")

    self._view:KeyMap("n", key_bindings.quit, function()
        self:Close()
    end, "close hover")

    if key_bindings.open_url and key_bindings.open_url ~= "" then
        self._view:KeyMap("n", key_bindings.open_url, function()
            self:OpenUrl()
        end, "open url under cursor")
    end
end

--- 打开光标下的链接。
--- 不走默认 `gx`：默认实现依赖 treesitter 的 url 元数据，对引用式链接会拿到
--- 链接文字而不是 URL，且找不到目标时会抛 E446。
function ClassHover:OpenUrl()
    if not self:IsValid() then
        return
    end

    local buffer_id = self._view:GetBufID()
    local winnr = self._view:GetWinID()
    if not buffer_id or not winnr then
        return
    end

    local url = resolve_url_at_cursor(buffer_id, winnr)
    if not url then
        notify.Info("no url under cursor!")
        return
    end

    local ok, err = vim.ui.open(url)
    if not ok then
        notify.Warn(err or string.format("failed to open %s", url))
    end
end

--- @param buffer_id integer
function ClassHover:SetAutoCommands(buffer_id)
    if not self._view then
        return
    end

    if self._autocmd_group then
        pcall(api.nvim_del_augroup_by_id, self._autocmd_group)
        self._autocmd_group = nil
    end

    self._autocmd_group = api.nvim_create_augroup(
        "LspUI_hover_" .. tostring(buffer_id),
        { clear = true }
    )

    api.nvim_create_autocmd(
        { "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" },
        {
            group = self._autocmd_group,
            buffer = buffer_id,
            callback = function()
                if not self._enter_lock then
                    self:Close()
                    return true
                end
            end,
            desc = tools.command_desc("auto close hover when cursor moves"),
        }
    )
end

--- 在锁定状态下执行 callback，期间 SetAutoCommands 注册的 CursorMoved 不会自动关闭 hover
--- @param callback fun()
function ClassHover:EnterWithLock(callback)
    self._enter_lock = true
    callback()
    self._enter_lock = false
end

--- @return boolean
function ClassHover:IsValid()
    return self._view ~= nil and self._view:Valid()
end

--- 把焦点切到 hover 浮窗
function ClassHover:Focus()
    if self:IsValid() then
        self._view:Focus()
    end
end

--- 关闭 hover 浮窗 + 清理 autocmd + 回收所有 hover_tuples 中未显示过的 buffer
function ClassHover:Close()
    if self._autocmd_group then
        pcall(api.nvim_del_augroup_by_id, self._autocmd_group)
        self._autocmd_group = nil
    end

    local active_buf
    if self._view then
        active_buf = self._view:GetBufID()
        if self._view:Valid() then
            self._view:Destroy()
        end
        self._view = nil
    end

    -- 回收多客户端场景下未显示过的 hover buffer（bufhidden=wipe 只对显示过的生效）
    for _, tuple in ipairs(self._hover_tuples) do
        if
            tuple.buffer_id ~= active_buf
            and api.nvim_buf_is_valid(tuple.buffer_id)
        then
            pcall(api.nvim_buf_delete, tuple.buffer_id, { force = true })
        end
    end
    self._hover_tuples = {}
    self._current_index = 1
    self._key_bindings = nil
end

return ClassHover
