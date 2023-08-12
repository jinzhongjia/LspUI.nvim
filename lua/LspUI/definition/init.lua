local config = require("LspUI.config")
local command = require("LspUI.command")
local lib_notify = require("LspUI.lib.notify")
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
end

return M
