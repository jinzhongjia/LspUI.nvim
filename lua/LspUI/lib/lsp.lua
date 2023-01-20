local lsp, fn, api = vim.lsp, vim.fn, vim.api

local config = require("LspUI.config")
local util = require("LspUI.lib.util")
local log = require("LspUI.lib.log")
local lsp_document = {
	code_action_method = "textDocument/codeAction",
}

local M = {}

-- Check if there is an active lsp client， @prarms：isNotify, Whether to notify
M.Check_lsp_active = function(isNotify)
	isNotify = isNotify or false
	-- get current buffer
	local current_buf = api.nvim_get_current_buf()
	-- get_active_clients
	local active_clients = lsp.get_active_clients({ buffer = current_buf })
	if vim.tbl_isempty(active_clients) then
		if isNotify then
			log.Warn("not found lsp client in this buffer!")
		end
		return false
	end
	return true
end

-- check the buffer lsp support codeaction
M.Check_lsp_support_codeaction = function(buffer)
	local clients = lsp.get_active_clients({ buffer = buffer })
	for _, client in pairs(clients) do
		if
			client.supports_method(lsp_document.code_action_method)
			and util.Tb_has_value(client.config.filetypes, vim.bo[buffer].filetype)
		then
			return true
		end
	end
	return false
end

return M
