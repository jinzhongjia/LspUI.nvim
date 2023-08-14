local api = vim.api
local config = require("LspUI.config")
local command = require("LspUI.command")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.definition.util")
local lib_lsp = require("LspUI.lib.lsp")
local M = {}
-- whether this module is initialized
local is_initialized = false

M.init = function()
	if not config.options.definition.enable then
		return
	end

	if is_initialized then
		return
	end

	is_initialized = true

	if config.options.definition.command_enable then
		command.register_command("definition", M.run, {})
	end
end

M.run = function()
	if not config.options.definition.enable then
		lib_notify.Info("definition is not enabled!")
		return
	end

	-- get current buffer
	local current_buffer = api.nvim_get_current_buf()
	-- get current window
	local current_window = api.nvim_get_current_win()

	local clients = util.get_clients(current_buffer)
	if clients == nil then
		return
	end

	local params = util.make_params(current_window)

	util.get_definition_tuple(current_buffer, clients, params, function() end)
end

return M
