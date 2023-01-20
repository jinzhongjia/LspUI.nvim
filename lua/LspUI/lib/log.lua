local lsp, fn, api = vim.lsp, vim.fn, vim.api

local config = require("LspUI.config")

local M = {}

-- this is public notify message prefix
local _notify_public_message = "[LspUI]:"

M.Error = function(message)
	api.nvim_notify(_notify_public_message .. message, vim.log.levels.ERROR, {})
end

M.Info = function(message)
	api.nvim_notify(_notify_public_message .. message, vim.log.levels.INFO, {})
end

M.Warn = function(message)
	api.nvim_notify(_notify_public_message .. message, vim.log.levels.WARN, {})
end

return M
