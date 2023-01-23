local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}
local util = require("LspUI.rename.util")

M.init = function()
	if not config.rename.enable then
		return
	end
end

M.run = function()
	if not config.rename.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end

	-- get current buffer and win
	local current_buffer = api.nvim_get_current_buf()
	local current_win = api.nvim_get_current_win()

	local clients = util.Get_clients(current_buffer)
	if vim.tbl_isempty(clients) then
		lib.log.Info("No available rename lsp")
		return
	end

	-- this function may need two param, but second param is optional
	local params = lsp.util.make_position_params(current_win)

	local cword = vim.fn.expand("<cword>")

	local content_wrap = {
		contents = { cword },
		filetype = "lspui_rename",
		enter = true,
		modify = true,
		height = 1,
		width = 20,
	}

	local new_buffer, win_id = lib.windows.Create_window(content_wrap)

	if config.rename.auto_select then
		vim.cmd([[normal! V]])
		util.Feedkeys("<C-g>", "n")
	end

	-- keybind
	vim.keymap.set({ "n", "v", "i" }, config.rename.keybind.change, function()
		local new_name = vim.trim(api.nvim_get_current_line())
		util.Close_window(win_id)
		if cword ~= new_name then
			util.Do_rename(params, clients, current_buffer, new_name)
		end
	end, { buffer = new_buffer })

	vim.keymap.set({ "n" }, config.rename.keybind.quit, function()
		util.Close_window(win_id)
	end, { buffer = new_buffer })

	-- autocmd
	api.nvim_create_autocmd("WinLeave", {
		buffer = new_buffer,
		once = true,
		callback = function(arg)
			util.Close_window(win_id)
		end,
		desc = lib.Command_des("Rename auto close windows when WinLeave"),
	})
end

return M
