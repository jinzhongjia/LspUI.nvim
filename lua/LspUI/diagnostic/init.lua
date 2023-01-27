local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local render = require("LspUI.diagnostic.render")
local util = require("LspUI.diagnostic.util")

M.init = function()
	if not config.diagnostic.enable then
		return
	end
end

local function switch_arg(arg)
	if arg == "next" then
		render.display(util.Next())
	elseif arg == "prev" then
		render.display(util.Prev())
	end
end

M.run = function(arg)
	if not config.diagnostic.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end
	switch_arg(arg)
end

return M
