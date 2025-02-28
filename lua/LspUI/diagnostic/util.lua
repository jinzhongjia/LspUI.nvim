local api, fn = vim.api, vim.fn
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")
local M = {}

--- @class LspUI-highlightgroup
--- @field severity 1|2|3|4
--- @field lnum integer
--- @field col integer
--- @field end_col integer

local autocmd_group = "Lspui_diagnostic"

-- convert severity to string
--- @param severity integer
--- @return string?
---@diagnostic disable-next-line: unused-local, unused-function
local function diagnostic_severity_to_string(severity)
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
local function diagnostic_severity_to_highlight(severity)
    local arr = {
        "DiagnosticError",
        "DiagnosticWarn",
        "DiagnosticInfo",
        "DiagnosticHint",
    }
    return arr[severity] or nil
end

local diagnostic_window = -1

-- render the float window
--- @param action "prev"|"next"
function M.render(action)
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

    --- @type vim.Diagnostic|nil
    local diagnostic

    if search_forward then
        diagnostic = vim.diagnostic.get_next()
    else
        diagnostic = vim.diagnostic.get_prev()
    end

    if not diagnostic then
        return
    end

    local next_row = diagnostic.lnum
    local next_col = diagnostic.col

    -- get content
    local content = {}
    local max_width = 0

    --- @type LspUI-highlightgroup[]
    local highlight_groups = {}

    local messages = vim.split(diagnostic.message, "\n")

    for _, message in pairs(messages) do
        --- @type string
        local msg = string.format("%s", message)
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
                col = 0,
                end_col = -1,
            }
        )
        table.insert(content, msg)
    end

    -- create a new buffer
    local new_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(new_buffer, 0, -1, false, content)
    -- stylua: ignore
    api.nvim_set_option_value("filetype", "LspUI-diagnostic", { buf = new_buffer })
    api.nvim_set_option_value("modifiable", false, { buf = new_buffer })
    api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buffer })

    -- highlight buffer
    for _, highlight_group in pairs(highlight_groups) do
        api.nvim_buf_add_highlight(
            new_buffer,
            -1,
            --- @type string
            diagnostic_severity_to_highlight(highlight_group.severity),
            highlight_group.lnum,
            highlight_group.col,
            highlight_group.end_col
        )
    end

    local width =
        math.min(max_width, math.floor(lib_windows.get_max_width() * 0.6))

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

    -- try to cloase the old window
    lib_windows.close_window(diagnostic_window)
    diagnostic_window = lib_windows.display_window(new_window_wrap)

    -- stylua: ignore
    api.nvim_set_option_value("winhighlight", "Normal:Normal", { win = diagnostic_window })
    api.nvim_set_option_value("wrap", true, { win = diagnostic_window })
    -- this is very very important, because it will hide highlight group
    api.nvim_set_option_value("conceallevel", 2, { win = diagnostic_window })
    api.nvim_set_option_value("concealcursor", "n", { win = diagnostic_window })
    -- stylua: ignore
    api.nvim_set_option_value("winblend", config.options.diagnostic.transparency, { win = diagnostic_window })

    -- Forced delay of autocmd mounting
    vim.schedule(function()
        M.autocmd(current_buffer, new_buffer, diagnostic_window)
    end)
end

-- autocmd for diagnostic
--- @param buffer_id integer original buffer id, not float window's buffer id
--- @param new_buffer integer new buffer id
--- @param window_id integer new window id
function M.autocmd(buffer_id, new_buffer, window_id)
    local group = api.nvim_create_augroup(autocmd_group, { clear = true })
    api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            if current_buffer == new_buffer then
                return
            end
            lib_windows.close_window(window_id)
            api.nvim_del_augroup_by_name(autocmd_group)
        end,
    })
    api.nvim_create_autocmd(
        { "CursorMoved", "CursorMovedI", "InsertCharPre" },
        {
            buffer = buffer_id,
            group = autocmd_group,
            callback = function()
                lib_windows.close_window(window_id)
                api.nvim_del_augroup_by_name(autocmd_group)
            end,
            desc = lib_util.command_desc("diagnostic, auto close windows"),
        }
    )
end

return M
