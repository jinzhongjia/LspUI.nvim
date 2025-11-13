-- 从源文件提取 Treesitter 高亮信息的模块
local api = vim.api

local M = {}

-- 缓存已提取的高亮信息，避免重复解析
-- cache[source_buf][line_num] = { {hl_group, start_col, end_col}, ... }
--
-- 注意：缓存策略
-- 1. 只在 BufDelete/BufWipeout 时清理，不监听文件内容变化
-- 2. 假设源 buffer 在 SubView 显示期间不会被修改
-- 3. 如果用户修改了源文件，SubView 通常会关闭并重新打开，缓存会被重建
-- 4. 即使缓存过期，最坏情况是显示旧的高亮，不会导致崩溃
M.cache = {}

--- 从源缓冲区提取指定行的 Treesitter 高亮信息
--- @param source_buf integer 源文件的 buffer ID
--- @param source_line integer 源文件中的行号（0-indexed）
--- @return table[] 高亮信息数组，每项为 {hl_group, start_col, end_col}
function M.extract_line_highlights(source_buf, source_line)
    -- 检查缓存
    if M.cache[source_buf] and M.cache[source_buf][source_line] then
        return M.cache[source_buf][source_line]
    end

    -- 验证 buffer 是否有效
    if not api.nvim_buf_is_valid(source_buf) then
        return {}
    end

    -- 获取该行的文本
    local ok, lines = pcall(api.nvim_buf_get_lines, source_buf, source_line, source_line + 1, false)
    if not ok or not lines or #lines == 0 then
        return {}
    end
    local line_text = lines[1]

    local highlights = {}

    -- 直接尝试获取 parser，不创建新的 highlighter
    local success, parser = pcall(vim.treesitter.get_parser, source_buf)
    if not success or not parser then
        return {}
    end

    -- 确保 parser 已解析
    local parse_ok, trees = pcall(parser.parse, parser)
    if not parse_ok or not trees or #trees == 0 then
        return {}
    end

    -- 获取语言和 query
    local lang = parser:lang()
    local query_ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not query_ok or not query then
        return {}
    end

    -- 遍历所有树（支持注入的语言）
    for _, tree in ipairs(trees) do
        local root = tree:root()
        if not root then
            goto continue
        end

        -- 使用 query 获取该行的高亮
        local iter_ok, iter = pcall(query.iter_captures, query, root, source_buf, source_line, source_line + 1)
        if not iter_ok then
            goto continue
        end

        for id, node, metadata in iter do
            local range_ok, start_row, start_col, end_row, end_col = pcall(node.range, node)
            if not range_ok then
                goto continue_capture
            end

            local capture_name = query.captures[id]
            if not capture_name then
                goto continue_capture
            end

            -- 只处理与当前行相交的节点
            if start_row <= source_line and end_row >= source_line then
                -- 计算在当前行的实际列范围
                local actual_start_col = start_row == source_line and start_col or 0
                local actual_end_col = end_row == source_line and end_col or #line_text

                if actual_start_col < actual_end_col then
                    -- 提取优先级（如果有）
                    local priority = 100
                    if type(metadata) == "table" and type(metadata.priority) == "number" then
                        priority = metadata.priority
                    end

                    table.insert(highlights, {
                        hl_group = "@" .. capture_name,
                        start_col = actual_start_col,
                        end_col = actual_end_col,
                        priority = priority,
                    })
                end
            end

            ::continue_capture::
        end

        ::continue::
    end

    -- 按优先级和位置排序
    table.sort(highlights, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.start_col < b.start_col
    end)

    -- 缓存结果（即使是空的也缓存，避免重复尝试）
    M.cache[source_buf] = M.cache[source_buf] or {}
    M.cache[source_buf][source_line] = highlights

    return highlights
end

--- 应用提取的高亮到目标 buffer 的指定区域
--- @param target_buf integer 目标 buffer ID
--- @param target_line integer 目标行号（0-indexed）
--- @param target_col_start integer 目标起始列（0-indexed），代码在目标buffer中的起始位置
--- @param target_col_end integer 目标区域的字符串长度（用于兼容controller的col_end语义）
--- @param source_buf integer 源 buffer ID
--- @param source_line integer 源行号（0-indexed）
--- @param source_col_offset integer? 源文件中的列偏移（默认0），用于处理只显示部分代码的情况
function M.apply_highlights(target_buf, target_line, target_col_start, target_col_end, source_buf, source_line, source_col_offset)
    source_col_offset = source_col_offset or 0

    local highlights = M.extract_line_highlights(source_buf, source_line)

    if #highlights == 0 then
        return false
    end

    -- 创建命名空间
    local ns = api.nvim_create_namespace("LspUI_source_highlight")

    -- 获取目标行的实际文本，用于确定有效范围
    local target_line_text = api.nvim_buf_get_lines(target_buf, target_line, target_line + 1, false)[1]
    if not target_line_text then
        return false
    end

    -- 计算实际的目标区域结束位置（0-indexed）
    -- target_col_end 是字符串长度，需要转换为 0-indexed 的结束位置
    local actual_target_end = math.min(target_col_end, #target_line_text)

    -- 应用高亮
    for _, hl in ipairs(highlights) do
        -- 源文件中高亮的位置（0-indexed）
        local src_start = hl.start_col
        local src_end = hl.end_col

        -- 计算在目标 buffer 中的位置
        -- 源文件的高亮区域映射到目标区域
        local target_start = target_col_start + (src_start - source_col_offset)
        local target_end = target_col_start + (src_end - source_col_offset)

        -- 裁剪到目标区域的有效范围内
        target_start = math.max(target_start, target_col_start)
        target_end = math.min(target_end, actual_target_end)

        -- 应用高亮
        if target_start < target_end and target_start >= 0 then
            pcall(api.nvim_buf_add_highlight,
                target_buf,
                ns,
                hl.hl_group,
                target_line,
                target_start,
                target_end
            )
        end
    end

    return true
end

--- 清除缓存
--- @param source_buf? integer 如果提供，只清除该 buffer 的缓存；否则清除所有
function M.clear_cache(source_buf)
    if source_buf then
        M.cache[source_buf] = nil
    else
        M.cache = {}
    end
end

-- 自动清理缓存的自动命令
api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
    group = api.nvim_create_augroup("LspUI.source_highlight", { clear = true }),
    callback = function(ev)
        M.clear_cache(ev.buf)
    end,
})

return M
