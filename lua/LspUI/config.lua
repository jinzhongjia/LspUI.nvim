local lib_notify = require("LspUI.lib.notify")

local default_rename_config = {
	enable = true,
	command_enable = true,
	auto_select = true,
	key_binding = {
		exec = "<CR>",
		quit = "<ESC>",
	},
}

local default_lighthulb_config = {
	enable = true,
	-- whether cache code action, if do, code action will use lighthulb's cache
	is_cached = true,
	icon = "💡",
}

local default_code_action_config = {
	enable = true,
	command_enable = true,
	icon = "💡",
	key_binding = {
		exec = "<cr>",
		prev = "k",
		next = "j",
		quit = "q",
	},
}

-- default config
local default_config = {
	rename = default_rename_config,
	lighthulb = default_lighthulb_config,
	code_action = default_code_action_config,
}

-- Prevent plugins from being initialized multiple times
local is_already_init = false

local M = {}

-- LspUI plugin init function
-- you need to pass a table
--- @param config table
M.setup = function(config)
	-- check plugin whether has initialized
	if is_already_init then
		-- TODO:whether retain this
		lib_notify.Warn("you have already initialized the plugin config!")
		return
	end

	config = config or {}
	M.options = vim.tbl_deep_extend("force", default_config, config)
	is_already_init = true
end

--TODO: Should add api to ensure that the configuration can be modified in real time

return M
