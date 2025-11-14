--- 增强的跳转历史模块
--- 与原生 jumplist 配合使用，提供更丰富的历史信息和管理功能

local api = vim.api

local M = {}

-- 常量定义
local DEFAULT_CONTEXT_MAX_LEN = 60 -- 上下文字符串的最大长度

--- @class JumpHistoryItem
--- @field uri string 文件 URI
--- @field line integer 行号（1-based）
--- @field col integer 列号（0-based）
--- @field buffer_id integer Buffer ID
--- @field lsp_type string LSP 跳转类型（definition/reference/implementation 等）
--- @field file_name string 文件名（不含路径）
--- @field file_path string 完整文件路径
--- @field context string 代码上下文（跳转位置所在行的代码）
--- @field timestamp integer 时间戳

--- @class JumpHistoryState
--- @field items JumpHistoryItem[] 历史项数组
--- @field max_size integer 最大历史数量
--- @field enabled boolean 是否启用

--- 创建新的历史状态
--- @param max_size integer? 最大历史数量，默认 50
--- @return JumpHistoryState
function M.new_state(max_size)
    return {
        items = {},
        max_size = max_size or 50,
        enabled = true,
    }
end

--- 添加跳转记录到历史
--- @param state JumpHistoryState
--- @param item JumpHistoryItem
function M.add_item(state, item)
    if not state.enabled then
        return
    end

    -- 添加时间戳
    item.timestamp = os.time()

    -- 去重：如果最后一条记录与当前完全相同，则不添加
    if #state.items > 0 then
        local last = state.items[#state.items]
        if
            last.uri == item.uri
            and last.line == item.line
            and last.col == item.col
        then
            -- 更新时间戳即可
            last.timestamp = item.timestamp
            return
        end
    end

    -- 添加到历史
    table.insert(state.items, item)

    -- 如果超过最大容量，移除最老的
    if #state.items > state.max_size then
        table.remove(state.items, 1)
    end
end

--- 获取指定行的代码上下文
--- @param uri string
--- @param line integer 行号（1-based）
--- @return string
function M.get_line_context(uri, line)
    local bufnr = vim.uri_to_bufnr(uri)

    -- 如果 buffer 已加载
    if api.nvim_buf_is_loaded(bufnr) then
        local ok, lines =
            pcall(api.nvim_buf_get_lines, bufnr, line - 1, line, false)
        if ok and lines and lines[1] then
            return vim.fn.trim(lines[1])
        end
    end

    -- 如果 buffer 未加载，尝试读取文件
    local file_path = vim.uri_to_fname(uri)
    local ok, lines = pcall(vim.fn.readfile, file_path, "", line)
    if ok and lines and #lines > 0 then
        -- readfile 返回前 n 行，我们需要的是最后一行（即第 line 行）
        return vim.fn.trim(lines[#lines])
    end

    return ""
end

--- 创建跳转历史项
--- @param opts table
--- @return JumpHistoryItem
function M.create_item(opts)
    local uri = opts.uri
    local file_path = vim.uri_to_fname(uri)
    local file_name = vim.fn.fnamemodify(file_path, ":t")

    -- 延迟加载 context：只在显示历史窗口时才获取，避免跳转时的文件读取延迟
    -- 如果调用者显式提供了 context，则使用它；否则保持为 nil
    local context = opts.context
    if context and context ~= "" then
        -- 截断过长的上下文
        if #context > DEFAULT_CONTEXT_MAX_LEN then
            context = context:sub(1, DEFAULT_CONTEXT_MAX_LEN - 3) .. "..."
        end
    else
        context = nil
    end

    return {
        uri = uri,
        line = opts.line,
        col = opts.col or 0,
        buffer_id = opts.buffer_id or vim.uri_to_bufnr(uri),
        lsp_type = opts.lsp_type or "unknown",
        file_name = file_name,
        file_path = file_path,
        context = context,
        timestamp = opts.timestamp or os.time(),
    }
end

--- 格式化历史项为显示文本
--- @param item JumpHistoryItem
--- @param index integer 索引（用于显示序号）
--- @return string
function M.format_item(item, index)
    -- 格式化时间
    local time_str = os.date("%H:%M:%S", item.timestamp)

    -- 格式化 LSP 类型（固定宽度）
    local type_str = item.lsp_type
    if #type_str > 10 then
        type_str = type_str:sub(1, 7) .. "..."
    end
    type_str = string.format("%-10s", type_str)

    -- 格式化文件位置
    local pos_str = string.format("%s:%d", item.file_name, item.line)
    if #pos_str > 25 then
        pos_str = "..." .. pos_str:sub(-22)
    end
    pos_str = string.format("%-25s", pos_str)

    -- 懒加载代码上下文：只在显示时才获取（如果还未获取）
    local context = item.context
    if not context or context == "" then
        context = M.get_line_context(item.uri, item.line)
        -- 缓存到 item 中，避免重复读取
        item.context = context
    end

    -- 确保上下文不超过限制
    if #context > DEFAULT_CONTEXT_MAX_LEN then
        context = context:sub(1, DEFAULT_CONTEXT_MAX_LEN - 3) .. "..."
    end

    return string.format(
        "[%s] %s │ %s │ %s",
        time_str,
        type_str,
        pos_str,
        context
    )
end

--- 获取历史列表的显示内容
--- @param state JumpHistoryState
--- @return string[] 显示行数组
function M.get_display_lines(state)
    if #state.items == 0 then
        return {
            "",
            "  No jump history yet",
            "",
            "  Tip: LSP jumps (definition, reference, etc.) will be recorded automatically",
            "",
        }
    end

    local lines = {}

    -- 标题
    table.insert(
        lines,
        string.format(" LspUI Jump History (%d items)", #state.items)
    )
    table.insert(lines, string.rep("─", 100))

    -- 历史项（倒序显示，最新的在上面）
    for i = #state.items, 1, -1 do
        local item = state.items[i]
        local formatted = M.format_item(item, i)
        table.insert(lines, " " .. formatted)
    end

    -- 底部提示
    table.insert(lines, string.rep("─", 100))
    table.insert(lines, " <CR>:Jump  d:Delete  c:Clear  q:Close")

    return lines
end

--- 清空历史
--- @param state JumpHistoryState
function M.clear_history(state)
    state.items = {}
end

--- 删除指定索引的历史项
--- @param state JumpHistoryState
--- @param index integer 索引（1-based）
--- @return boolean 是否删除成功
function M.remove_item(state, index)
    if index < 1 or index > #state.items then
        return false
    end

    table.remove(state.items, index)
    return true
end

--- 获取指定行号对应的历史项索引
--- @param display_line integer 显示行号（1-based）
--- @param total_items integer 总历史项数
--- @return integer? 历史项索引（1-based），如果不是历史项行则返回 nil
function M.get_item_index_from_display_line(display_line, total_items)
    -- 跳过标题行（前 2 行）和底部提示（最后 2 行）
    if display_line <= 2 or display_line > (2 + total_items) then
        return nil
    end

    -- 因为是倒序显示，需要反向计算
    local offset = display_line - 2 -- 减去标题行
    return total_items - offset + 1
end

return M
