local lib_notify = require("LspUI.lib.notify")

--- @type LspUI_rename_config
local default_rename_config = {
	enable = true,
	command_enable = true,
	auto_select = true,
	key_binding = {
		exec = "<CR>",
		quit = "<ESC>",
	},
}

--- @type LspUI_lightbulb_config
local default_lightbulb_config = {
	enable = true,
	-- whether cache code action, if do, code action will use lightbulb's cache
	is_cached = true,
	icon = "💡",
}

--- @type LspUI_code_action_config
local default_code_action_config = {
	enable = true,
	command_enable = true,
	key_binding = {
		exec = "<cr>",
		prev = "k",
		next = "j",
		quit = "q",
	},
}

--- @type LspUI_diagnostic
local default_diagnostic_config = {
	enable = true,
	command_enable = true,
}

--- @type LspUI_hover
local default_hover_config = {
	enable = true,
	command_enable = true,
	key_binding = {
		prev = "p",
		next = "n",
		quit = "q",
	},
}

-- default config
--- @type LspUI_config
local default_config = {
	rename = default_rename_config,
	lightbulb = default_lightbulb_config,
	code_action = default_code_action_config,
	diagnostic = default_diagnostic_config,
	hover = default_hover_config,
}

-- Prevent plugins from being initialized multiple times
local is_already_init = false

local M = {}

-- LspUI plugin init function
-- you need to pass a table
--- @param config LspUI_config?
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
