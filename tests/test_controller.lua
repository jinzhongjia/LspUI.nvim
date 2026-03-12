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

T["controller"] = new_set()

T["controller"]["onCursorMoved short-circuits unchanged selection"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")

            local ctl = setmetatable({}, ClassController)
            local range = {
                start = { line = 1, character = 2 },
                finish = { line = 1, character = 4 },
            }

            ctl._current_item = {
                uri = "file:///tmp/a.lua",
                buffer_id = 1,
                range = vim.deepcopy(range),
                is_file_header = false,
            }

            local heavy_calls = 0
            local load_more_calls = 0

            ctl._getLspPositionByLnum = function()
                return "file:///tmp/a.lua", range
            end

            ctl._checkAndLoadMore = function()
                load_more_calls = load_more_calls + 1
            end

            ctl._mainView = {
                Valid = function() return true end,
                UnPinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetBufID = function() return 1 end,
                RestoreKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                SwitchBuffer = function() heavy_calls = heavy_calls + 1 end,
                SaveKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                PinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetWinID = function() heavy_calls = heavy_calls + 1; return nil end,
                SetHighlight = function() heavy_calls = heavy_calls + 1 end,
            }

            ctl._lsp = {
                GetData = function()
                    return { ["file:///tmp/a.lua"] = { buffer_id = 1 } }
                end,
            }

            ctl._virtual_scroll = { enabled = true }

            ctl:_onCursorMoved()

            return {
                heavy_calls = heavy_calls,
                load_more_calls = load_more_calls,
                uri_unchanged = ctl._current_item.uri == "file:///tmp/a.lua",
                range_unchanged = ctl._current_item.range.start.line == 1,
            }
        ]])

    h.eq(0, result.heavy_calls)
    h.eq(1, result.load_more_calls)
    h.eq(true, result.uri_unchanged)
    h.eq(true, result.range_unchanged)
end

T["controller"]["onCursorMoved still updates when selection changes"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")

            local ctl = setmetatable({}, ClassController)
            local old_range = {
                start = { line = 1, character = 2 },
                finish = { line = 1, character = 4 },
            }
            local new_range = {
                start = { line = 2, character = 0 },
                finish = { line = 2, character = 3 },
            }

            ctl._current_item = {
                uri = "file:///tmp/a.lua",
                buffer_id = 1,
                range = old_range,
                is_file_header = false,
            }

            local heavy_calls = 0
            ctl._getLspPositionByLnum = function()
                return "file:///tmp/a.lua", new_range
            end
            ctl._setupMainViewKeyBindings = function()
                heavy_calls = heavy_calls + 1
            end

            ctl._mainView = {
                Valid = function() return true end,
                UnPinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetBufID = function() return 1 end,
                RestoreKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                SwitchBuffer = function() heavy_calls = heavy_calls + 1 end,
                SaveKeyMappings = function() heavy_calls = heavy_calls + 1 end,
                PinBuffer = function() heavy_calls = heavy_calls + 1 end,
                GetWinID = function() return nil end,
                SetHighlight = function() heavy_calls = heavy_calls + 1 end,
            }

            ctl._lsp = {
                GetData = function()
                    return { ["file:///tmp/a.lua"] = { buffer_id = 1 } }
                end,
            }

            ctl._virtual_scroll = { enabled = false }

            ctl:_onCursorMoved()

            return {
                heavy_calls = heavy_calls,
                new_line = ctl._current_item.range.start.line,
            }
        ]])

    h.eq(true, result.heavy_calls > 0)
    h.eq(2, result.new_line)
end

T["controller"]["_generateCodeLinesForUri returns formatted lines"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")
            local tools = require("LspUI.layer.tools")

            -- Mock tools.GetUriLines to return source lines
            tools.GetUriLines = function(_, _, rows)
                local lines = {}
                lines[0] = "    local x = 1"
                lines[1] = "    local y = 2"
                return lines
            end

            local ctl = setmetatable({}, ClassController)

            local item = {
                buffer_id = 1,
                fold = false,
                range = {
                    { start = { line = 0, character = 4 }, finish = { line = 0, character = 15 } },
                    { start = { line = 1, character = 4 }, finish = { line = 1, character = 15 } },
                },
            }

            local code_lines = ctl:_generateCodeLinesForUri("file:///tmp/a.lua", item)

            return {
                line_count = #code_lines,
                first_line = code_lines[1],
                second_line = code_lines[2],
            }
        ]])

    h.eq(2, result.line_count)
    h.eq("   local x = 1", result.first_line)
    h.eq("   local y = 2", result.second_line)
end

T["controller"]["_incrementalToggleFold collapses correctly"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")
            local tools = require("LspUI.layer.tools")
            local lib_path = require("LspUI.lib.path")

            -- Mock dependencies
            tools.detect_filetype = function() return "lua" end
            tools.GetUriLines = function(_, _, rows)
                local lines = {}
                for _, r in ipairs(rows) do lines[r] = "  code" .. r end
                return lines
            end
            lib_path.get_relative_path = function() return "a.lua" end
            lib_path.format_relative_display = function() return "a.lua" end

            local ctl = setmetatable({}, ClassController)

            -- Create a buffer with initial content (2 files, each with 2 code lines)
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                " ▼ a.lua",    -- line 1: file A header
                "   code0",    -- line 2: file A code 1
                "   code1",    -- line 3: file A code 2
                " ▼ b.lua",    -- line 4: file B header
                "   code0",    -- line 5: file B code 1
                "   code1",    -- line 6: file B code 2
            })

            local uri_a = "file:///tmp/a.lua"
            local uri_b = "file:///tmp/b.lua"
            local range_a1 = { start = { line = 0, character = 0 }, finish = { line = 0, character = 5 } }
            local range_a2 = { start = { line = 1, character = 0 }, finish = { line = 1, character = 5 } }
            local range_b1 = { start = { line = 0, character = 0 }, finish = { line = 0, character = 5 } }
            local range_b2 = { start = { line = 1, character = 0 }, finish = { line = 1, character = 5 } }

            ctl._line_map = {
                [1] = { uri = uri_a, range = nil },
                [2] = { uri = uri_a, range = range_a1 },
                [3] = { uri = uri_a, range = range_a2 },
                [4] = { uri = uri_b, range = nil },
                [5] = { uri = uri_b, range = range_b1 },
                [6] = { uri = uri_b, range = range_b2 },
            }

            local data = {
                [uri_a] = { buffer_id = 1, fold = false, range = { range_a1, range_a2 } },
                [uri_b] = { buffer_id = 2, fold = false, range = { range_b1, range_b2 } },
            }

            ctl._lsp = { GetData = function() return data end }
            ctl._subView = {
                GetBufID = function() return buf end,
                GetWinID = function() return nil end,
                ClearSyntaxHighlight = function() end,
                ApplySyntaxHighlight = function() end,
            }

            -- Collapse file A
            ctl:_incrementalToggleFold(uri_a)

            -- Check buffer content
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            -- Check line_map
            local map_keys = {}
            for k in pairs(ctl._line_map) do table.insert(map_keys, k) end
            table.sort(map_keys)

            return {
                fold_state = data[uri_a].fold,
                line_count = #lines,
                header_a = lines[1],
                header_b = lines[2],
                code_b1 = lines[3],
                code_b2 = lines[4],
                map_keys = map_keys,
                -- file B header should now be at line 2
                map_2_uri = ctl._line_map[2] and ctl._line_map[2].uri or "nil",
                map_2_is_header = ctl._line_map[2] and ctl._line_map[2].range == nil,
            }
        ]])

    h.eq(true, result.fold_state)
    h.eq(4, result.line_count)
    h.expect_match("▶", result.header_a) -- collapsed icon
    h.expect_match("▼", result.header_b) -- still expanded
    h.eq("   code0", result.code_b1)
    h.eq("   code1", result.code_b2)
    -- line_map: line 1 = A header, line 2 = B header, line 3 = B code1, line 4 = B code2
    h.eq({ 1, 2, 3, 4 }, result.map_keys)
    h.eq("file:///tmp/b.lua", result.map_2_uri)
    h.eq(true, result.map_2_is_header)
end

T["controller"]["_incrementalToggleFold expands correctly"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")
            local tools = require("LspUI.layer.tools")
            local lib_path = require("LspUI.lib.path")

            -- Mock dependencies
            tools.detect_filetype = function() return "lua" end
            tools.GetUriLines = function(_, _, rows)
                local lines = {}
                for _, r in ipairs(rows) do lines[r] = "  code" .. r end
                return lines
            end
            lib_path.get_relative_path = function() return "b.lua" end
            lib_path.format_relative_display = function() return "b.lua" end

            local ctl = setmetatable({}, ClassController)

            local uri_a = "file:///tmp/a.lua"
            local uri_b = "file:///tmp/b.lua"
            local range_a1 = { start = { line = 0, character = 0 }, finish = { line = 0, character = 5 } }
            local range_a2 = { start = { line = 1, character = 0 }, finish = { line = 1, character = 5 } }
            local range_b1 = { start = { line = 0, character = 0 }, finish = { line = 0, character = 5 } }
            local range_b2 = { start = { line = 1, character = 0 }, finish = { line = 1, character = 5 } }

            -- Start with file A collapsed, file B expanded
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                " ▶ a.lua",    -- line 1: file A header (collapsed)
                " ▼ b.lua",    -- line 2: file B header
                "   code0",    -- line 3: file B code 1
                "   code1",    -- line 4: file B code 2
            })

            ctl._line_map = {
                [1] = { uri = uri_a, range = nil },
                [2] = { uri = uri_b, range = nil },
                [3] = { uri = uri_b, range = range_b1 },
                [4] = { uri = uri_b, range = range_b2 },
            }

            local data = {
                [uri_a] = { buffer_id = 1, fold = true, range = { range_a1, range_a2 } },
                [uri_b] = { buffer_id = 2, fold = false, range = { range_b1, range_b2 } },
            }

            ctl._lsp = { GetData = function() return data end }
            ctl._subView = {
                GetBufID = function() return buf end,
                GetWinID = function() return nil end,
                ClearSyntaxHighlight = function() end,
                ApplySyntaxHighlight = function() end,
            }

            -- Expand file A
            ctl:_incrementalToggleFold(uri_a)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            local map_keys = {}
            for k in pairs(ctl._line_map) do table.insert(map_keys, k) end
            table.sort(map_keys)

            return {
                fold_state = data[uri_a].fold,
                line_count = #lines,
                header_a = lines[1],
                code_a1 = lines[2],
                code_a2 = lines[3],
                header_b = lines[4],
                map_keys = map_keys,
                -- After expanding A, B header should be at line 4
                map_4_uri = ctl._line_map[4] and ctl._line_map[4].uri or "nil",
                map_4_is_header = ctl._line_map[4] and ctl._line_map[4].range == nil,
                -- New code lines for A should be in line_map
                map_2_has_range = ctl._line_map[2] and ctl._line_map[2].range ~= nil,
                map_3_has_range = ctl._line_map[3] and ctl._line_map[3].range ~= nil,
            }
        ]])

    h.eq(false, result.fold_state)
    h.eq(6, result.line_count)
    h.expect_match("▼", result.header_a) -- expanded icon
    h.eq("   code0", result.code_a1)
    h.eq("   code1", result.code_a2)
    h.expect_match("▼", result.header_b)
    h.eq({ 1, 2, 3, 4, 5, 6 }, result.map_keys)
    h.eq("file:///tmp/b.lua", result.map_4_uri)
    h.eq(true, result.map_4_is_header)
    h.eq(true, result.map_2_has_range)
    h.eq(true, result.map_3_has_range)
end

T["controller"]["_incrementalToggleFold preserves lines above cursor"] = function()
    local result = child.lua([[
            local ClassController = require("LspUI.layer.controller")
            local tools = require("LspUI.layer.tools")
            local lib_path = require("LspUI.lib.path")

            tools.detect_filetype = function() return "lua" end
            tools.GetUriLines = function(_, _, rows)
                local lines = {}
                for _, r in ipairs(rows) do lines[r] = "  code" .. r end
                return lines
            end
            lib_path.get_relative_path = function() return "test" end
            lib_path.format_relative_display = function() return "test" end

            local ctl = setmetatable({}, ClassController)

            local uri_a = "file:///tmp/a.lua"
            local uri_b = "file:///tmp/b.lua"
            local uri_c = "file:///tmp/c.lua"

            local range1 = { start = { line = 0, character = 0 }, finish = { line = 0, character = 5 } }

            -- 3 files, each with 1 code line, all expanded
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                " ▼ a.lua",    -- 1
                "   code0",    -- 2
                " ▼ b.lua",    -- 3
                "   code0",    -- 4
                " ▼ c.lua",    -- 5
                "   code0",    -- 6
            })

            ctl._line_map = {
                [1] = { uri = uri_a, range = nil },
                [2] = { uri = uri_a, range = range1 },
                [3] = { uri = uri_b, range = nil },
                [4] = { uri = uri_b, range = range1 },
                [5] = { uri = uri_c, range = nil },
                [6] = { uri = uri_c, range = range1 },
            }

            local data = {
                [uri_a] = { buffer_id = 1, fold = false, range = { range1 } },
                [uri_b] = { buffer_id = 2, fold = false, range = { range1 } },
                [uri_c] = { buffer_id = 3, fold = false, range = { range1 } },
            }

            ctl._lsp = { GetData = function() return data end }
            ctl._subView = {
                GetBufID = function() return buf end,
                GetWinID = function() return nil end,
                ClearSyntaxHighlight = function() end,
                ApplySyntaxHighlight = function() end,
            }

            -- Save lines above file B (lines 1-2)
            local lines_before = vim.api.nvim_buf_get_lines(buf, 0, 2, true)

            -- Collapse file B (in the middle)
            ctl:_incrementalToggleFold(uri_b)

            -- Lines above should be unchanged
            local lines_after = vim.api.nvim_buf_get_lines(buf, 0, 2, true)

            return {
                lines_preserved = lines_before[1] == lines_after[1] and lines_before[2] == lines_after[2],
                total_lines = #vim.api.nvim_buf_get_lines(buf, 0, -1, true),
                -- C header should shift from line 5 to line 4
                map_4_uri = ctl._line_map[4] and ctl._line_map[4].uri or "nil",
                map_4_is_header = ctl._line_map[4] and ctl._line_map[4].range == nil,
            }
        ]])

    h.eq(true, result.lines_preserved)
    h.eq(5, result.total_lines) -- 6 - 1 collapsed code line
    h.eq("file:///tmp/c.lua", result.map_4_uri)
    h.eq(true, result.map_4_is_header)
end

return T
