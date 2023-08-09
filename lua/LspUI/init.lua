local config = require("LspUI.config")
local api = require("LspUI.api")
local modules = require("LspUI.modules")
local command = require("LspUI.command")

return {
	-- init `LspUI` plugin
	--- @param user_config LspUI_config user's plugin config
	setup = function(user_config)
		config.setup(user_config)
		command.init()
		for _, module in pairs(modules) do
			module.init()
		end
	end,
	api = api.api,
}
