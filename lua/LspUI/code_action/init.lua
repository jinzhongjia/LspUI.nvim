local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local render = require("LspUI.code_action.render")
local util = require("LspUI.code_action.util")

local method = "textDocument/codeAction"

M.init = function()
	if not config.option.code_action.enable then
		return
	end

	if not lib.lsp.Check_lsp_active() then
		return
	end
end

M.run = function()
	if not config.option.code_action.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end
	local mode = api.nvim_get_mode().mode
	local params
	if mode == "v" or mode == "V" then
		-- [bufnum, lnum, col, off]; both row and column 1-indexed
		local start = vim.fn.getpos("v")
		local end_ = vim.fn.getpos(".")
		local start_row = start[2]
		local start_col = start[3]
		local end_row = end_[2]
		local end_col = end_[3]

		-- A user can start visual selection at the end and move backwards
		-- Normalize the range to start < end
		if start_row == end_row and end_col < start_col then
			end_col, start_col = start_col, end_col
		elseif end_row < start_row then
			start_row, end_row = end_row, start_row
			start_col, end_col = end_col, start_col
		end
		params = lsp.util.make_given_range_params({ start_row, start_col - 1 }, { end_row, end_col - 1 })
	else
		params = lsp.util.make_range_params()
	end
	local current_buffer = api.nvim_get_current_buf()
	local diagnostics = util.diagnostic_vim_to_lsp(vim.diagnostic.get(current_buffer, {
		lnum = fn.line(".") - 1,
	}))
	params.context = { diagnostics = diagnostics }
	local ctx = { bufnr = current_buffer, method = method, params = params }
	lsp.buf_request_all(current_buffer, method, params, function(results)
		local actions = {}
		for client_id, result in pairs(results) do
			for _, action in pairs(result.result or {}) do
				table.insert(actions, { id = client_id, action = action })
			end
		end
		if #actions == 0 then
			lib.log.Info("Non available actions!")
			return
		end
		local new_buffer, win_id = render.action_render(actions)
		lib.util.Disable_move_keys(new_buffer)
		util.Lock_cursor(new_buffer, win_id, #actions)

		util.Keybinding(new_buffer, win_id, actions, ctx)
	end)
end

return M
