local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.Prev = function()
	local prev_diagnostic = vim.diagnostic.get_prev()
	return prev_diagnostic
end

M.Next = function()
	local next_diagnostic = vim.diagnostic.get_next()
	return next_diagnostic
end

M.severity = function(severity)
	local severities = {
		"Error",
		"Warn",
		"Info",
		"Hint",
	}
	return severities[severity]
end

M.highlight_name = function(severity)
	local name_group = {
		"DiagnosticError",
		"DiagnosticWarn",
		"DiagnosticInfo",
		"DiagnosticHint",
	}
	return name_group[severity]
end

M.highlight = function(buffer, hl_wrap)
	for i = 1, hl_wrap.height, 1 do
		api.nvim_buf_add_highlight(buffer, -1, hl_wrap.hl_name, i - 1, 0, -1)
	end
	for _, val in pairs(hl_wrap.hl_arr) do
		api.nvim_buf_add_highlight(buffer, -1, "Comment", val.line, val.start_col, val.end_col)
	end
end

return M
