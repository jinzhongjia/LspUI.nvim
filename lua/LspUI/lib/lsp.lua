local lsp, api = vim.lsp, vim.api

local lib_notify = require("LspUI.lib.notify")

local M = {}

-- format and complete diagnostic default option,
-- this func is referred from
-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/diagnostic.lua#L138-L160
--- @param diagnostics lsp.Diagnostic[]
--- @return lsp.Diagnostic[]
M.diagnostic_vim_to_lsp = function(diagnostics)
    ---@diagnostic disable-next-line:no-unknown
    return vim.tbl_map(function(diagnostic)
        ---@cast diagnostic vim.Diagnostic
        return vim.tbl_extend("keep", {
            -- "keep" the below fields over any duplicate fields
            -- in diagnostic.user_data.lsp
            range = {
                start = {
                    line = diagnostic.lnum,
                    character = diagnostic.col,
                },
                ["end"] = {
                    line = diagnostic.end_lnum,
                    character = diagnostic.end_col,
                },
            },
            severity = type(diagnostic.severity) == "string"
                    and vim.diagnostic.severity[diagnostic.severity]
                or diagnostic.severity,
            message = diagnostic.message,
            source = diagnostic.source,
            code = diagnostic.code,
        }, diagnostic.user_data and (diagnostic.user_data.lsp or {}) or {})
    end, diagnostics)
end

return M
