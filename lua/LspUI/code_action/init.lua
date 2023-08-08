local api = vim.api
local config = require("LspUI.config")
local command = require("LspUI.command")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.code_action.util")
local lib_debug = require("LspUI.lib.debug")

local M = {}

-- whether this module is initialized
local is_initialized = false

M.init = function()
	if not config.options.code_action.enable then
		return
	end

	if is_initialized then
		return
	end

	is_initialized = true

	if config.options.code_action.command_enable then
		command.register_command("code_action", M.run, {})
	end
end

M.run = function()
	if not config.options.code_action.enable then
		lib_notify.Info("code_sction is not enabled!")
		return
	end
	-- get current buffer
	local current_buffer = api.nvim_get_current_buf()

	-- get all valid clients which support code action, if return nil, that means no client
	local clients = util.get_clients(current_buffer)
	if clients == nil then
		lib_notify.Warn("no client supports code_action!")
		return
	end

	local params = util.get_range_params(current_buffer)
	util.get_action_tuples(clients, params, current_buffer, function(action_tuples)
		util.render(action_tuples)
	end)
end

return M
