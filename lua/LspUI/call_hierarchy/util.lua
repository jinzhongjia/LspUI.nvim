local lsp = vim.lsp
local call_hierarchy_prepare_feature =
    lsp.protocol.Methods.textDocument_prepareCallHierarchy
local M = {}

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = call_hierarchy_prepare_feature,
    })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

return M
