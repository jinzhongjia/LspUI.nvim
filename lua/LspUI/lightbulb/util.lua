local lsp, fn, api = vim.lsp, vim.fn, vim.api
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction

local code_action_register = require("LspUI.code_action.register")
local config = require("LspUI.config")
local global = require("LspUI.global")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")

local M = {}

local attach_autocmd_id = -1
local autocmd_list = {}

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = code_action_feature })
    return #clients == 0 and nil or clients
end

-- render sign
--- @param buffer_id integer buffer's id
--- @param line integer the line number, and this will be set as sign id
--- @return integer? sign_identifier sign's identifier, -1 means failing
M.render = function(buffer_id, line)
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    return fn.sign_place(
        line,
        global.lightbulb.sign_group,
        global.lightbulb.sign_name,
        buffer_id,
        {
            lnum = line,
        }
    )
end

-- clear sign
M.clear_render = function()
    -- TODO:Do you need to add pcall here???
    fn.sign_unplace(global.lightbulb.sign_group)
end

-- register the sign
-- note: this func only can be called once!
M.register_sign = function()
    fn.sign_define(
        global.lightbulb.sign_name,
        { text = config.options.lightbulb.icon }
    )
end

-- unregister the sign
M.unregister_sign = function()
    fn.sign_undefine(global.lightbulb.sign_name)
end

-- this function will request all lsp clients
--- @param buffer_id integer buffer's id
--- @param callback function callback is a function, has a param boolean
M.request = function(buffer_id, callback)
    -- this buffer id maybe invalid
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    -- when switch buffer too quickly, window will be not correct
    -- maybe this problem is caused by neovim event loop
    if buffer_id ~= api.nvim_win_get_buf(api.nvim_get_current_win()) then
        return
    end
    local params = lsp.util.make_range_params()
    local context = {
        triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
        diagnostics = lib_lsp.diagnostic_vim_to_lsp(
            vim.diagnostic.get(buffer_id, {
                lnum = fn.line(".") - 1,
            })
        ),
    }
    params.context = context

    -- which commented below is the old logic
    -- lsp.buf_request_all(buffer_id, code_action_feature, params, function(results)
    -- 	local has_action = false
    -- 	for _, result in pairs(results or {}) do
    -- 		if result.result and type(result.result) == "table" and next(result.result) ~= nil then
    -- 			has_action = true
    -- 			break
    -- 		end
    -- 	end
    -- 	if has_action then
    -- 		callback(true)
    -- 	else
    -- 		callback(false)
    -- 	end
    -- end)

    -- new logic, reduce a little calculations
    local new_callback = lib_util.exec_once(callback)
    -- here will Check for new content
    if config.options.code_action.gitsigns then
        local status, gitsigns = pcall(require, "gitsigns")
        if status then
            local gitsigns_actions = gitsigns.get_actions()
            if gitsigns_actions and not vim.tbl_isempty(gitsigns_actions) then
                new_callback(true)
                return
            end
        end
    end
    if
        not vim.tbl_isempty(
            code_action_register.handle(params.textDocument.uri, params.range)
        )
    then
        new_callback(true)
        return
    end

    local clients = M.get_clients(buffer_id)
    local tmp_number = 0
    for _, client in pairs(clients or {}) do
        client.request(code_action_feature, params, function(err, result, _, _)
            tmp_number = tmp_number + 1
            if err ~= nil then
                lib_notify.Warn(
                    string.format(
                        "lightbulb meet error, server %s, error code is %d, msg is %s",
                        client.name,
                        err.code,
                        err.message
                    )
                )
            else
                if
                    result
                    and type(result) == "table"
                    and next(result) ~= nil
                then
                    new_callback(true)
                    return
                end
            end

            if tmp_number == #clients then
                new_callback(false)
            end
        end, buffer_id)
    end
end

local debounce_func = function(buffer_id)
    local func = function()
        M.request(buffer_id, function(result)
            M.clear_render()
            if result then
                local line = fn.line(".")
                if line == nil then
                    return
                end
                M.render(buffer_id, line)
            end
        end)
    end
    if config.options.lightbulb.debounce then
        if type(config.options.lightbulb.debounce) == "number" then
            return lib_util.debounce(
                func,
                ---@diagnostic disable-next-line: param-type-mismatch
                math.floor(config.options.lightbulb.debounce)
            )
        else
            return lib_util.debounce(func, 250)
        end
    else
        return func
    end
end

-- auto command for lightbulb
M.autocmd = function()
    local lightbulb_group =
        api.nvim_create_augroup("Lspui_lightBulb", { clear = true })

    -- here is just no cache option
    attach_autocmd_id = api.nvim_create_autocmd("LspAttach", {
        group = lightbulb_group,
        callback = function()
            -- get current buffer
            local current_buffer = api.nvim_get_current_buf()
            local group_id = api.nvim_create_augroup(
                "Lspui_lightBulb_" .. tostring(current_buffer),
                { clear = true }
            )

            autocmd_list[current_buffer] = {}

            local new_func = debounce_func(current_buffer)

            local hold_autocmd_id = api.nvim_create_autocmd({ "CursorHold" }, {
                group = group_id,
                buffer = current_buffer,
                callback = vim.schedule_wrap(function()
                    new_func()
                end),
                desc = lib_util.command_desc(
                    "Lightbulb update when CursorHold"
                ),
            })

            local move_autocmd_id = api.nvim_create_autocmd(
                { "InsertEnter", "WinLeave" },
                {
                    group = group_id,
                    buffer = current_buffer,
                    callback = function()
                        M.clear_render()
                    end,
                    desc = lib_util.command_desc(
                        "Lightbulb update when InsertEnter"
                    ),
                }
            )

            local wipe_autocmd_id = api.nvim_create_autocmd({ "BufWipeout" }, {
                group = group_id,
                buffer = current_buffer,
                callback = function()
                    api.nvim_del_augroup_by_id(group_id)
                end,
                desc = lib_util.command_desc("Exec clean cmd when QuitPre"),
            })

            for _, autocmd_id in pairs({
                hold_autocmd_id,
                move_autocmd_id,
                wipe_autocmd_id,
            }) do
                table.insert(autocmd_list[current_buffer], autocmd_id)
            end
        end,
        desc = lib_util.command_desc("Lsp attach lightbulb cmd"),
    })
end

M.un_autocmd = function()
    pcall(api.nvim_del_autocmd, attach_autocmd_id)
    for _, autocmd_ids in pairs(autocmd_list) do
        for _, autocmd_id in pairs(autocmd_ids) do
            pcall(api.nvim_del_autocmd, autocmd_id)
        end
    end
end

return M
