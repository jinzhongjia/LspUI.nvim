local lib_notify = require("LspUI.lib.notify")
local config = require("LspUI.config")
local command = require("LspUI.command")
local M = {}

-- whether this module has initialized
local is_initialized = false

-- init for hover
M.init = function()
	if not config.options.hover.enable then
		return
	end

	if is_initialized then
		return
	end

	is_initialized = true

	-- register command
	if config.options.hover.command_enable then
		command.register_command("hover", M.run, {})
	end
end

-- run of hover
M.run = function()
	if not config.options.hover.enable then
		lib_notify.Info("hover is not enabled!")
		return
	end
end

return M
