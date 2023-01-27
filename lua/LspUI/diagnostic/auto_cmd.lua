local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.autocmd = function(current_buffer, win_id)
	api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
		buffer = current_buffer,
		callback = function(arg)
			api.nvim_win_close(win_id, true)
			api.nvim_del_autocmd(arg.id)
		end,
		desc = lib.util.Command_des("diagnostic, auto close windows"),
	})
end

return M
