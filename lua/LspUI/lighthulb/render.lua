local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local store = require("LspUI.lighthulb.store")

M.render = function(buffer)
	local line = fn.line(".")
	fn.sign_place(line, store.SIGN_GROUP, store.SIGN_NAME, buffer, { lnum = line })
end

M.clean_render = function(buffer)
	fn.sign_unplace(store.SIGN_GROUP, { buffer = buffer })
end

return M
