local M = {}

--- @param severity integer
--- @return string
function M.severity_to_highlight(severity)
    local map = {
        [1] = "DiagnosticFloatingError",
        [2] = "DiagnosticFloatingWarn",
        [3] = "DiagnosticFloatingInfo",
        [4] = "DiagnosticFloatingHint",
    }
    return map[severity] or "DiagnosticFloatingError"
end

--- @param str string
--- @return string
function M.clean_string(str)
    return str:match("^%s*(.-)%s*$"):gsub("%.+$", "")
end

--- @param diagnostics vim.Diagnostic[]
--- @return vim.Diagnostic[]
function M.sort_diagnostics(diagnostics)
    local sorted = vim.deepcopy(diagnostics)
    table.sort(sorted, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        if a.col ~= b.col then
            return a.col < b.col
        end
        return a.severity < b.severity
    end)
    return sorted
end

--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer
--- @param cursor_col integer
--- @return integer
function M.find_diagnostic_at_or_after(diagnostics, cursor_row, cursor_col)
    for i, d in ipairs(diagnostics) do
        if d.lnum > cursor_row then
            return i
        elseif d.lnum == cursor_row and d.col >= cursor_col then
            return i
        end
    end
    return 0
end

--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer
--- @param cursor_col integer
--- @return integer
function M.find_diagnostic_at_or_before(diagnostics, cursor_row, cursor_col)
    for i = #diagnostics, 1, -1 do
        local d = diagnostics[i]
        if d.lnum < cursor_row then
            return i
        elseif d.lnum == cursor_row and d.col <= cursor_col then
            return i
        end
    end
    return 0
end

--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer
--- @param cursor_col integer
--- @return integer
function M.find_diagnostic_at_cursor(diagnostics, cursor_row, cursor_col)
    for i, d in ipairs(diagnostics) do
        local end_col = d.end_col or d.col
        if
            d.lnum == cursor_row
            and d.col <= cursor_col
            and end_col >= cursor_col
        then
            return i
        end
    end
    return 0
end

--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer
--- @return integer
function M.find_diagnostic_on_line(diagnostics, cursor_row)
    for i, d in ipairs(diagnostics) do
        if d.lnum == cursor_row then
            return i
        end
    end
    return 0
end

--- @class LspUI_DiagnosticHighlight
--- @field severity integer
--- @field lnum integer
--- @field col integer
--- @field end_col integer

--- @class LspUI_FormatDiagnosticOpts
--- @field show_code boolean?
--- @field show_related_info boolean?

--- @param diagnostic vim.Diagnostic
--- @param opts LspUI_FormatDiagnosticOpts?
--- @return string[], LspUI_DiagnosticHighlight[]
function M.format_diagnostic(diagnostic, opts)
    opts = opts or {}
    local lines = {}
    local highlights = {}

    local messages = vim.split(
        diagnostic.message,
        "[\n;]",
        { plain = false, trimempty = true }
    )
    for i, part in ipairs(messages) do
        messages[i] = vim.trim(part)
    end

    for _, msg in ipairs(messages) do
        if msg ~= "" then
            table.insert(highlights, {
                severity = diagnostic.severity,
                lnum = #lines,
                col = 0,
                end_col = #msg,
            })
            table.insert(lines, msg)
        end
    end

    if opts.show_code and diagnostic.code then
        local code_str = string.format("  [%s]", tostring(diagnostic.code))
        if #lines > 0 then
            local last_line_idx = #lines
            lines[last_line_idx] = lines[last_line_idx] .. code_str
            highlights[#highlights].end_col = #lines[last_line_idx]
        else
            local line = vim.trim(code_str)
            table.insert(lines, line)
            table.insert(highlights, {
                severity = diagnostic.severity,
                lnum = 0,
                col = 0,
                end_col = #line,
            })
        end
    end

    if opts.show_related_info and diagnostic.user_data then
        local lsp_data = diagnostic.user_data.lsp
        local related_info = lsp_data and lsp_data.relatedInformation
        if related_info then
            for _, info in ipairs(related_info) do
                if info.message then
                    local rel_msg =
                        string.format("  -> %s", vim.trim(info.message))
                    table.insert(highlights, {
                        severity = 4,
                        lnum = #lines,
                        col = 0,
                        end_col = #rel_msg,
                    })
                    table.insert(lines, rel_msg)
                end
            end
        end
    end

    if #lines == 0 then
        local fallback = "No diagnostic message"
        table.insert(lines, fallback)
        table.insert(highlights, {
            severity = diagnostic.severity,
            lnum = 0,
            col = 0,
            end_col = #fallback,
        })
    end

    return lines, highlights
end

--- @param lines string[]
--- @param max_width_ratio number
--- @param screen_width integer
--- @return integer, integer
function M.calculate_dimensions(lines, max_width_ratio, screen_width)
    local max_width = 0
    for _, line in ipairs(lines) do
        local line_width = vim.fn.strdisplaywidth(line)
        if line_width > max_width then
            max_width = line_width
        end
    end

    local max_allowed = math.floor(screen_width * max_width_ratio)
    local width = math.min(max_width, max_allowed)

    local height = 0
    for _, line in ipairs(lines) do
        local line_width = vim.fn.strdisplaywidth(line)
        height = height + math.max(1, math.ceil(line_width / width))
    end

    return width, height
end

return M
