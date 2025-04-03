local lsp, api, fn = vim.lsp, vim.api, vim.fn
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction
local exec_command_feature = lsp.protocol.Methods.workspace_executeCommand
local code_action_resolve_feature = lsp.protocol.Methods.codeAction_resolve

local config = require("LspUI.config")
local layer = require("LspUI.layer")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local register = require("LspUI.code_action.register")

--- @alias action_tuple { action: lsp.CodeAction|lsp.Command, client: vim.lsp.Client?, buffer_id: integer, callback: function? }

local M = {}

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = code_action_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- make range params
--- @param buffer_id integer
--- @param offset_encoding string
--- @return lsp.CodeActionParams params
--- @return boolean is_visual
function M.get_range_params(buffer_id, offset_encoding)
    local mode = api.nvim_get_mode().mode
    local params
    local is_visual = false
    if mode == "v" or mode == "V" then
        is_visual = true
        --this logic here is taken from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L125-L153
        -- [bufnum, lnum, col, off]; both row and column 1-indexed
        local start = vim.fn.getpos("v")
        local end_ = vim.fn.getpos(".")
        local start_row = start[2]
        local start_col = start[3]
        local end_row = end_[2]
        local end_col = end_[3]

        -- A user can start visual selection at the end and move backwards
        -- Normalize the range to start < end
        if start_row == end_row and end_col < start_col then
            end_col, start_col = start_col, end_col
        elseif end_row < start_row then
            start_row, end_row = end_row, start_row
            start_col, end_col = end_col, start_col
        end

        if mode == "V" then
            start_col = 1
            local lines =
                api.nvim_buf_get_lines(buffer_id, end_row - 1, end_row, true)
            end_col = #lines[1]
        end
        params = lsp.util.make_given_range_params(
            { start_row, start_col - 1 },
            { end_row, end_col - 1 },
            buffer_id,
            offset_encoding
        )
    else
        params = lsp.util.make_range_params(0, offset_encoding)
    end

    local context = {
        triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
        diagnostics = lib_lsp.diagnostic_vim_to_lsp(
            vim.diagnostic.get(buffer_id, {
                lnum = fn.line(".") - 1,
            })
        ),
    }

    ---@diagnostic disable-next-line: inject-field
    params.context = context

    return params, is_visual
end

-- get gitsigns actions
--- @param action_tuples action_tuple[]
--- @param buffer_id integer
--- @param is_visual boolean
--- @param uri lsp.DocumentUri
--- @param range lsp.Range
--- @return action_tuple[]
local function get_gitsigns_actions(
    action_tuples,
    buffer_id,
    is_visual,
    uri,
    range
)
    if not config.options.code_action.gitsigns then
        -- if not enable gitsigns, just return
        return action_tuples
    end
    local status, gitsigns = pcall(require, "gitsigns")
    -- if gitsigns not exists, just return
    if not status then
        return action_tuples
    end

    local gitsigns_actions = gitsigns.get_actions()
    for name, gitsigns_action in pairs(gitsigns_actions or {}) do
        local title = string.format(
            "%s%s",
            string.sub(name, 1, 1),
            string.sub(string.gsub(name, "_", " "), 2)
        )
        local func = gitsigns_action
        if is_visual then
            func = function()
                gitsigns_action({ range.start.line, range["end"].line })
            end
        end

        local do_func = function()
            local bufnr = vim.uri_to_bufnr(uri)
            api.nvim_buf_call(bufnr, func)
        end

        table.insert(
            action_tuples,
            --- @type action_tuple
            {
                action = {
                    title = title,
                },
                buffer_id = buffer_id,
                callback = do_func,
            }
        )
    end
    return action_tuples
end

-- get all register acions
--- @param action_tuples action_tuple[]
--- @param buffer_id integer
--- @param uri lsp.URI
--- @param range lsp.Range
--- @return action_tuple[]
local get_register_actions = function(action_tuples, buffer_id, uri, range)
    local res = register.handle(uri, range)
    for _, val in pairs(res) do
        table.insert(
            action_tuples,
            --- @type action_tuple
            {
                action = {
                    title = val.title,
                },
                buffer_id = buffer_id,
                callback = val.action,
            }
        )
    end
    return action_tuples
end

-- get action tuples
--- @param clients vim.lsp.Client[]
--- @param params table
--- @param buffer_id integer
--- @param is_visual boolean
--- @param callback fun(action_tuples:action_tuple[])
function M.get_action_tuples(clients, params, buffer_id, is_visual, callback)
    --- @type action_tuple[]
    local action_tuples = {}
    local tmp_number = 0
    for _, client in pairs(clients) do
        client:request(code_action_feature, params, function(err, result, _, _)
            if err ~= nil then
                lib_notify.Warn(string.format("there some error, %s", err))
                return
            end

            tmp_number = tmp_number + 1

            for _, action in pairs(result or {}) do
                -- add a detectto prevent action.title is blank
                if action.title ~= "" then
                    -- here must be suitable for alias action_tuple
                    table.insert(
                        action_tuples,
                        --- @type action_tuple
                        {
                            action = action,
                            client = client,
                            buffer_id = buffer_id,
                        }
                    )
                end
            end

            if tmp_number == #clients then
                action_tuples = get_gitsigns_actions(
                    action_tuples,
                    buffer_id,
                    is_visual,
                    params.textDocument.uri,
                    params.range
                )
                action_tuples = get_register_actions(
                    action_tuples,
                    buffer_id,
                    params.textDocument.uri,
                    params.range
                )
                callback(action_tuples)
            end
        end, buffer_id)
    end
end

-- exec command
-- execute a lsp command, either via client command function (if available)
-- or via workspace/executeCommand (if supported by the server)
-- this func is referred from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp.lua#L1666-L1697C6
--- @param client vim.lsp.Client
--- @param command lsp.Command
--- @param buffer_id integer
--- @param handler ?lsp.Handler only called if a server command
local function exec_command(client, command, buffer_id, handler)
    local cmdname = command.command
    local func = client.commands[cmdname] or lsp.commands[cmdname]
    if func then
        func(command, { bufnr = buffer_id, client_id = client.id })
        return
    end

    -- get the server all available commands
    local command_provider = client.server_capabilities.executeCommandProvider
    local commands = type(command_provider) == "table"
            and command_provider.commands
        or {}

    if not vim.list_contains(commands, cmdname) then
        lib_notify.Warn(
            string.format(
                "Language server `%s` does not support command `%s`",
                client.name,
                cmdname
            )
        )
        return
    end

    local params = {
        command = command.command,
        arguments = command.arguments,
    }

    client:request(exec_command_feature, params, handler, buffer_id)
end

--- @param action lsp.CodeAction|lsp.Command
--- @param client vim.lsp.Client
--- @param buffer_id integer
local function apply_action(action, client, buffer_id)
    if action.edit then
        lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end
    if action.command then
        local command = type(action.command) == "table" and action.command
            or action
        exec_command(
            client,
            --- @cast command lsp.Command
            command,
            buffer_id
        )
    end
end

-- choice action tuple
-- this function is referred from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L639-L675C6
--- @param action_tuple action_tuple
local function choice_action_tupe(action_tuple)
    local callback = action_tuple.callback
    if callback then
        callback()
        return
    end
    local action = action_tuple.action
    local client = action_tuple.client
    if client == nil then
        lib_notify.Warn(
            string.format(
                "not exist client,buffer id: %d",
                action_tuple.buffer_id
            )
        )
        return
    end
    ---@diagnostic disable-next-line: invisible
    local reg = client.dynamic_capabilities:get(
        code_action_feature,
        { bufnr = action_tuple.buffer_id }
    )

    local supports_resolve = vim.tbl_get(
        reg or {},
        "registerOptions",
        "resolveProvider"
    ) or client:supports_method(code_action_resolve_feature)
    if not action.edit and client and supports_resolve then
        client:request(
            code_action_resolve_feature,
            action,
            --- @param err lsp.ResponseError
            --- @param resolved_action any
            function(err, resolved_action)
                if err then
                    vim.notify(
                        err.code .. ": " .. err.message,
                        vim.log.levels.ERROR
                    )
                    return
                end
                apply_action(resolved_action, client, action_tuple.buffer_id)
            end,
            action_tuple.buffer_id
        )
    else
        apply_action(action, client, action_tuple.buffer_id)
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
        view:Destory()
    end, "quit code_action")

    view:KeyMap("n", config.options.code_action.key_binding.exec, function()
        local action_tuple_index = tonumber(fn.expand("<cword>"))
        if action_tuple_index == nil then
            lib_notify.Error(
                string.format(
                    "this plugin occurs an error: %s",
                    "try to convert a non-number to number"
                )
            )
            return
        end
        local action_tuple = action_tuples[action_tuple_index]
        choice_action_tupe(action_tuple)
        view:Destory()
    end, "execute acode action")

    -- number keys exec action
    for action_tuple_index, action_tuple in pairs(action_tuples) do
        -- stylua: ignore
        local desc = string.format("exec action with numberk key [%d]", action_tuple_index)
        view:KeyMap("n", tostring(action_tuple_index), function()
            choice_action_tupe(action_tuple)
            view:Destory()
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
        view:Destory()
    end, "code action auto close window when focus leave")
end

-- render the menu for the code actions
--- @param action_tuples action_tuple[]
function M.render(action_tuples)
    if vim.tbl_isempty(action_tuples) then
        lib_notify.Info("no code action!")
        return
    end
    local contents = {}
    local title = "code_action"
    local max_width = 0

    for index, action_tuple in pairs(action_tuples) do
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

    local view = layer
        .ClassView
        :New(true)
        :BufContent(0, -1, contents)
        :BufOption("filetype", "LspUI-code_action")
        :BufOption("modifiable", false)
        :BufOption("bufhidden", "wipe")
        :Size(max_width + 1, height)
        :Enter(true)
        :Anchor("NW")
        :Border("rounded")
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
