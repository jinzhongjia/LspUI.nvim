local api, fn, lsp = vim.api, vim.fn, vim.lsp
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local util = require("LspUI.rename.util")
local windows = require("LspUI.lib.windows")
local command = require("LspUI.command")

local M = {}

-- whether this module has initialized
local is_initialized = false

-- init for the rename
M.init = function()
	if not config.options.rename.enable then
		return
	end

	if is_initialized then
		return
	end

	is_initialized = true

	-- register command
	if config.options.rename.command_enable then
		command.register_command("rename", M.run, {})
	end
end

-- run of rename
M.run = function()
	if not config.options.rename.enable then
		lib_notify.Info("rename is not enabled!")
		return
	end

	local current_buffer = api.nvim_get_current_buf()
	local clients = util.get_clients(current_buffer)
	if clients == nil then
		-- if no valid client, step into here
		return
	end

	local current_win = api.nvim_get_current_win()

	local old_name = fn.expand("<cword>")

	-- TODO: this func maybe should not pass win id ?
	local position_param = lsp.util.make_position_params(current_win)

	-- Here we need to define window

	local new_buffer = api.nvim_create_buf(false, true)

	-- note: this must set before modifiable, when modifiable is false, this function will fail
	api.nvim_buf_set_lines(new_buffer, 0, -1, false, { old_name })
	api.nvim_buf_set_option(new_buffer, "filetype", "LspUI-rename")
	api.nvim_buf_set_option(new_buffer, "modifiable", true)
	api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

	local new_window_wrap = windows.new_window(new_buffer)

	windows.set_width_window(new_window_wrap, fn.strcharlen(old_name) + 3)
	windows.set_height_window(new_window_wrap, 1)
	windows.set_enter_window(new_window_wrap, true)
	windows.set_anchor_window(new_window_wrap, "NW")
	windows.set_border_window(new_window_wrap, "rounded")
	windows.set_focusable_window(new_window_wrap, true)
	windows.set_relative_window(new_window_wrap, "cursor")
	windows.set_col_window(new_window_wrap, 1)
	windows.set_row_window(new_window_wrap, 1)
	windows.set_style_window(new_window_wrap, "minimal")

	local window_id = windows.display_window(new_window_wrap)

	api.nvim_win_set_option(window_id, "winhighlight", "Normal:Normal")

	if config.options.rename.auto_select then
		vim.cmd([[normal! V]])
		api.nvim_feedkeys(api.nvim_replace_termcodes("<C-g>", true, true, true), "n", true)
	end

	-- keybinding and autocommand
	util.keybinding_autocmd(window_id, old_name, clients, current_buffer, new_buffer, position_param)
end

return M
