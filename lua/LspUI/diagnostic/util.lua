local api, fn = vim.api, vim.fn
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")
local M = {}

--- @class LspUI-highlightgroup
--- @field severity 1|2|3|4
--- @field lnum integer
--- @field col integer
--- @field end_col integer

local autocmd_group = "Lspui_diagnostic"
local ns_id = vim.api.nvim_create_namespace("LspUI-diagnostic")

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

--- @type ClassView
local diagnostic_view

local function cleanStringConcise(str)
    return str:match("^%s*(.-)%s*$"):gsub("%.+$", "")
end

-- render the float window
--- @param action "prev"|"next"
function M.render(action)
    --- @type boolean
    local search_forward = action == "next"
    if not (action == "next" or action == "prev") then
        notify.Warn(string.format("diagnostic, unknown action %s", action))
        return
    end
    -- get current buffer
    local current_buffer = api.nvim_get_current_buf()
    -- get current window
    local current_window = api.nvim_get_current_win()

    --- @type vim.Diagnostic|nil
    local diagnostic

    local count = search_forward and 1 or -1
    diagnostic = vim.diagnostic.jump({ count = count })

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

    -- local messages = vim.split(diagnostic.message, "\n")
    -- stylua: ignore
    local messages = vim.split(diagnostic.message, "[\n;]", { plain = false, trimempty = false })
    for i, part in ipairs(messages) do
        messages[i] = vim.trim(part)
    end

    for _, message in pairs(messages) do
        --- @type string
        local msg = message
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
                end_col = msg_len,
            }
        )
        table.insert(content, msg)
    end

    local width =
        math.min(max_width, math.floor(tools.get_max_width() * 0.6))

    if diagnostic.source then
        local msg =
            string.format("        %s", cleanStringConcise(diagnostic.source))
        local len = fn.strdisplaywidth(msg)
        if len > width then
            width = math.min(len, math.floor(tools.get_max_width() * 0.6))
        end
    end

    local view = ClassView:New(true)
        :BufContent(0, -1, content)
        :BufOption("filetype", "LspUI-diagnostic")
        :BufOption("modifiable", false)
        :BufOption("bufhidden", "wipe")

    -- highlight buffer
    for _, highlight_group in pairs(highlight_groups) do
        vim.hl.range(
            ---@diagnostic disable-next-line: param-type-mismatch
            view:GetBufID(),
            ns_id,
            diagnostic_severity_to_highlight(highlight_group.severity),
            { highlight_group.lnum, highlight_group.col },
            { highlight_group.lnum, highlight_group.end_col }
        )
    end

    local height = tools.compute_height_for_windows(content, width)

    view:Size(width, height)
        :Enter(false)
        :Anchor("NW")
        :Border("rounded")
        :Focusable(true)
        :Relative("cursor")
        :Pos(1, 1)
        :Style("minimal")
        :Title("diagnostic", "right")

    if diagnostic.source then
        view:Footer(cleanStringConcise(diagnostic.source), "right")
    end

    if diagnostic_view then
        diagnostic_view:Destroy()
    end

    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(current_window, { next_row + 1, next_col })
    vim.cmd("normal! m'")

    view:Render()

    vim.cmd.redraw()
    diagnostic_view = view

    view:Winhl("Normal:Normal")
        :Winbl(config.options.diagnostic.transparency)
        :Option("wrap", true)
        :Option("conceallevel", 2)
        :Option("concealcursor", "n")

    -- Forced delay of autocmd mounting
    vim.schedule(function()
        M.autocmd(current_buffer)
    end)
end

-- autocmd for diagnostic
--- @param buffer_id integer original buffer id, not float window's buffer id
function M.autocmd(buffer_id)
    local group = api.nvim_create_augroup(autocmd_group, { clear = true })
    local new_buffer = diagnostic_view:GetBufID()
    local win_id = diagnostic_view:GetWinID()
    api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            if current_buffer == new_buffer then
                return
            end
            diagnostic_view:Destroy()
            api.nvim_del_augroup_by_name(autocmd_group)
        end,
    })
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
        buffer = buffer_id,
        group = autocmd_group,
        callback = function()
            -- 只有当前的 diagnostic view的window id 没变，才会触发关闭操作
            if diagnostic_view and diagnostic_view:GetWinID() == win_id then
                diagnostic_view:Destroy()
            end
            api.nvim_del_augroup_by_name(autocmd_group)
        end,
        desc = tools.command_desc("diagnostic, auto close windows"),
    })
end

return M
