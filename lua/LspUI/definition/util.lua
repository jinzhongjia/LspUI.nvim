local lsp = vim.lsp
local definition_feature = lsp.protocol.Methods.textDocument_definition
local lib_lsp = require("LspUI.lib.lsp")

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
	local clients = lsp.get_clients({ bufnr = buffer_id, method = definition_feature })
	return #clients == 0 and nil or clients
end

-- make request param
-- TODO: implement `WorkDoneProgressParams` and `PartialResultParams`
--
--- @param window_id integer
--- @return lsp.TextDocumentPositionParams
--- @see https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#definitionParams
M.make_params = function(window_id)
	return lsp.util.make_position_params(window_id)
end

--- @param buffer_id integer
---@param clients lsp.Client[]
---@param params lsp.TextDocumentPositionParams
---@param callback function
M.get_definition_tuple = function(buffer_id, clients, params, callback)
	lib_lsp.lsp_clients_request(buffer_id, clients, definition_feature, params, function(data)
		for _, val in pairs(data) do
			--- @type lsp.Location|lsp.Location[]|lsp.LocationLink[]|nil
			local definition_response = val.result
			local client = val.client
		end
	end)
end

return M
