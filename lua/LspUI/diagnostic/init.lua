local config = require("LspUI.config")
local command = require("LspUI.command")
local util = require("LspUI.diagnostic.util")
local M = {}

-- whether this module has initialized
local is_initialized = false

-- init for diagnostic
M.init = function()
	if not config.options.diagnostic.enable then
		return
	end
	if is_initialized then
		return
	end

	is_initialized = true

	if config.options.diagnostic.command_enable then
		command.register_command("diagnostic", M.run, { "next", "prev" })
	end
end

--- @param arg "next"|"prev"
M.run = function(arg)
	if not config.options.diagnostic.enable then
		return
	end

	util.render(arg)
end

return M
