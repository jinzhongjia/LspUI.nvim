local lsp = vim.lsp
local implementation_feature = lsp.protocol.Methods.textDocument_implementation

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = implementation_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- make request param
-- TODO: implement `WorkDoneProgressParams` and `PartialResultParams`
--
--- @param window_id integer
--- @param offset_encoding string
--- @return lsp.TextDocumentPositionParams
--- @see https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#implementationParams
M.make_params = function(window_id, offset_encoding)
    local params = lsp.util.make_position_params(window_id, offset_encoding)
    return params
end

return M
