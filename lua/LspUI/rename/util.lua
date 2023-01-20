local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local method = "textDocument/rename"

M.Get_clients = function(current)
	local clients = vim.lsp.get_active_clients({
		bufnr = current,
	})
	clients = vim.tbl_filter(function(client)
		return client.supports_method(method)
	end, clients)

	return clients
end

M.Feedkeys = function(keys, mode)
	api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, true, true), mode, true)
end

M.Do_rename = function(params, clients, buffer, name)
	local function rename(idx, client)
		if not client then
			return
		end
		params.newName = name
		local handler = vim.tbl_isempty(client.handlers) and client.handlers[method] or vim.lsp.handlers[method]
		client.request(method, params, function(...)
			handler(...)
			rename(next(clients, idx))
		end, buffer)
	end
	rename(next(clients))
end

M.Close_window = function(win_id)
	if vim.fn.mode() == "i" then
		vim.cmd([[stopinsert]])
	end
	api.nvim_win_close(win_id, true)
end

return M
