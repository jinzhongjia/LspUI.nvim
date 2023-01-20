local version = "0.0.1"

local M = {
	lightbulb = {
		enable = false,
		command_enable = true,
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
}

M.version = function()
	return version
end

return M
