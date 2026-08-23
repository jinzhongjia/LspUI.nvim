local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            h.child_start(child)
        end,
        post_once = child.stop,
    },
})

T["extract_text_highlights"] = new_set()

T["extract_text_highlights"]["extracts highlights from lua code"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        local text = "local function foo(a, b) return a + b end"
        local highlights = sh.extract_text_highlights("lua", text)

        local ok = #highlights > 0
        local all_valid = true
        for _, hl in ipairs(highlights) do
            if
                not hl.hl_group:match("^@")
                or hl.start_col < 0
                or hl.end_col > #text
                or hl.start_col >= hl.end_col
            then
                all_valid = false
            end
        end
        return { count = #highlights, ok = ok, all_valid = all_valid }
    ]])
    h.expect_truthy(result.ok)
    h.eq(true, result.all_valid)
end

T["extract_text_highlights"]["returns empty for unknown language"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        return #sh.extract_text_highlights(
            "no_such_language_xyz",
            "local a = 1"
        )
    ]])
    h.eq(0, result)
end

T["extract_text_highlights"]["returns empty for empty input"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        return {
            empty_text = #sh.extract_text_highlights("lua", ""),
            empty_lang = #sh.extract_text_highlights("", "local a = 1"),
        }
    ]])
    h.eq(0, result.empty_text)
    h.eq(0, result.empty_lang)
end

T["extract_text_highlights"]["cache returns identical results"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        local text = "local cached = require('mod')"
        local first = sh.extract_text_highlights("lua", text)
        local second = sh.extract_text_highlights("lua", text)
        return {
            same_table = first == second,
            equal = vim.deep_equal(first, second),
        }
    ]])
    -- 命中缓存应返回同一张表
    h.eq(true, result.same_table)
    h.eq(true, result.equal)
end

T["apply_text_highlights"] = new_set()

T["apply_text_highlights"]["places extmarks offset by col_start"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        local buf = vim.api.nvim_create_buf(false, true)
        local line = "   local x = call(1)"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })

        local ok = sh.apply_text_highlights(buf, 0, 3, #line, "lua")
        local marks =
            vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })

        local min_col = math.huge
        local groups_ok = true
        for _, mark in ipairs(marks) do
            min_col = math.min(min_col, mark[3])
            if not mark[4].hl_group:match("^@") then
                groups_ok = false
            end
        end
        return {
            ok = ok,
            count = #marks,
            min_col = min_col,
            groups_ok = groups_ok,
        }
    ]])
    h.eq(true, result.ok)
    h.expect_truthy(result.count > 0)
    -- 所有 extmark 都不能落进 3 列前缀区
    h.expect_truthy(result.min_col >= 3)
    h.eq(true, result.groups_ok)
end

T["apply_text_highlights"]["returns false when range is invalid"] = function()
    local result = child.lua([[
        local sh = require("LspUI.layer.source_highlight")
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc" })
        return {
            -- col_start 超过行长
            beyond = sh.apply_text_highlights(buf, 0, 10, 20, "lua"),
            -- 未知语言
            unknown = sh.apply_text_highlights(
                buf,
                0,
                0,
                3,
                "no_such_language_xyz"
            ),
            -- 行不存在
            no_line = sh.apply_text_highlights(buf, 5, 0, 3, "lua"),
        }
    ]])
    h.eq(false, result.beyond)
    h.eq(false, result.unknown)
    h.eq(false, result.no_line)
end

T["sub_view pending highlight"] = new_set()

T["sub_view pending highlight"]["highlights unloaded source without bufload"] = function()
    local result = child.lua([[
        local ClassSubView = require("LspUI.layer.sub_view")

        -- 磁盘上的"源文件"，只 bufadd 不加载
        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        file:write("local value = compute(42)\n")
        file:close()
        local source_buf = vim.fn.bufadd(path)

        local fired = 0
        vim.api.nvim_create_autocmd(
            { "BufReadPre", "BufReadPost", "FileType", "Syntax" },
            { callback = function() fired = fired + 1 end }
        )

        local sub = ClassSubView:New(true)
        local bufid = sub:GetBufID()
        local code_line = "   local value = compute(42)"
        vim.api.nvim_buf_set_lines(bufid, 0, -1, false, { code_line })

        sub:ApplySyntaxHighlight({
            lua = {
                {
                    line = 0,
                    col_start = 3,
                    col_end = #code_line,
                    source_buf = source_buf,
                    source_line = 0,
                    source_col_offset = 0,
                },
            },
        })

        -- 高亮在 vim.schedule 之后补上
        vim.wait(500, function()
            local marks = vim.api.nvim_buf_get_extmarks(bufid, -1, 0, -1, {})
            return #marks > 0
        end)

        local marks =
            vim.api.nvim_buf_get_extmarks(bufid, -1, 0, -1, { details = true })
        local has_ts_group = false
        for _, mark in ipairs(marks) do
            if
                mark[4].hl_group and tostring(mark[4].hl_group):match("^@")
            then
                has_ts_group = true
            end
        end

        local out = {
            marks = #marks,
            has_ts_group = has_ts_group,
            source_loaded = vim.api.nvim_buf_is_loaded(source_buf),
            fired = fired,
        }
        vim.fn.delete(path)
        return out
    ]])
    h.expect_truthy(result.marks > 0)
    h.eq(true, result.has_ts_group)
    -- 核心断言：源文件全程未被加载、未触发任何自动命令链
    h.eq(false, result.source_loaded)
    h.eq(0, result.fired)
end

T["sub_view pending highlight"]["loaded source still uses buffer path"] = function()
    local result = child.lua([[
        local ClassSubView = require("LspUI.layer.sub_view")

        local path = vim.fn.tempname() .. ".lua"
        local file = io.open(path, "w")
        file:write("local ready = true\n")
        file:close()
        local source_buf = vim.fn.bufadd(path)
        vim.fn.bufload(source_buf)
        vim.bo[source_buf].filetype = "lua"

        local sub = ClassSubView:New(true)
        local bufid = sub:GetBufID()
        local code_line = "   local ready = true"
        vim.api.nvim_buf_set_lines(bufid, 0, -1, false, { code_line })

        sub:ApplySyntaxHighlight({
            lua = {
                {
                    line = 0,
                    col_start = 3,
                    col_end = #code_line,
                    source_buf = source_buf,
                    source_line = 0,
                    source_col_offset = 0,
                },
            },
        })

        -- 已加载路径是同步的
        local marks = vim.api.nvim_buf_get_extmarks(bufid, -1, 0, -1, {})
        local out = { marks = #marks }
        vim.fn.delete(path)
        return out
    ]])
    h.expect_truthy(result.marks > 0)
end

return T
