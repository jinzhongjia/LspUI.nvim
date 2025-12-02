local api, fn = vim.api, vim.fn
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

local M = {}

--- @class LspUI_diagnostic_highlight
--- @field severity integer
--- @field lnum integer
--- @field col integer
--- @field end_col integer

local autocmd_group = "Lspui_diagnostic"
local ns_id = api.nvim_create_namespace("LspUI-diagnostic")

-- Convert severity to floating highlight group
--- @param severity integer
--- @return string
local function severity_to_floating_highlight(severity)
    local arr = {
        "DiagnosticFloatingError",
        "DiagnosticFloatingWarn",
        "DiagnosticFloatingInfo",
        "DiagnosticFloatingHint",
    }
    return arr[severity] or "DiagnosticFloatingError"
end

--- @type ClassView|nil
local diagnostic_view

--- All diagnostics in current buffer (sorted by position)
--- @type vim.Diagnostic[]
local all_diagnostics = {}

--- Current diagnostic index (1-based)
--- @type integer
local current_index = 0

--- Current buffer id
--- @type integer
local current_buffer = 0

local function ensure_diagnostic_view()
    if diagnostic_view and diagnostic_view:Valid() then
        return diagnostic_view, false
    end

    diagnostic_view = ClassView:New(true)
    return diagnostic_view, true
end

local function clean_string(str)
    return str:match("^%s*(.-)%s*$"):gsub("%.+$", "")
end

local function clean_autocmds()
    pcall(api.nvim_del_augroup_by_name, autocmd_group)
end

--- Get all diagnostics for the buffer, sorted by position and severity
--- @param bufnr integer
--- @param severity_filter? table
--- @return vim.Diagnostic[]
local function get_all_diagnostics(bufnr, severity_filter)
    local diagnostics = vim.diagnostic.get(bufnr, {
        severity = severity_filter,
    })

    -- Sort by position (lnum, col) then by severity
    table.sort(diagnostics, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        if a.col ~= b.col then
            return a.col < b.col
        end
        return a.severity < b.severity
    end)

    return diagnostics
end

--- Find the index of diagnostic at or after cursor position
--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer 0-indexed
--- @param cursor_col integer 0-indexed
--- @return integer index (1-based), 0 if not found
local function find_diagnostic_at_or_after_cursor(diagnostics, cursor_row, cursor_col)
    for i, d in ipairs(diagnostics) do
        if d.lnum > cursor_row then
            return i
        elseif d.lnum == cursor_row and d.col >= cursor_col then
            return i
        end
    end
    return 0
end

--- Find the index of diagnostic at or before cursor position
--- @param diagnostics vim.Diagnostic[]
--- @param cursor_row integer 0-indexed
--- @param cursor_col integer 0-indexed
--- @return integer index (1-based), 0 if not found
local function find_diagnostic_at_or_before_cursor(diagnostics, cursor_row, cursor_col)
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

--- Format a single diagnostic for display
--- @param diagnostic vim.Diagnostic
--- @param opts table
--- @return string[], LspUI_diagnostic_highlight[]
local function format_diagnostic(diagnostic, opts)
    local lines = {}
    local highlights = {}

    -- Split message by newlines and semicolons
    local messages =
        vim.split(diagnostic.message, "[\n;]", { plain = false, trimempty = true })
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

    -- Add diagnostic code if available and configured
    if opts.show_code and diagnostic.code then
        local code_str = string.format("  [%s]", tostring(diagnostic.code))
        if #highlights > 0 then
            local last_hl_idx = #highlights
            local last_line_idx = #lines
            lines[last_line_idx] = lines[last_line_idx] .. code_str
            highlights[last_hl_idx].end_col = #lines[last_line_idx]
        end
    end

    -- Add related information if available (stored in user_data by LSP)
    if opts.show_related_info and diagnostic.user_data then
        local lsp_data = diagnostic.user_data.lsp
        local related_info = lsp_data and lsp_data.relatedInformation
        if related_info then
            for _, info in ipairs(related_info) do
                if info.message then
                    local rel_msg = string.format("  → %s", vim.trim(info.message))
                    table.insert(highlights, {
                        severity = vim.diagnostic.severity.HINT,
                        lnum = #lines,
                        col = 0,
                        end_col = #rel_msg,
                    })
                    table.insert(lines, rel_msg)
                end
            end
        end
    end

    return lines, highlights
end

--- Render a diagnostic in the float window
--- @param diagnostic vim.Diagnostic
--- @param index integer
--- @param total integer
--- @param opts table
--- @return ClassView|nil, boolean|nil
local function render_diagnostic(diagnostic, index, total, opts)
    local view, is_new = ensure_diagnostic_view()
    local buf_id = view:GetBufID()

    if not buf_id then
        notify.Warn("diagnostic: failed to get buffer id")
        return nil, nil
    end

    local lines, highlights = format_diagnostic(diagnostic, opts)

    -- Calculate max width
    local max_width = 0
    for _, line in ipairs(lines) do
        max_width = math.max(max_width, fn.strdisplaywidth(line))
    end

    local max_allowed_width = math.floor(tools.get_max_width() * opts.max_width)
    local width = math.min(max_width, max_allowed_width)

    -- Add source info to footer
    local footer = ""
    if opts.show_source and diagnostic.source then
        footer = clean_string(diagnostic.source)
        local footer_width = fn.strdisplaywidth(footer) + 4
        if footer_width > width then
            width = math.min(footer_width, max_allowed_width)
        end
    end

    -- Clear and set buffer content
    api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

    view:BufOption("modifiable", true)
        :BufOption("bufhidden", "wipe")
        :BufOption("filetype", "LspUI-diagnostic")

    api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    view:BufOption("modifiable", false)

    -- Apply highlights
    for _, hl in ipairs(highlights) do
        local hl_group = severity_to_floating_highlight(hl.severity)
        vim.hl.range(buf_id, ns_id, hl_group, { hl.lnum, hl.col }, { hl.lnum, hl.end_col })
    end

    local height = tools.compute_height_for_windows(lines, width)

    view:Updates(function()
        view:Size(width, height)
            :Enter(false)
            :Anchor("NW")
            :Border(config.options.diagnostic.border)
            :Focusable(true)
            :Relative("cursor")
            :Pos(1, 1)
            :Style("minimal")
    end)

    -- Set title
    if total > 1 then
        view:Title(string.format("diagnostic [%d/%d]", index, total), "right")
    else
        view:Title("diagnostic", "right")
    end

    -- Set footer with source
    if footer ~= "" then
        view:Footer(footer, "right")
    else
        view:Footer("", "right")
    end

    return view, is_new
end

--- Get config options
--- @return table
local function get_opts()
    return {
        show_source = config.options.diagnostic.show_source,
        show_code = config.options.diagnostic.show_code,
        show_related_info = config.options.diagnostic.show_related_info,
        max_width = config.options.diagnostic.max_width,
        severity = config.options.diagnostic.severity,
    }
end

--- Refresh diagnostics list for current buffer
local function refresh_diagnostics()
    local bufnr = api.nvim_get_current_buf()
    local opts = get_opts()

    if bufnr ~= current_buffer then
        current_buffer = bufnr
        all_diagnostics = get_all_diagnostics(bufnr, opts.severity)
        current_index = 0
    else
        all_diagnostics = get_all_diagnostics(bufnr, opts.severity)
        if current_index > #all_diagnostics then
            current_index = #all_diagnostics
        end
    end
end

--- Jump cursor to diagnostic position
--- @param diagnostic vim.Diagnostic
local function jump_to_diagnostic(diagnostic)
    local win = api.nvim_get_current_win()
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(win, { diagnostic.lnum + 1, diagnostic.col })
    vim.cmd("normal! m'")
end

--- Show and render diagnostic window
--- @param diagnostic vim.Diagnostic
--- @param index integer
--- @param total integer
local function show_diagnostic_window(diagnostic, index, total)
    local opts = get_opts()
    local view, is_new = render_diagnostic(diagnostic, index, total, opts)

    if not view then
        return
    end

    if is_new then
        view:Render()
    else
        view:ShowView()
    end

    vim.cmd.redraw()
    diagnostic_view = view

    view:Winhl("Normal:Normal")
        :Winbl(config.options.diagnostic.transparency)
        :Option("wrap", true)
        :Option("conceallevel", 2)
        :Option("concealcursor", "n")

    vim.schedule(function()
        M.autocmd(current_buffer)
    end)
end

--- Show diagnostic at current cursor position
function M.show()
    refresh_diagnostics()

    if #all_diagnostics == 0 then
        notify.Info("No diagnostics in current buffer")
        return
    end

    local cursor = api.nvim_win_get_cursor(0)
    local cursor_row = cursor[1] - 1
    local cursor_col = cursor[2]

    -- Find diagnostic at cursor position
    local found_index = 0
    for i, d in ipairs(all_diagnostics) do
        -- Check if cursor is within diagnostic range
        local end_col = d.end_col or d.col
        if d.lnum == cursor_row and d.col <= cursor_col and end_col >= cursor_col then
            found_index = i
            break
        end
    end

    -- If no diagnostic at cursor, find nearest on same line
    if found_index == 0 then
        for i, d in ipairs(all_diagnostics) do
            if d.lnum == cursor_row then
                found_index = i
                break
            end
        end
    end

    if found_index == 0 then
        notify.Info("No diagnostics at current position")
        return
    end

    current_index = found_index
    clean_autocmds()

    show_diagnostic_window(all_diagnostics[current_index], current_index, #all_diagnostics)
end

--- Jump to next/prev diagnostic and show float window
--- @param action "prev"|"next"
function M.render(action)
    if action ~= "next" and action ~= "prev" then
        notify.Warn(string.format("diagnostic: unknown action '%s'", action))
        return
    end

    refresh_diagnostics()

    if #all_diagnostics == 0 then
        notify.Info("No diagnostics in current buffer")
        return
    end

    clean_autocmds()

    -- If we have a valid current_index, use it for cycling
    -- Otherwise, find starting position based on cursor
    if current_index >= 1 and current_index <= #all_diagnostics then
        -- Cycle from current index
        if action == "next" then
            current_index = current_index + 1
            if current_index > #all_diagnostics then
                current_index = 1
            end
        else
            current_index = current_index - 1
            if current_index < 1 then
                current_index = #all_diagnostics
            end
        end
    else
        -- First time: find based on cursor position
        local cursor = api.nvim_win_get_cursor(0)
        local cursor_row = cursor[1] - 1
        local cursor_col = cursor[2]

        if action == "next" then
            local next_index = find_diagnostic_at_or_after_cursor(all_diagnostics, cursor_row, cursor_col)
            if next_index == 0 then
                next_index = 1
            end
            current_index = next_index
        else
            local prev_index = find_diagnostic_at_or_before_cursor(all_diagnostics, cursor_row, cursor_col)
            if prev_index == 0 then
                prev_index = #all_diagnostics
            end
            current_index = prev_index
        end
    end

    local diagnostic = all_diagnostics[current_index]
    jump_to_diagnostic(diagnostic)
    show_diagnostic_window(diagnostic, current_index, #all_diagnostics)
end

--- Set up autocmds for auto-closing the diagnostic window
--- @param buffer_id integer original buffer id
function M.autocmd(buffer_id)
    clean_autocmds()

    if not (diagnostic_view and diagnostic_view:Valid()) then
        return
    end

    local group = api.nvim_create_augroup(autocmd_group, { clear = true })
    local float_buffer = diagnostic_view:GetBufID()
    local win_id = diagnostic_view:GetWinID()

    api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function()
            local cur_buf = api.nvim_get_current_buf()
            if cur_buf == float_buffer then
                return
            end
            if diagnostic_view and diagnostic_view:GetWinID() == win_id then
                diagnostic_view:Destroy()
            end
            current_index = 0
            clean_autocmds()
        end,
    })

    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
        buffer = buffer_id,
        group = group,
        callback = function()
            if diagnostic_view and diagnostic_view:GetWinID() == win_id then
                diagnostic_view:Destroy()
            end
            current_index = 0
            clean_autocmds()
        end,
        desc = tools.command_desc("diagnostic, auto close windows"),
    })

    -- Reset when diagnostics change
    api.nvim_create_autocmd("DiagnosticChanged", {
        buffer = buffer_id,
        group = group,
        callback = function()
            current_buffer = 0
            current_index = 0
        end,
        desc = tools.command_desc("diagnostic, refresh on change"),
    })
end

return M
