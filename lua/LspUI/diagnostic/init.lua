local config = require("LspUI.config")
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
end

--- @param arg "next"|"prev"
M.run = function(arg)
	if not config.options.diagnostic.enable then
		return
	end
end

return M
