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

T["severity_to_highlight"] = new_set()

T["severity_to_highlight"]["returns error highlight for severity 1"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.severity_to_highlight(1)
    ]])
    h.eq("DiagnosticFloatingError", result)
end

T["severity_to_highlight"]["returns warn highlight for severity 2"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.severity_to_highlight(2)
    ]])
    h.eq("DiagnosticFloatingWarn", result)
end

T["severity_to_highlight"]["returns info highlight for severity 3"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.severity_to_highlight(3)
    ]])
    h.eq("DiagnosticFloatingInfo", result)
end

T["severity_to_highlight"]["returns hint highlight for severity 4"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.severity_to_highlight(4)
    ]])
    h.eq("DiagnosticFloatingHint", result)
end

T["severity_to_highlight"]["returns error highlight for invalid severity"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return {
            nil_val = diag.severity_to_highlight(nil),
            zero = diag.severity_to_highlight(0),
            five = diag.severity_to_highlight(5),
        }
    ]])
    h.eq("DiagnosticFloatingError", result.nil_val)
    h.eq("DiagnosticFloatingError", result.zero)
    h.eq("DiagnosticFloatingError", result.five)
end

T["clean_string"] = new_set()

T["clean_string"]["trims whitespace"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.clean_string("  hello world  ")
    ]])
    h.eq("hello world", result)
end

T["clean_string"]["removes trailing dots"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.clean_string("error message...")
    ]])
    h.eq("error message", result)
end

T["clean_string"]["handles mixed whitespace and dots"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        return diag.clean_string("  warning..  ")
    ]])
    h.eq("warning", result)
end

T["sort_diagnostics"] = new_set()

T["sort_diagnostics"]["sorts by line number"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local input = {
            { lnum = 10, col = 0, severity = 1 },
            { lnum = 5, col = 0, severity = 1 },
            { lnum = 15, col = 0, severity = 1 },
        }
        local sorted = diag.sort_diagnostics(input)
        return { sorted[1].lnum, sorted[2].lnum, sorted[3].lnum }
    ]])
    h.eq(5, result[1])
    h.eq(10, result[2])
    h.eq(15, result[3])
end

T["sort_diagnostics"]["sorts by column when lines are equal"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local input = {
            { lnum = 5, col = 20, severity = 1 },
            { lnum = 5, col = 5, severity = 1 },
            { lnum = 5, col = 10, severity = 1 },
        }
        local sorted = diag.sort_diagnostics(input)
        return { sorted[1].col, sorted[2].col, sorted[3].col }
    ]])
    h.eq(5, result[1])
    h.eq(10, result[2])
    h.eq(20, result[3])
end

T["sort_diagnostics"]["sorts by severity when position is equal"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local input = {
            { lnum = 5, col = 10, severity = 3 },
            { lnum = 5, col = 10, severity = 1 },
            { lnum = 5, col = 10, severity = 2 },
        }
        local sorted = diag.sort_diagnostics(input)
        return { sorted[1].severity, sorted[2].severity, sorted[3].severity }
    ]])
    h.eq(1, result[1])
    h.eq(2, result[2])
    h.eq(3, result[3])
end

T["sort_diagnostics"]["does not modify original array"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local input = {
            { lnum = 10, col = 0, severity = 1 },
            { lnum = 5, col = 0, severity = 1 },
        }
        diag.sort_diagnostics(input)
        return input[1].lnum
    ]])
    h.eq(10, result)
end

T["find_diagnostic_at_or_after"] = new_set()

T["find_diagnostic_at_or_after"]["finds diagnostic after cursor"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 0 },
            { lnum = 10, col = 5 },
            { lnum = 15, col = 0 },
        }
        return diag.find_diagnostic_at_or_after(diagnostics, 7, 0)
    ]])
    h.eq(2, result)
end

T["find_diagnostic_at_or_after"]["finds diagnostic at cursor position"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 10 },
            { lnum = 10, col = 5 },
        }
        return diag.find_diagnostic_at_or_after(diagnostics, 5, 10)
    ]])
    h.eq(1, result)
end

T["find_diagnostic_at_or_after"]["returns 0 when no match"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 0 },
            { lnum = 10, col = 0 },
        }
        return diag.find_diagnostic_at_or_after(diagnostics, 15, 0)
    ]])
    h.eq(0, result)
end

T["find_diagnostic_at_or_before"] = new_set()

T["find_diagnostic_at_or_before"]["finds diagnostic before cursor"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 0 },
            { lnum = 10, col = 5 },
            { lnum = 15, col = 0 },
        }
        return diag.find_diagnostic_at_or_before(diagnostics, 12, 0)
    ]])
    h.eq(2, result)
end

T["find_diagnostic_at_or_before"]["finds diagnostic at cursor position"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 10 },
            { lnum = 10, col = 5 },
        }
        return diag.find_diagnostic_at_or_before(diagnostics, 10, 5)
    ]])
    h.eq(2, result)
end

T["find_diagnostic_at_or_before"]["returns 0 when no match"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 10, col = 0 },
            { lnum = 15, col = 0 },
        }
        return diag.find_diagnostic_at_or_before(diagnostics, 5, 0)
    ]])
    h.eq(0, result)
end

T["find_diagnostic_at_cursor"] = new_set()

T["find_diagnostic_at_cursor"]["finds diagnostic containing cursor"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 10, end_col = 20 },
            { lnum = 10, col = 5, end_col = 15 },
        }
        return diag.find_diagnostic_at_cursor(diagnostics, 5, 15)
    ]])
    h.eq(1, result)
end

T["find_diagnostic_at_cursor"]["returns 0 when cursor not in any diagnostic"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 10, end_col = 20 },
        }
        return diag.find_diagnostic_at_cursor(diagnostics, 5, 25)
    ]])
    h.eq(0, result)
end

T["find_diagnostic_at_cursor"]["uses col as end_col when end_col is nil"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 10 },
        }
        return diag.find_diagnostic_at_cursor(diagnostics, 5, 10)
    ]])
    h.eq(1, result)
end

T["find_diagnostic_on_line"] = new_set()

T["find_diagnostic_on_line"]["finds first diagnostic on line"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 20 },
            { lnum = 10, col = 5 },
            { lnum = 10, col = 15 },
        }
        return diag.find_diagnostic_on_line(diagnostics, 10)
    ]])
    h.eq(2, result)
end

T["find_diagnostic_on_line"]["returns 0 when no diagnostic on line"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostics = {
            { lnum = 5, col = 0 },
            { lnum = 15, col = 0 },
        }
        return diag.find_diagnostic_on_line(diagnostics, 10)
    ]])
    h.eq(0, result)
end

T["format_diagnostic"] = new_set()

T["format_diagnostic"]["formats simple message"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "undefined variable 'x'",
            severity = 1,
        }
        local lines, highlights = diag.format_diagnostic(diagnostic, {})
        return {
            lines = lines,
            highlight_count = #highlights,
            first_hl_severity = highlights[1].severity,
        }
    ]])
    h.eq(1, #result.lines)
    h.eq("undefined variable 'x'", result.lines[1])
    h.eq(1, result.highlight_count)
    h.eq(1, result.first_hl_severity)
end

T["format_diagnostic"]["splits message by newlines"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "error line 1\nerror line 2",
            severity = 2,
        }
        local lines, _ = diag.format_diagnostic(diagnostic, {})
        return lines
    ]])
    h.eq(2, #result)
    h.eq("error line 1", result[1])
    h.eq("error line 2", result[2])
end

T["format_diagnostic"]["splits message by semicolons"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "error 1; error 2",
            severity = 1,
        }
        local lines, _ = diag.format_diagnostic(diagnostic, {})
        return lines
    ]])
    h.eq(2, #result)
    h.eq("error 1", result[1])
    h.eq("error 2", result[2])
end

T["format_diagnostic"]["appends code when show_code is true"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "error message",
            severity = 1,
            code = "E001",
        }
        local lines, _ = diag.format_diagnostic(diagnostic, { show_code = true })
        return lines[1]
    ]])
    h.expect_match("[E001]", result)
end

T["format_diagnostic"]["handles empty message with code"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "",
            severity = 1,
            code = "E001",
        }
        local lines, _ = diag.format_diagnostic(diagnostic, { show_code = true })
        return lines[1]
    ]])
    h.expect_match("E001", result)
end

T["format_diagnostic"]["returns fallback for empty diagnostic"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local diagnostic = {
            message = "",
            severity = 1,
        }
        local lines, _ = diag.format_diagnostic(diagnostic, {})
        return lines[1]
    ]])
    h.eq("No diagnostic message", result)
end

T["calculate_dimensions"] = new_set()

T["calculate_dimensions"]["calculates width correctly"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local lines = { "short", "a longer line here" }
        local width, _ = diag.calculate_dimensions(lines, 0.8, 100)
        return width
    ]])
    h.eq(18, result)
end

T["calculate_dimensions"]["respects max_width_ratio"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local lines = { string.rep("a", 100) }
        local width, _ = diag.calculate_dimensions(lines, 0.5, 100)
        return width
    ]])
    h.eq(50, result)
end

T["calculate_dimensions"]["calculates height with wrapping"] = function()
    local result = child.lua([[
        local diag = require("LspUI.lib.diagnostic")
        local lines = { string.rep("a", 100) }
        local _, height = diag.calculate_dimensions(lines, 0.5, 100)
        return height
    ]])
    h.eq(2, result)
end

return T
