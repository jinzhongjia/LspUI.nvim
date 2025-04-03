local lsp = vim.lsp

--- @class ClassLsp
--- @field _client vim.lsp.Client|nil
local ClassLsp = {
    _client = nil,
}

--- @param method string
--- @param param lsp.HoverParams
--- @param callback lsp.Handler
function ClassLsp:Hover(method, param, callback)
    self._client:request(
        lsp.protocol.Methods.textDocument_hover,
        param,
        callback
    )
end
