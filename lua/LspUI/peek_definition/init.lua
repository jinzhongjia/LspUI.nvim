local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local request = require("LspUI.peek_definition.request")
local util = require("LspUI.peek_definition.util")
local render = require("LspUI.peek_definition.render")

M.init = function()
	if not config.option.peek_definition.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end
end

M.run = function()
	if not config.option.peek_definition.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end

	request.request(function(result)
		local uri, range = util.Handle(result)
		render.render(uri, range)
	end)
end

return M
