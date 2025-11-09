-- 搜索/过滤功能模块
local api = vim.api

local M = {}

---@class SearchState
---@field enabled boolean 是否启用搜索模式
---@field pattern string 当前搜索模式
---@field matches table<integer, boolean> 匹配的行号映射
---@field match_count integer 匹配数量
---@field total_count integer 总行数
---@field current_index integer 当前匹配索引
---@field namespace integer 高亮命名空间

--- 创建搜索状态
---@return SearchState
function M.new_state()
    return {
        enabled = false,
        pattern = "",
        matches = {},
        match_count = 0,
        total_count = 0,
        current_index = 0,
        namespace = api.nvim_create_namespace("LspUI_Search"),
    }
end

--- 清除搜索高亮
---@param bufnr integer
---@param state SearchState
function M.clear_highlights(bufnr, state)
    if api.nvim_buf_is_valid(bufnr) then
        api.nvim_buf_clear_namespace(bufnr, state.namespace, 0, -1)
    end
end

--- 检查一行是否匹配搜索模式
---@param line string
---@param pattern string
---@param ignore_case boolean
---@return boolean, integer?, integer? 是否匹配，起始位置，结束位置
local function line_matches(line, pattern, ignore_case)
    if pattern == "" then
        return true, nil, nil
    end

    local search_line = ignore_case and line:lower() or line
    local search_pattern = ignore_case and pattern:lower() or pattern

    -- 尝试普通匹配
    local start_pos, end_pos = search_line:find(search_pattern, 1, true)
    if start_pos then
        return true, start_pos - 1, end_pos  -- 转换为0-based索引
    end

    return false, nil, nil
end

--- 更新搜索匹配并高亮
---@param bufnr integer
---@param state SearchState
---@param ignore_case boolean
function M.update_matches(bufnr, state, ignore_case)
    if not api.nvim_buf_is_valid(bufnr) then
        return
    end

    -- 清除旧的高亮
    M.clear_highlights(bufnr, state)

    -- 重置匹配信息
    state.matches = {}
    state.match_count = 0

    -- 如果搜索模式为空，所有行都匹配
    if state.pattern == "" then
        local line_count = api.nvim_buf_line_count(bufnr)
        for i = 0, line_count - 1 do
            state.matches[i] = true
        end
        state.match_count = line_count
        state.total_count = line_count
        return
    end

    -- 获取所有行
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    state.total_count = #lines

    -- 检查每一行
    for line_idx, line in ipairs(lines) do
        local lnum = line_idx - 1  -- 转换为0-based索引
        local matches, start_col, end_col = line_matches(line, state.pattern, ignore_case)

        if matches then
            state.matches[lnum] = true
            state.match_count = state.match_count + 1

            -- 高亮匹配的文本
            if start_col and end_col then
                api.nvim_buf_add_highlight(
                    bufnr,
                    state.namespace,
                    "Search",
                    lnum,
                    start_col,
                    end_col
                )
            end
        end
    end
end

--- 获取下一个匹配的行号
---@param state SearchState
---@param current_line integer 当前行号(0-based)
---@return integer? 下一个匹配的行号，如果没有则返回nil
function M.next_match(state, current_line)
    if state.match_count == 0 then
        return nil
    end

    -- 从当前行之后查找
    for line = current_line + 1, state.total_count - 1 do
        if state.matches[line] then
            return line
        end
    end

    -- 循环到开头
    for line = 0, current_line do
        if state.matches[line] then
            return line
        end
    end

    return nil
end

--- 获取上一个匹配的行号
---@param state SearchState
---@param current_line integer 当前行号(0-based)
---@return integer? 上一个匹配的行号，如果没有则返回nil
function M.prev_match(state, current_line)
    if state.match_count == 0 then
        return nil
    end

    -- 从当前行之前查找
    for line = current_line - 1, 0, -1 do
        if state.matches[line] then
            return line
        end
    end

    -- 循环到末尾
    for line = state.total_count - 1, current_line, -1 do
        if state.matches[line] then
            return line
        end
    end

    return nil
end

--- 过滤行，只保留匹配的行
---@param lines string[] 所有行
---@param state SearchState
---@return string[], table<integer, integer> 过滤后的行和原始行号映射
function M.filter_lines(lines, state)
    if state.pattern == "" then
        local line_map = {}
        for i = 1, #lines do
            line_map[i] = i - 1  -- 映射到0-based原始行号
        end
        return lines, line_map
    end

    local filtered = {}
    local line_map = {}  -- 新行号 -> 原始行号的映射

    for idx, line in ipairs(lines) do
        local lnum = idx - 1  -- 0-based
        if state.matches[lnum] then
            table.insert(filtered, line)
            line_map[#filtered] = lnum
        end
    end

    return filtered, line_map
end

--- 获取搜索状态字符串
---@param state SearchState
---@param virtual_scroll_info table? 虚拟滚动信息 {loaded: number, total: number}
---@return string
function M.get_status_line(state, virtual_scroll_info)
    if not state.enabled then
        return ""
    end

    if state.pattern == "" then
        return " [Search: (empty)] "
    end

    if state.match_count == 0 then
        return string.format(" [Search: '%s' - No matches] ", state.pattern)
    end

    -- 虚拟滚动搜索过滤模式
    if virtual_scroll_info and virtual_scroll_info.total > 0 then
        return string.format(
            " [Search: '%s' - %d/%d matches] (%d/%d files loaded) ",
            state.pattern,
            state.match_count,
            state.total_count,
            virtual_scroll_info.loaded,
            virtual_scroll_info.total
        )
    end

    return string.format(
        " [Search: '%s' - %d/%d matches] ",
        state.pattern,
        state.match_count,
        state.total_count
    )
end

--- 进入搜索模式
---@param bufnr integer
---@param state SearchState
---@param on_change function? 搜索模式变化时的回调
---@param on_exit function? 退出搜索时的回调
function M.enter_search_mode(bufnr, state, on_change, on_exit)
    if not api.nvim_buf_is_valid(bufnr) then
        return
    end

    state.enabled = true
    state.pattern = ""

    -- 创建输入提示
    vim.ui.input({
        prompt = "Search: ",
        default = state.pattern,
    }, function(input)
        if input then
            state.pattern = input
            M.update_matches(bufnr, state, true)

            if on_change then
                on_change(state)
            end
        else
            -- 用户取消了输入
            state.enabled = false
            M.clear_highlights(bufnr, state)

            if on_exit then
                on_exit(state)
            end
        end
    end)
end

--- 清除搜索
---@param bufnr integer
---@param state SearchState
function M.clear_search(bufnr, state)
    state.enabled = false
    state.pattern = ""
    state.matches = {}
    state.match_count = 0
    state.current_index = 0
    M.clear_highlights(bufnr, state)
end

return M
