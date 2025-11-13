-- 简单的关键字高亮模块（用于代码片段）
local api = vim.api

local M = {}

-- 语言关键字定义
local LANGUAGE_KEYWORDS = {
    go = {
        keywords = {
            "break", "case", "chan", "const", "continue", "default", "defer",
            "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
            "interface", "map", "package", "range", "return", "select", "struct",
            "switch", "type", "var",
        },
        types = {
            "bool", "byte", "complex64", "complex128", "error", "float32",
            "float64", "int", "int8", "int16", "int32", "int64", "rune",
            "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
        },
        builtins = {
            "append", "cap", "close", "complex", "copy", "delete", "imag",
            "len", "make", "new", "panic", "print", "println", "real", "recover",
        },
    },
    typescript = {
        keywords = {
            "abstract", "as", "async", "await", "break", "case", "catch",
            "class", "const", "continue", "debugger", "declare", "default",
            "delete", "do", "else", "enum", "export", "extends", "false",
            "finally", "for", "from", "function", "get", "if", "implements",
            "import", "in", "instanceof", "interface", "is", "let", "module",
            "namespace", "new", "null", "of", "package", "private", "protected",
            "public", "readonly", "return", "set", "static", "super", "switch",
            "this", "throw", "true", "try", "type", "typeof", "var", "void",
            "while", "with", "yield",
        },
        types = {
            "any", "bigint", "boolean", "never", "null", "number", "object",
            "string", "symbol", "undefined", "unknown", "void",
        },
        builtins = {
            "Array", "Boolean", "Date", "Error", "Function", "Map", "Number",
            "Object", "Promise", "RegExp", "Set", "String", "Symbol",
        },
    },
    javascript = {
        keywords = {
            "async", "await", "break", "case", "catch", "class", "const",
            "continue", "debugger", "default", "delete", "do", "else", "export",
            "extends", "false", "finally", "for", "function", "if", "import",
            "in", "instanceof", "let", "new", "null", "of", "return", "static",
            "super", "switch", "this", "throw", "true", "try", "typeof", "var",
            "void", "while", "with", "yield",
        },
        types = {"null", "undefined"},
        builtins = {
            "Array", "Boolean", "Date", "Error", "Function", "JSON", "Math",
            "Number", "Object", "Promise", "RegExp", "String",
        },
    },
    python = {
        keywords = {
            "False", "None", "True", "and", "as", "assert", "async", "await",
            "break", "class", "continue", "def", "del", "elif", "else", "except",
            "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
            "try", "while", "with", "yield",
        },
        types = {"int", "float", "str", "bool", "list", "dict", "tuple", "set"},
        builtins = {
            "abs", "all", "any", "bin", "chr", "dir", "enumerate", "filter",
            "help", "len", "map", "max", "min", "open", "ord", "print", "range",
            "round", "sorted", "sum", "type", "zip",
        },
    },
}

-- 应用关键字高亮到 buffer
function M.apply(buf, lang, regions)
    local keywords_def = LANGUAGE_KEYWORDS[lang]
    if not keywords_def then
        return false  -- 不支持的语言
    end

    local highlight_ns = api.nvim_create_namespace("LspUI_keyword_" .. lang)

    for _, region in ipairs(regions) do
        -- region 格式: {{line, col_start}, {line, col_end}}
        local start_row = region[1][1]
        local start_col = region[1][2]
        local end_row = region[2][1]
        local end_col = region[2][2]

        -- 获取该行的文本
        local line_text = api.nvim_buf_get_lines(buf, start_row, start_row + 1, false)[1] or ""
        local text = line_text:sub(start_col + 1, end_col)

        -- 高亮关键字
        M._highlight_keywords(buf, highlight_ns, start_row, start_col, text, keywords_def.keywords, "@keyword")

        -- 高亮类型
        M._highlight_keywords(buf, highlight_ns, start_row, start_col, text, keywords_def.types, "@type")

        -- 高亮内置函数
        M._highlight_keywords(buf, highlight_ns, start_row, start_col, text, keywords_def.builtins, "@function.builtin")
    end

    return true
end

-- 在文本中匹配并高亮关键字
function M._highlight_keywords(buf, ns, row, col_offset, text, keywords, hl_group)
    for _, keyword in ipairs(keywords) do
        -- 使用单词边界匹配
        local pattern = "%f[%w_]" .. vim.pesc(keyword) .. "%f[^%w_]"
        local start_pos = 1

        while true do
            local s, e = text:find(pattern, start_pos)
            if not s then
                break
            end

            -- 应用高亮
            api.nvim_buf_add_highlight(
                buf,
                ns,
                hl_group,
                row,
                col_offset + s - 1,
                col_offset + e
            )

            start_pos = e + 1
        end
    end
end

-- 清除高亮
function M.clear(buf, lang)
    local highlight_ns = api.nvim_create_namespace("LspUI_keyword_" .. lang)
    api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
end

return M
