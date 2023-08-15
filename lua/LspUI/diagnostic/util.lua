local api, fn = vim.api, vim.fn
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")
local M = {}

--- @class LspUI-highlightgroup
--- @field severity 1|2|3|4
--- @field lnum integer
--- @field col integer
--- @field end_col integer

-- convert severity to string
--- @param severity integer
--- @return string?
---@diagnostic disable-next-line: unused-local, unused-function
local diagnostic_severity_to_string = function(severity)
    local arr = {
        "Error",
        "Warn",
        "Info",
        "Hint",
    }
    return arr[severity] or nil
end

-- convert severity to highlight
--- @param severity integer
--- @return string
local diagnostic_severity_to_hightlight = function(severity)
    local arr = {
        "DiagnosticError",
        "DiagnosticWarn",
        "DiagnosticInfo",
        "DiagnosticHint",
    }
    return arr[severity] or nil
end

--- @param diagnostics Diagnostic[]
--- @return Diagnostic[][][]
local sort_diagnostics = function(diagnostics)
    local sorted_diagnostics = {}

    for _, diagnostic in pairs(diagnostics) do
        --- @type Diagnostic[][]?
        local lnum_diagnostics = sorted_diagnostics[diagnostic.lnum]
        if lnum_diagnostics == nil then
            lnum_diagnostics = {}
            lnum_diagnostics[diagnostic.col] = { diagnostic }
            sorted_diagnostics[diagnostic.lnum] = lnum_diagnostics
            goto continue
        end
        local col_diagnostics = lnum_diagnostics[diagnostic.col]
        if col_diagnostics == nil then
            lnum_diagnostics[diagnostic.col] = { diagnostic }
            goto continue
        end
        table.insert(col_diagnostics, diagnostic)
        ::continue::
    end
    return sorted_diagnostics
end

-- get next position diagnostics
--- @param sorted_diagnostics Diagnostic[][][]
--- @param row integer (row,col) is a tuple, get from `nvim_win_get_cursor`, 1 based
--- @param col integer (row,col) is a tuple, get from `nvim_win_get_cursor`, 0 based
--- @param search_forward boolean true is down, false is up
--- @param buffer_id integer
--- @return Diagnostic[]?
local next_position_diagnostics = function(sorted_diagnostics, row, col, search_forward, buffer_id)
    row = row - 1
    local buffer_lines = api.nvim_buf_line_count(buffer_id)
    for i = 0, buffer_lines do
        local offset = i * (search_forward and 1 or -1)
        local lnum = row + offset
        if lnum < 0 or lnum >= buffer_lines then
            lnum = (lnum + buffer_lines) % buffer_lines
        end
        local lnum_diagnostics = sorted_diagnostics[lnum]
        if lnum_diagnostics and not vim.tbl_isempty(lnum_diagnostics) then
            local line_length = #api.nvim_buf_get_lines(buffer_id, lnum, lnum + 1, true)[1]
            if search_forward then
                -- note: Since the lsp protocol stipulates that col starts from 0, so we should use line_length-1, but rust-analyzer
                -- ```rust
                -- dd
                -- fn main() {
                --     println!("Hello, world!");
                -- }
                -- ````
                -- it will return diagnostic position is row=0,col=2,but it should be row=0,col= (0 or 1)?
                --
                -- Why not raise an issue with rust-analyzer?
                -- that's too much trouble... 0.0
                for current_col = 0, line_length do
                    local col_diagnostics = lnum_diagnostics[current_col]
                    if col_diagnostics ~= nil then
                        if offset ~= 0 then
                            return col_diagnostics
                        end
                        if math.min(current_col, line_length - 1) > col then
                            return col_diagnostics
                        end
                    end
                end
            else
                for current_col = line_length, 0, -1 do
                    local col_diagnostics = lnum_diagnostics[current_col]
                    if col_diagnostics ~= nil then
                        if offset ~= 0 then
                            return col_diagnostics
                        end
                        if math.min(current_col, line_length - 1) < col then
                            return col_diagnostics
                        end
                    end
                end
            end
        end
    end
end

-- render the float window
--- @param action "prev"|"next"
M.render = function(action)
    --- @type boolean
    local search_forward
    if action == "prev" then
        search_forward = false
    elseif action == "next" then
        search_forward = true
    else
        lib_notify.Warn(string.format("diagnostic, unknown action %s", action))
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()
    -- get current window
    local current_window = api.nvim_get_current_win()
    -- get current buffer's diagnostics
    local diagnostics = vim.diagnostic.get(current_buffer)
    if diagnostics == nil then
        return
    end
    local sorted_diagnostics = sort_diagnostics(diagnostics)
    -- get cursor position
    local position = api.nvim_win_get_cursor(0)
    local row = position[1]
    local col = position[2]

    local next_diagnostics = next_position_diagnostics(sorted_diagnostics, row, col, search_forward, current_buffer)
    if next_diagnostics == nil then
        return
    end

    local next_row = next_diagnostics[1].lnum
    local next_col = next_diagnostics[1].col

    -- local severities = {}
    -- get content
    local content = {}
    local max_width = 0
    --- @type LspUI-highlightgroup[]
    local highlight_groups = {}
    for diagnostic_index, diagnostic in pairs(next_diagnostics) do
        -- table.insert(severities, diagnostic_severity_to_string(diagnostic.severity))
        local messages = vim.split(diagnostic.message, "\n")
        for index, message in pairs(messages) do
            --- @type string
            local msg
            if index == 1 then
                if #next_diagnostics == 1 then
                    msg = string.format("%s", message)
                else
                    msg = string.format("%d. %s", diagnostic_index, message)
                end
            else
                if #next_diagnostics == 1 then
                    msg = string.format("%s", message)
                else
                    msg = string.format("   %s", message)
                end
            end
            local msg_len = fn.strdisplaywidth(msg)
            if msg_len > max_width then
                max_width = msg_len
            end
            table.insert(
                highlight_groups,
                --- @type LspUI-highlightgroup
                {
                    severity = diagnostic.severity,
                    lnum = #content,
                    col = #next_diagnostics == 1 and 0 or 3,
                    end_col = -1,
                }
            )
            table.insert(content, msg)
        end
    end

    -- create a new buffer
    local new_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(new_buffer, 0, -1, false, content)
    api.nvim_buf_set_option(new_buffer, "filetype", "LspUI-diagnostic")
    api.nvim_buf_set_option(new_buffer, "modifiable", false)
    api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

    -- highlight buffer
    for _, highlight_group in pairs(highlight_groups) do
        api.nvim_buf_add_highlight(
            new_buffer,
            -1,
            --- @type string
            diagnostic_severity_to_hightlight(highlight_group.severity),
            highlight_group.lnum,
            highlight_group.col,
            highlight_group.end_col
        )
    end

    -- TODO:whether this can be set by user?
    local width = math.min(max_width, math.floor(lib_windows.get_max_width() * 0.6))

    local height = lib_windows.compute_height_for_windows(content, width)

    local new_window_wrap = lib_windows.new_window(new_buffer)

    lib_windows.set_width_window(new_window_wrap, width)
    -- lib_windows.set_height_window(new_window_wrap, #content)
    lib_windows.set_height_window(new_window_wrap, height)
    lib_windows.set_enter_window(new_window_wrap, false)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_focusable_window(new_window_wrap, true)
    lib_windows.set_relative_window(new_window_wrap, "cursor")
    lib_windows.set_col_window(new_window_wrap, 1)
    lib_windows.set_row_window(new_window_wrap, 1)
    lib_windows.set_style_window(new_window_wrap, "minimal")
    lib_windows.set_right_title_window(new_window_wrap, "diagnostic")

    api.nvim_win_set_cursor(current_window, { next_row + 1, next_col })
    local window_id = lib_windows.display_window(new_window_wrap)

    api.nvim_win_set_option(window_id, "winhighlight", "Normal:Normal")
    api.nvim_win_set_option(window_id, "wrap", true)

    -- this is very very important, because it will hide highlight group
    api.nvim_win_set_option(window_id, "conceallevel", 2)
    api.nvim_win_set_option(window_id, "concealcursor", "n")

    vim.schedule(function()
        M.autocmd(current_buffer, window_id)
    end)
end

-- autocmd for diagnostic
--- @param buffer_id integer original buffer id, not float window's buffer id
--- @param window_id integer float window's id
M.autocmd = function(buffer_id, window_id)
    api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
        buffer = buffer_id,
        callback = function(arg)
            lib_windows.close_window(window_id)
            api.nvim_del_autocmd(arg.id)
        end,
        desc = lib_util.command_desc("diagnostic, auto close windows"),
    })
end

return M
