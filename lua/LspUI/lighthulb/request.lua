local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local method = "textDocument/codeAction"

M.request = function(current_buffer, dofunc)
	local params = lsp.util.make_range_params()
	local current_line = fn.line(".") - 1
	local diagnostics = vim.diagnostic.get(current_buffer, {
		lnum = current_line,
	})
	params.context = { diagnostics = diagnostics }
	lsp.buf_request_all(current_buffer, method, params, function(results)
		local has_action = false
		for _, result in pairs(results or {}) do
			if result.result and type(result.result) == "table" and next(result.result) ~= nil then
				has_action = true
				break
			end
		end
		if has_action and dofunc ~= nil then
			dofunc(true)
		else
			dofunc(false)
		end
	end)
end

return M
