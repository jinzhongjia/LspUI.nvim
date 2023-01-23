local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local method = "textDocument/hover"

M.Request = function(handle)
	local params = lsp.util.make_position_params()
	lsp.buf_request_all(0, method, params, function(responses)
		local res = {}
		for _, response in pairs(responses) do
			if response and response.result and response.result.contents then
				-- table.insert(res, response.result.contents)
				res = response.result.contents
			end
		end
		handle(res)
	end)
end

return M
