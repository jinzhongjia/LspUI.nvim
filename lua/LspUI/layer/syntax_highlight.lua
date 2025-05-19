local api = vim.api

local M = {}

-- 缓存已创建的高亮器
M.cache = {}
-- 创建命名空间
local ns = api.nvim_create_namespace("LspUI.syntax_highlight")

-- 封装 Treesitter 高亮器方法
local function wrap_method(method_name)
    return function(_, win, buf, ...)
        if not M.cache[buf] then
            return false
        end

        for _, hl in pairs(M.cache[buf] or {}) do
            if hl.enabled then
                vim.treesitter.highlighter.active[buf] = hl.highlighter
                vim.treesitter.highlighter[method_name](_, win, buf, ...)
            end
        end

        vim.treesitter.highlighter.active[buf] = nil
    end
end

-- 初始化状态
M.did_setup = false

-- 设置高亮器
function M.setup()
    if M.did_setup then
        return
    end
    M.did_setup = true

    -- 注册装饰提供程序
    api.nvim_set_decoration_provider(ns, {
        on_win = wrap_method("_on_win"),
        on_line = wrap_method("_on_line"),
    })

    -- 创建自动命令清理缓存
    api.nvim_create_autocmd("BufWipeout", {
        group = api.nvim_create_augroup(
            "LspUI.syntax_highlight",
            { clear = true }
        ),
        callback = function(ev)
            M.cache[ev.buf] = nil
        end,
    })
end

-- 获取一段文本在缓冲区中的字节偏移量
---@diagnostic disable-next-line: unused-local, unused-function
local function get_byte_offset(buf, row, col, text)
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    if col >= #line then
        return api.nvim_buf_get_offset(buf, row) + col
    end

    -- 使用UTF-8字节长度计算
    local prefix = string.sub(line, 1, col)
    return api.nvim_buf_get_offset(buf, row) + #prefix
end

-- 为缓冲区添加语法高亮
function M.attach(buf, regions)
    M.setup()
    M.cache[buf] = M.cache[buf] or {}

    -- 禁用不在regions中的语言高亮器
    for lang in pairs(M.cache[buf]) do
        M.cache[buf][lang].enabled = regions[lang] ~= nil
    end

    -- 为每种语言添加高亮器
    for lang, lang_regions in pairs(regions) do
        M._attach_lang(buf, lang, lang_regions)
    end
end

-- 为特定语言添加高亮器
function M._attach_lang(buf, lang, regions)
    -- 跳过空语言
    if lang == "" then
        return
    end

    M.cache[buf] = M.cache[buf] or {}

    -- 格式化regions为Treesitter期望的格式
    local formatted_regions = {}

    for _, region in ipairs(regions) do
        local start_row, start_col = region[1][1], region[1][2]
        local end_row, end_col = region[2][1], region[2][2]

        -- 获取字节偏移量
        local start_byte = api.nvim_buf_get_offset(buf, start_row) + start_col
        local end_byte

        if end_row == start_row then
            -- 同一行的情况
            local line = api.nvim_buf_get_lines(
                buf,
                start_row,
                start_row + 1,
                false
            )[1] or ""
            -- 确保不超出行长度
            local effective_end_col = math.min(end_col, #line)
            end_byte = api.nvim_buf_get_offset(buf, end_row) + effective_end_col
        else
            -- 跨行的情况
            local end_line = api.nvim_buf_get_lines(
                buf,
                end_row,
                end_row + 1,
                false
            )[1] or ""
            -- 确保不超出行长度
            local effective_end_col = math.min(end_col, #end_line)
            end_byte = api.nvim_buf_get_offset(buf, end_row) + effective_end_col
        end

        -- 添加格式化后的区域
        table.insert(formatted_regions, {
            start_row,
            start_col,
            start_byte,
            end_row,
            end_col,
            end_byte,
        })
    end

    -- 尝试创建解析器
    local ok, parser
    if lang == "markdown" then
        ok, parser =
            pcall(vim.treesitter.languagetree.new, buf, "markdown_inline")
    else
        ok, parser = pcall(vim.treesitter.languagetree.new, buf, lang)
    end

    -- 如果创建失败，尝试使用基本语言
    if not ok and lang:find("%.") then
        local base_lang = lang:match("^[^%.]+")
        ok, parser = pcall(vim.treesitter.languagetree.new, buf, base_lang)
    end

    -- 如果仍然失败，记录错误并返回
    if not ok then
        vim.notify_once(
            "LspUI 无法为 " .. lang .. " 创建语法高亮",
            vim.log.levels.WARN
        )
        return
    end

    -- 设置包含的区域
    ---@diagnostic disable-next-line: invisible
    parser:set_included_regions({ formatted_regions })

    -- 创建或更新高亮器
    if not M.cache[buf][lang] then
        M.cache[buf][lang] = {
            parser = parser,
            highlighter = vim.treesitter.highlighter.new(parser),
            enabled = true,
        }
    else
        local old_parser = M.cache[buf][lang].parser
        old_parser:set_included_regions({ formatted_regions })
        M.cache[buf][lang].enabled = true
    end
end

-- 从缓冲区中移除高亮器
function M.detach(buf)
    if M.cache[buf] then
        M.cache[buf] = nil
    end
end

return M
