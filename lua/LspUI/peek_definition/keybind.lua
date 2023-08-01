local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.keybind = function(buffer, win_id, filename, start_line, start_char_pos)
	local keymap = config.option.peek_definition.keybind
	for action, key in pairs(keymap) do
		vim.keymap.set("n", key, function()
			if action ~= "quit" then
				api.nvim_win_close(win_id, true)
				vim.cmd(action .. " " .. filename)
				local new_win_id = api.nvim_get_current_win()
				api.nvim_win_set_cursor(new_win_id, { start_line + 1, start_char_pos })
			else
				api.nvim_win_close(win_id, true)
			end
		end, { buffer = buffer })
	end
end

return M
