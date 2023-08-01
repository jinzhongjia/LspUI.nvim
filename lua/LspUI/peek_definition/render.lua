local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local keybind = require("LspUI.peek_definition.keybind")

M.render = function(uri, range)
	-- if uri is nil, the file not exist
	if not uri then
		return
	end

	-- create a buffer from uri
	local buffer = vim.uri_to_bufnr(uri)
	-- get file name from uri
	local filename = vim.uri_to_fname(uri)

	-- load the buffer
	if not vim.api.nvim_buf_is_loaded(buffer) then
		fn.bufload(buffer)
	end

	local start_line = range.start.line
	local start_char_pos = range.start.character
	local end_char_pos = range["end"].character
	local end_line = range["end"].line

	local max_width = math.floor(lib.windows.Get_max_float_width() * 0.75)
	local max_height = math.floor(lib.windows.Get_max_float_height() * 0.75)

	local content_wrap = {
		buffer = buffer,
		width = max_width,
		height = max_height,
		modify = true,
		enter = true,
		title = filename,
	}

	local _, win_id = lib.windows.Create_window(content_wrap)

	-- set variable to windows for lightbulb will not render in this
	api.nvim_win_set_var(win_id, lib.store.lsp_define, true)
	api.nvim_win_set_cursor(win_id, { start_line + 1, start_char_pos })

	vim.cmd("normal! zt")

	keybind.keybind(buffer, win_id, filename, start_line, start_char_pos)
end

return M
