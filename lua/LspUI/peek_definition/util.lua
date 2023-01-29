local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.Handle = function(result)
	if not result then
		lib.log.Info("not found the definition!")
	end
	local uri, range = nil, nil
	if type(result[1]) == "table" then
		uri = result[1].uri or result[1].targetUri
		range = result[1].range or result[1].targetRange
	else
		uri = result.uri
		range = result.range
	end

	return uri, range
end

return M
