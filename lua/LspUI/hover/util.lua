local lsp = vim.lsp
local hover_feature = lsp.protocol.Methods.textDocument_hover

local M = {}

-- get all valid clients for hover
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
	local clients = lsp.get_clients({ bufnr = buffer_id, method = hover_feature })
	return #clients == 0 and nil or clients
end

return M
