local lsp, api, fn = vim.lsp, vim.api, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local lib_notify = require("LspUI.lib.notify")
local lib_windows = require("LspUI.lib.windows")
local lib_util = require("LspUI.lib.util")

--- @alias hover_tuple { client: lsp.Client, buffer_id: integer, contents: string[], width: integer, height: integer }

local M = {}

-- get all valid clients for hover
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
	local clients = lsp.get_clients({ bufnr = buffer_id, method = hover_feature })
	return #clients == 0 and nil or clients
end

-- get hovers from lsp
--- @param clients lsp.Client[]
--- @param buffer_id integer
--- @param callback function this callback has a param is hover_tuples[]
M.get_hovers = function(clients, buffer_id, callback)
	--- @type hover_tuple[]
	local hover_tuples = {}
	local params = lsp.util.make_position_params()
	local tmp_number = 0

	for _, client in pairs(clients) do
		client.request(
			hover_feature,
			params,
			---@param result lsp.Hover
			---@param config any
			function(_, result, _, config)
				config = config or {}

				if not (result and result.contents) then
					if config.silent ~= true then
						lib_notify.Warn(string.format("No valid hover, %s", client.name))
					end
					return
				end

				local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
				markdown_lines = lsp.util.trim_empty_lines(markdown_lines)

				if vim.tbl_isempty(markdown_lines) then
					if config.silent ~= true then
						lib_notify.Warn(string.format("No valid hover, %s", client.name))
					end
					return
				end

				local new_buffer = api.nvim_create_buf(false, true)

				markdown_lines = lsp.util.stylize_markdown(
					new_buffer,
					markdown_lines,
					{ max_width = lib_windows.get_max_width() * 0.6 }
				)

				local max_width = 0

				for _, line in pairs(markdown_lines) do
					max_width = math.max(fn.strdisplaywidth(line), max_width)
				end
				-- note: don't change filetype, this will cause syntx failing
				-- api.nvim_buf_set_option(new_buffer, "filetype", "LspUI-hover")
				api.nvim_buf_set_option(new_buffer, "modifiable", false)
				api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

				local width = math.min(max_width, math.floor(lib_windows.get_max_width() * 0.6))

				local height = lib_windows.compute_height_for_windows(markdown_lines, width)

				table.insert(
					hover_tuples,
					--- @type hover_tuple
					{
						client = client,
						buffer_id = new_buffer,
						contents = markdown_lines,
						width = width,
						height = height,
					}
				)

				tmp_number = tmp_number + 1

				if tmp_number == #clients then
					callback(hover_tuples)
				end
			end,
			buffer_id
		)
	end
end

-- render hover
--- @param hover_tuple hover_tuple
--- @return integer window_id window's id
M.base_render = function(hover_tuple)
	local new_window_wrap = lib_windows.new_window(hover_tuple.buffer_id)

	lib_windows.set_width_window(new_window_wrap, hover_tuple.width)
	lib_windows.set_height_window(new_window_wrap, hover_tuple.height)
	lib_windows.set_enter_window(new_window_wrap, false)
	lib_windows.set_anchor_window(new_window_wrap, "NW")
	lib_windows.set_border_window(new_window_wrap, "rounded")
	lib_windows.set_focusable_window(new_window_wrap, true)
	lib_windows.set_relative_window(new_window_wrap, "cursor")
	lib_windows.set_col_window(new_window_wrap, 1)
	lib_windows.set_row_window(new_window_wrap, 1)
	lib_windows.set_style_window(new_window_wrap, "minimal")
	lib_windows.set_right_title_window(new_window_wrap, "hover")

	local window_id = lib_windows.display_window(new_window_wrap)

	api.nvim_win_set_option(window_id, "winhighlight", "Normal:Normal")
	api.nvim_win_set_option(window_id, "wrap", true)
	-- this is very very important, because it will hide highlight group
	api.nvim_win_set_option(window_id, "conceallevel", 2)
	api.nvim_win_set_option(window_id, "concealcursor", "n")

	return window_id
end

--- audo for hover
--- this must be called in vim.schedule
--- @param current_buffer integer current buffer id, not float window's buffer id'
--- @param window_id integer  float window's id
M.autocmd = function(current_buffer, window_id)
	api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufDelete" }, {
		buffer = current_buffer,
		callback = function(arg)
			lib_windows.close_window(window_id)
			api.nvim_del_autocmd(arg.id)
		end,
		desc = lib_util.command_desc("auto close hover when cursor moves"),
	})
end

return M
