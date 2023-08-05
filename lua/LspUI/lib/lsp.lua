local lsp, api = vim.lsp, vim.api

local notify = require("LspUI.lib.notify")

local M = {}

-- check whether there is an active lsp client
-- note: this function now should not be called!!
--- @param is_notify boolean whether notify, default not
M.is_lsp_active = function(is_notify)
	is_notify = is_notify or false
	local current_buf = api.nvim_get_current_buf()

	local clients = lsp.get_clients({
		bufnr = current_buf,
	})

	if vim.tbl_isempty(clients) then
		if is_notify then
			local message = string.format("not found lsp client on this buffer, id is %d", current_buf)
			notify.Warn(message)
		end
		return false
	end
	return true
end

return M
