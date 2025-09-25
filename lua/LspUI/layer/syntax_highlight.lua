local notify = require("LspUI.layer.notify")
local api = vim.api

local M = {}

-- 缓存已创建的高亮器
M.cache = {}
-- 创建命名空间
local ns = api.nvim_create_namespace("LspUI.syntax_highlight")

-- 语言映射表：将 filetype 映射到 treesitter parser 名称
local language_map = {
    typescriptreact = "tsx",
    javascriptreact = "jsx",
    -- 可以根据需要添加更多映射
}

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

    -- 应用语言名称映射
    local mapped_lang = language_map[lang] or lang

    M.cache[buf] = M.cache[buf] or {}

    -- 验证regions数据
    if not regions or #regions == 0 then
        return
    end

    -- 格式化regions为Treesitter期望的格式
    local formatted_regions = {}

    for _, region in ipairs(regions) do
        -- 验证region格式
        if not region or not region[1] or not region[2] then
            notify.Warn("LspUI: Invalid region format for " .. lang)
            goto continue
        end

        local start_row, start_col = region[1][1], region[1][2]
        local end_row, end_col = region[2][1], region[2][2]

        -- 验证行列号
        if start_row < 0 or start_col < 0 or end_row < 0 or end_col < 0 then
            goto continue
        end

        -- 获取字节偏移量（保持原有逻辑）
        local start_byte = api.nvim_buf_get_offset(buf, start_row) + start_col
        local end_byte

        if end_row == start_row then
            local line = api.nvim_buf_get_lines(
                buf,
                start_row,
                start_row + 1,
                false
            )[1] or ""
            local effective_end_col = math.min(end_col, #line)
            end_byte = api.nvim_buf_get_offset(buf, end_row) + effective_end_col
        else
            local end_line = api.nvim_buf_get_lines(
                buf,
                end_row,
                end_row + 1,
                false
            )[1] or ""
            local effective_end_col = math.min(end_col, #end_line)
            end_byte = api.nvim_buf_get_offset(buf, end_row) + effective_end_col
        end

        -- 确保字节偏移量有效
        if start_byte >= end_byte then
            goto continue
        end

        table.insert(formatted_regions, {
            start_row,
            start_col,
            start_byte,
            end_row,
            end_col,
            end_byte,
        })

        ::continue::
    end

    if #formatted_regions == 0 then
        return
    end

    -- 尝试创建解析器
    local ok, parser
    local tried_langs = {}

    -- 首先尝试映射后的语言
    ok, parser = pcall(vim.treesitter.languagetree.new, buf, mapped_lang)
    table.insert(tried_langs, mapped_lang)

    -- 如果失败且包含点号，尝试基本语言
    if not ok and mapped_lang:find("%.") then
        local base_lang = mapped_lang:match("^[^%.]+")
        ok, parser = pcall(vim.treesitter.languagetree.new, buf, base_lang)
        table.insert(tried_langs, base_lang)
    end

    -- 如果仍然失败，尝试原始语言名
    if not ok and mapped_lang ~= lang then
        ok, parser = pcall(vim.treesitter.languagetree.new, buf, lang)
        table.insert(tried_langs, lang)
    end

    if not ok then
        notify.Warn(
            string.format(
                "LspUI cannot create syntax highlighting for %s (tried: %s)",
                lang,
                table.concat(tried_langs, ", ")
            )
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
