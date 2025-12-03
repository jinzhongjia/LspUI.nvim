local api, fn = vim.api, vim.fn
local ClassLsp = require("LspUI.layer.lsp")
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")

--- @alias action_tuple { action: lsp.CodeAction|lsp.Command, client: vim.lsp.Client?, buffer_id: integer, callback: function? }

local M = {}

-- get all valid clients for code action
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    return ClassLsp:GetCodeActionClients(buffer_id)
end

-- make range params
--- @param buffer_id integer
--- @param offset_encoding string
--- @return lsp.CodeActionParams params
--- @return boolean is_visual
function M.get_range_params(buffer_id, offset_encoding)
    local client = { offset_encoding = offset_encoding }
    return ClassLsp:MakeCodeActionParams(buffer_id, client)
end

-- get action tuples
--- @param clients vim.lsp.Client[]
--- @param params table
--- @param buffer_id integer
--- @param is_visual boolean
--- @param callback fun(action_tuples:action_tuple[])
function M.get_action_tuples(clients, params, buffer_id, is_visual, callback)
    local options = {
        is_visual = is_visual,
        skip_registered = false,
        skip_gitsigns = false,
    }

    ClassLsp:RequestCodeActions(buffer_id, params, callback, options)
end

-- choice action tuple
--- @param action_tuple action_tuple
local function choice_action_tuple(action_tuple)
    local success, err = ClassLsp:ExecCodeAction(action_tuple)
    if not success then
        notify.Warn(err)
    end
end

--- @param view ClassView
--- @param action_tuples action_tuple[]
local function keybinding_autocmd(view, action_tuples)
    -- keybind
    view:KeyMap("n", config.options.code_action.key_binding.next, function()
        -- get current line number
        local _, lnum, _, _ = unpack(vim.fn.getpos("."))
        if lnum == #action_tuples then
            ---@diagnostic disable-next-line: param-type-mismatch
            api.nvim_win_set_cursor(view:GetWinID(), { 1, 1 })
            return
        end

        ---@diagnostic disable-next-line: param-type-mismatch
        api.nvim_win_set_cursor(view:GetWinID(), { lnum + 1, 1 })
    end, "go to next action")

    view:KeyMap("n", config.options.code_action.key_binding.prev, function()
        -- get current line number
        local _, lnum, _, _ = unpack(vim.fn.getpos("."))
        if lnum == 1 then
            ---@diagnostic disable-next-line: param-type-mismatch
            api.nvim_win_set_cursor(view:GetWinID(), { #action_tuples, 1 })
            return
        end

        ---@diagnostic disable-next-line: param-type-mismatch
        api.nvim_win_set_cursor(view:GetWinID(), { lnum - 1, 1 })
    end, "go to prev action")

    view:KeyMap("n", config.options.code_action.key_binding.quit, function()
        view:Destroy()
    end, "quit code_action")

    view:KeyMap("n", config.options.code_action.key_binding.exec, function()
        local action_tuple_index = tonumber(fn.expand("<cword>"))
        if action_tuple_index == nil then
            notify.Error(
                string.format(
                    "this plugin occurs an error: %s",
                    "try to convert a non-number to number"
                )
            )
            return
        end
        local action_tuple = action_tuples[action_tuple_index]
        choice_action_tuple(action_tuple)
        view:Destroy()
    end, "execute a code action")

    -- number keys exec action
    for action_tuple_index, action_tuple in ipairs(action_tuples) do
        -- stylua: ignore
        local desc = string.format("exec action with number key [%d]", action_tuple_index)
        view:KeyMap("n", tostring(action_tuple_index), function()
            choice_action_tuple(action_tuple)
            view:Destroy()
        end, desc)
    end

    view:BufAutoCmd("CursorMoved", nil, function()
        local _, lnum, col, _ = unpack(vim.fn.getpos("."))
        if col ~= 2 then
            ---@diagnostic disable-next-line: param-type-mismatch
            api.nvim_win_set_cursor(view:GetWinID(), { lnum, 1 })
        end
    end, "lock the cursor")

    view:BufAutoCmd("WinLeave", nil, function()
        view:Destroy()
    end, "code action auto close window when focus leave")
end

-- render the menu for the code actions
--- @param action_tuples action_tuple[]
function M.render(action_tuples)
    if vim.tbl_isempty(action_tuples) then
        notify.Info("no code action!")
        return
    end

    local contents = {}
    local title = "code_action"
    local max_width = 0

    for index, action_tuple in ipairs(action_tuples) do
        local action_title = ""
        if action_tuple.action.title then
            action_title =
                string.format("[%d] %s", index, action_tuple.action.title)
            --- @type integer
            local action_title_len = fn.strdisplaywidth(action_title)
            max_width = max_width < action_title_len and action_title_len
                or max_width
        end
        table.insert(contents, action_title)
    end

    -- max height should be 10, TODO: maybe this number should be set by user
    local height = #contents > 10 and 10 or #contents

    local view = ClassView
        :New(true)
        :BufContent(0, -1, contents)
        :BufOption("filetype", "LspUI-code_action")
        :BufOption("modifiable", false)
        :BufOption("bufhidden", "wipe")
        :Size(max_width + 1, height)
        :Enter(true)
        :Anchor("NW")
        :Border(config.options.code_action.border)
        :Focusable(true)
        :Relative("cursor")
        :Pos(1, 1)
        :Style("minimal")
        :Title(title, "right")
        -- render
        :Render()
        :Winhl("Normal:Normal")
        :Winbl(config.options.code_action.transparency)

    ---@diagnostic disable-next-line: param-type-mismatch
    keybinding_autocmd(view, action_tuples)
end

return M
