local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local store = require("LspUI.lighthulb.store")

M.render = function(buffer)
	local current_win_id = api.nvim_get_current_win()
	-- check current win variable lsp_define to judge it create by definition
	local status, _ = pcall(api.nvim_win_get_var, current_win_id, lib.store.lsp_define)
	if (not config.peek_definition.enable) or status then
		return
	end
	local line = fn.line(".")
	fn.sign_place(line, store.SIGN_GROUP, store.SIGN_NAME, buffer, { lnum = line })
end

M.clean_render = function(buffer)
	fn.sign_unplace(store.SIGN_GROUP, { buffer = buffer })
end

return M
