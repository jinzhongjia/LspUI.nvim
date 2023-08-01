local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.Handle_content = function(new_buffer, content)
	local contents = lsp.util.trim_empty_lines(lsp.util.convert_input_to_markdown_lines(content))

	local opt = {
		wrap = true,
		wrap_at = lib.windows.Get_max_float_width(),
		max_width = lib.windows.Get_max_float_width(),
		width = lib.windows.Get_max_float_width(),
	}

	contents = lsp.util.stylize_markdown(new_buffer, contents, opt)

	local width, height = lib.windows.Min_size_from_content(contents)

	local max_float_width = lib.windows.Get_max_float_width()
	if width > max_float_width then
		width = max_float_width
	end

	return width, height, contents
end

M.Update_win = function(new_buffer, hover_win_id, content_list, content_id)
	api.nvim_buf_set_option(new_buffer, "modifiable", true)
	local new_width, new_height, content = M.Handle_content(new_buffer, content_list[content_id])

	content = lib.wrap.Wrap(content, new_width)

	new_width, new_height = lib.windows.Min_size_from_content(content)

	api.nvim_buf_set_option(new_buffer, "modifiable", false)
	local win_config = {
		width = new_width,
		height = new_height,
		title = tostring(content_id) .. "/" .. tostring(#content_list),
		title_pos = "right",
	}
	api.nvim_win_set_config(hover_win_id, win_config)
	api.nvim_win_set_option(hover_win_id, "conceallevel", 2)
	api.nvim_win_set_option(hover_win_id, "concealcursor", "n")
	api.nvim_win_set_option(hover_win_id, "wrap", false)
end

return M
