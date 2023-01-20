local version = "0.0.1"

local M = {
	lightbulb = {
		enable = false,
		command_enable = false,
		icon = "💡",
	},
	code_action = {
		enable = true,
		command_enable = true,
		icon = "💡",
		keybind = {
			exec = "<CR>",
			prev = "k",
			next = "j",
			quit = "q",
		},
	},
	rename = {
		enable = true,
		command_enable = true,
		auto_select = true, -- whether select all automatically
		keybind = {
			change = "<CR>",
			quit = "<ESC>",
		},
	},
}

M.version = function()
	return version
end

return M
