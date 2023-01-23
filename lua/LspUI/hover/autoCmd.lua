local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.auto_cmd = function(current_buffer, new_buffer, win_id)
	api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufDelete" }, {
		buffer = current_buffer,
		callback = function(arg)
			pcall(api.nvim_win_close, win_id, true)
			api.nvim_del_autocmd(arg.id)
		end,
		desc = lib.util.Command_des("Auto close hover document when current windows cursor move"),
	})
end

return M
