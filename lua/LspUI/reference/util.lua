local lsp = vim.lsp
local reference_feature = lsp.protocol.Methods.textDocument_references

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = reference_feature })
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
--- @see  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#referenceParams
M.make_params = function(window_id, offset_encoding)
    local params = lsp.util.make_position_params(window_id, offset_encoding)
    -- TODO:add a option for `includeDeclaration`
    ---@diagnostic disable-next-line: inject-field
    params.context = { includeDeclaration = true }
    return params
end

return M
