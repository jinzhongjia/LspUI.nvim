local lsp, fn = vim.lsp, vim.fn
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction

local config = require("LspUI.config")
local global = require("LspUI.global")
local lib_lsp = require("LspUI.lib.lsp")
local lib_util = require("LspUI.lib.util")

local M = {}

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
--- @return integer sign_identifier sign's identifier, -1 means failing
M.render = function(buffer_id, line)
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

-- this function will request all lsp clients
--- @param buffer_id integer buffer's id
--- @param callback function callback is a function, has a param boolean
M.request = function(buffer_id, callback)
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
    if config.options.code_action.gitsigns then
        local status, gitsigns = pcall(require, "gitsigns")
        if status then
            local gitsigns_actions = gitsigns.get_actions()
            if gitsigns_actions and not vim.tbl_isempty(gitsigns_actions) then
                new_callback(true)
            end
        end
    end

    local clients = M.get_clients(buffer_id)
    local tmp_number = 0
    for _, client in pairs(clients or {}) do
        client.request(code_action_feature, params, function(_, result, _, _)
            tmp_number = tmp_number + 1
            if result and type(result) == "table" and next(result) ~= nil then
                new_callback(true)
                return
            end
            if tmp_number == #clients then
                new_callback(false)
            end
        end, buffer_id)
    end
end

return M
