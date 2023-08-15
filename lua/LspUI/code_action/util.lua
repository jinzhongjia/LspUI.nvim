local lsp, api, fn = vim.lsp, vim.api, vim.fn
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction
local exec_command_feature = lsp.protocol.Methods.workspace_executeCommand
local code_action_resolve_feature = lsp.protocol.Methods.codeAction_resolve

local config = require("LspUI.config")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

--- @alias action_tuple { action: lsp.CodeAction|lsp.Command, client: lsp.Client, buffer_id: integer }

local M = {}

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = code_action_feature })
    return #clients == 0 and nil or clients
end

-- make range params
--- @param buffer_id integer
--- @return lsp.CodeActionParams
M.get_range_params = function(buffer_id)
    local mode = api.nvim_get_mode().mode
    local params
    if mode == "v" or mode == "V" then
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
        params = lsp.util.make_given_range_params(
            { start_row, start_col - 1 },
            { end_row, end_col - 1 }
        )
    else
        params = lsp.util.make_range_params()
    end

    local context = {
        triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
        diagnostics = lib_lsp.diagnostic_vim_to_lsp(
            vim.diagnostic.get(buffer_id, {
                lnum = fn.line(".") - 1,
            })
        ),
    }

    params.context = context

    return params
end

-- get action tuples
--- @param clients lsp.Client[]
--- @param params table
--- @param buffer_id integer
--- @param callback function
M.get_action_tuples = function(clients, params, buffer_id, callback)
    local action_tuples = {}
    local tmp_number = 0
    for _, client in pairs(clients) do
        client.request(code_action_feature, params, function(err, result, _, _)
            if err ~= nil then
                lib_notify.Warn(string.format("there some error, %s", err))
                return
            end

            tmp_number = tmp_number + 1

            for _, action in pairs(result or {}) do
                -- add a detectto prevent action.title is blank
                if action.title ~= "" then
                    -- here must be suitable for alias action_tuple
                    table.insert(action_tuples, {
                        action = action,
                        client = client,
                        buffer_id = buffer_id,
                    })
                end
            end

            if tmp_number == #clients then
                callback(action_tuples)
            end
        end, buffer_id)
    end
end

-- exec command
-- execute a lsp command, either via client command function (if available)
-- or via workspace/executeCommand (if supported by the server)
-- this func is referred from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp.lua#L1666-L1697C6
--- @param client lsp.Client
--- @param command lsp.Command
--- @param buffer_id integer
--- @param handler? lsp-handler only called if a server command
local exec_command = function(client, command, buffer_id, handler)
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

    client.request(exec_command_feature, params, handler, buffer_id)
end

--- @param action lsp.CodeAction|lsp.Command
--- @param client lsp.Client
--- @param buffer_id integer
local apply_action = function(action, client, buffer_id)
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
local choice_action_tupe = function(action_tuple)
    local action = action_tuple.action
    local client = action_tuple.client
    ---@diagnostic disable-next-line: invisible
    local reg = client.dynamic_capabilities:get(
        code_action_feature,
        { bufnr = action_tuple.buffer_id }
    )

    local supports_resolve = vim.tbl_get(
        reg or {},
        "registerOptions",
        "resolveProvider"
    ) or client.supports_method(code_action_resolve_feature)
    if not action.edit and client and supports_resolve then
        client.request(
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

--- @param buffer_id integer
--- @param window_id integer
--- @param action_tuples action_tuple[]
local keybinding_autocmd = function(buffer_id, window_id, action_tuples)
    -- keybind

    -- next action
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.code_action.key_binding.next,
        "",
        {
            nowait = true,
            callback = function()
                -- get current line number
                local _, lnum, _, _ = unpack(vim.fn.getpos("."))
                if lnum == #action_tuples then
                    api.nvim_win_set_cursor(window_id, { 1, 1 })
                    return
                end

                api.nvim_win_set_cursor(window_id, { lnum + 1, 1 })
            end,
            desc = lib_util.command_desc("go to next action"),
        }
    )

    -- prev action
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.code_action.key_binding.prev,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                -- get current line number
                local _, lnum, _, _ = unpack(vim.fn.getpos("."))
                if lnum == 1 then
                    api.nvim_win_set_cursor(window_id, { #action_tuples, 1 })
                    return
                end

                api.nvim_win_set_cursor(window_id, { lnum - 1, 1 })
            end,
            desc = lib_util.command_desc("go to prev action"),
        }
    )

    -- quit action
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.code_action.key_binding.quit,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                -- the buffer will be deleted automatically when windows closed
                lib_windows.close_window(window_id)
            end,
            desc = lib_util.command_desc("quit code_action"),
        }
    )

    -- exec action
    api.nvim_buf_set_keymap(
        buffer_id,
        "n",
        config.options.code_action.key_binding.exec,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
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
                lib_windows.close_window(window_id)
            end,
            desc = lib_util.command_desc("execute acode action"),
        }
    )

    -- number keys exec action
    for action_tuple_index, action_tuple in pairs(action_tuples) do
        api.nvim_buf_set_keymap(
            buffer_id,
            "n",
            tostring(action_tuple_index),
            "",
            {
                noremap = true,
                callback = function()
                    choice_action_tupe(action_tuple)
                    lib_windows.close_window(window_id)
                end,
                desc = lib_util.command_desc(
                    string.format(
                        "exec action with numberk key [%d]",
                        action_tuple_index
                    )
                ),
            }
        )
    end

    --
    -- lock cursor
    --
    api.nvim_create_autocmd("CursorMoved", {
        buffer = buffer_id,
        callback = function()
            local _, lnum, col, _ = unpack(vim.fn.getpos("."))
            if col ~= 2 then
                api.nvim_win_set_cursor(window_id, { lnum, 1 })
            end
        end,
        desc = lib_util.command_desc("lock the cursor"),
    })

    -- auto close window when focus leave float window
    api.nvim_create_autocmd("WinLeave", {
        buffer = buffer_id,
        once = true,
        callback = function()
            lib_windows.close_window(window_id)
        end,
        desc = lib_util.command_desc(
            "code action auto close window when focus leave"
        ),
    })
end

-- render the menu for the code actions
--- @param action_tuples action_tuple[]
M.render = function(action_tuples)
    if #action_tuples == 0 then
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

    local new_buffer = api.nvim_create_buf(false, true)

    api.nvim_buf_set_lines(new_buffer, 0, -1, false, contents)
    api.nvim_buf_set_option(new_buffer, "filetype", "LspUI-code_action")
    api.nvim_buf_set_option(new_buffer, "modifiable", false)
    api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

    local new_window_wrap = lib_windows.new_window(new_buffer)

    lib_windows.set_width_window(new_window_wrap, max_width + 1)
    lib_windows.set_height_window(new_window_wrap, height)
    lib_windows.set_enter_window(new_window_wrap, true)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_focusable_window(new_window_wrap, true)
    lib_windows.set_relative_window(new_window_wrap, "cursor")
    lib_windows.set_col_window(new_window_wrap, 1)
    lib_windows.set_row_window(new_window_wrap, 1)
    lib_windows.set_style_window(new_window_wrap, "minimal")
    lib_windows.set_right_title_window(new_window_wrap, title)

    local window_id = lib_windows.display_window(new_window_wrap)

    api.nvim_win_set_option(window_id, "winhighlight", "Normal:Normal")

    keybinding_autocmd(new_buffer, window_id, action_tuples)
end

return M
