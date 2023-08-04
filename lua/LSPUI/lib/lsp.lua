local lsp, api = vim.lsp, vim.api

local notify = require("LSPUI.lib.notify")

local M = {}

-- check whether there is an active lsp client
--- @param is_notify boolean whether notify
M.is_lsp_active = function(is_notify)
	is_notify = is_notify or false
	local current_buf = api.nvim_get_current_buf()

	local clients = lsp.get_clients({
		bufnr = current_buf,
	})

	if vim.tbl_isempty(clients) and is_notify then
		local message = string.format("not found lsp client on this buffer, id is %d", current_buf)
		notify.Warn(message)
	end
end

return M
