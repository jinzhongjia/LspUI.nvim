local lsp, api, fn = vim.lsp, vim.api, vim.fn
local definition_feature = lsp.protocol.Methods.textDocument_definition
local lib_debug = require("LspUI.lib.debug")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local lib_windows = require("LspUI.lib.windows")

local M = {}

-- get all valid clients for definition
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = definition_feature })
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

return M
