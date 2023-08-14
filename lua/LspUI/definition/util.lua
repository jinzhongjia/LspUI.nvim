local lsp = vim.lsp
local definition_feature = lsp.protocol.Methods.textDocument_definition

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
	local clients = lsp.get_clients({ bufnr = buffer_id, method = definition_feature })
	return #clients == 0 and nil or clients
end

return M
