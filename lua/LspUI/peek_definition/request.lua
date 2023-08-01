local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local method = "textDocument/definition"

M.request = function(func)
	local current_buffer = api.nvim_get_current_buf()
	local params = lsp.util.make_position_params()
	lsp.buf_request_all(current_buffer, method, params, function(results)
		local result = nil
		for _, res in pairs(results) do
			if res and res.result then
				result = res.result
				break
			end
		end
		func(result)
	end)
end

return M
