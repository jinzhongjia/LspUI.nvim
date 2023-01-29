local version = "0.0.1"

local M = {}

M.option = {
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
	hover = {
		enable = true,
		command_enable = true,
		keybind = {
			prev = "p",
			next = "n",
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
	diagnostic = {
		enable = true,
		command_enable = true,
		icons = {
			Error = " ",
			Warn = " ",
			Info = " ",
			Hint = " ",
		},
	},
	peek_definition = {
		enable = false,
		command_enable = true,
		keybind = {
			edit = "op",
			vsplit = "ov",
			split = "os",
			quit = "q",
		},
	},
}

M.version = function()
	return version
end

return M
