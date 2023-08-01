local lsp, fn, api = vim.lsp, vim.fn, vim.api
local config = require("LspUI.config")

-- now, border just is single

local M = {}

local util = require("LspUI.lib.util")

M.MAX_WIDTH = api.nvim_get_option("columns")

M.MAX_HEIGHT = api.nvim_get_option("lines")

-- get the min width and height of contents
M.Min_size_from_content = function(contents)
	local width, height = 0, 0
	for _, content in pairs(contents) do
		width = math.max(vim.fn.strwidth(content), width)
		height = height + 1
	end
	return width, height
end

M.Create_window = function(contents_wrap)
	local contents = contents_wrap.contents or {}
	local filetype = contents_wrap.filetype or nil
	local enter = contents_wrap.enter or false

	if (not contents_wrap.width) or not contents_wrap.height then
		contents_wrap.width, contents_wrap.height = M.Min_size_from_content(contents_wrap.contents)
	end

	local new_buffer = contents_wrap.buffer or api.nvim_create_buf(false, true)

	if not vim.tbl_isempty(contents) then
		api.nvim_buf_set_lines(new_buffer, 0, -1, true, contents)
	end

	if filetype then
		api.nvim_buf_set_option(new_buffer, "filetype", filetype)
	end

	api.nvim_buf_set_option(new_buffer, "modifiable", contents_wrap.modify or false)
	api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

	local opt = {
		anchor = "NW",
		border = "rounded",
		focusable = true,
		relative = "cursor",
		col = 1,
		row = 1,
		style = "minimal",
		width = contents_wrap.width,
		-- TODO: here we should define a variable in config, so that we can custom
		height = contents_wrap.height > math.floor(M.MAX_HEIGHT * 0.8) and math.floor(M.MAX_HEIGHT * 0.8)
			or contents_wrap.height,
		zindex = contents_wrap.zindex,
	}

	-- TODO: when stable is 0.9, remove this!!!
	-- remain this!!!
	if fn.has("nvim-0.9") == 1 then
		opt.title = contents_wrap.title or ""
		opt.title_pos = contents_wrap.title_pos or "right"
	end

	local win_id = api.nvim_open_win(new_buffer, enter, opt)
	api.nvim_win_set_option(win_id, "winhighlight", "Normal:Normal")

	return new_buffer, win_id
end

-- move cursor and save position in jumplist
M.Move_cursor = function(winid, line, col)
	api.nvim_win_set_cursor(0, { line, col })

	vim.api.nvim_win_call(winid, function()
		-- Save position in the window's jumplist
		vim.cmd("normal! m'")
		api.nvim_win_set_cursor(winid, { line, col })
		-- Open folds under the cursor
		vim.cmd("normal! zv")
	end)
end

-- useless
M.Resize_window = function(win_id, size)
	if size.height then
		api.nvim_win_set_height(win_id or 0, size.height)
	end
	if size.width then
		api.nvim_win_set_width(win_id or 0, size.width)
	end
end

M.Get_max_float_width = function()
	local max_width = math.floor(M.MAX_WIDTH * 0.7)
	return max_width
end

M.Get_max_float_height = function()
	local max_height = math.floor(M.MAX_HEIGHT * 0.7)
	return max_height
end

return M
