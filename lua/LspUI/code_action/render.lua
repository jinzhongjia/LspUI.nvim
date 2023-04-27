local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.action_render = function(actions)
	local contents = {}
	local title = config.option.code_action.icon .. " CodeActions:"
	table.insert(contents, title)

	for index, client_with_actions in pairs(actions) do
		local action_title = ""
		if client_with_actions.action.title then
			action_title = "[" .. index .. "]" .. " " .. client_with_actions.action.title
		end
		table.insert(contents, action_title)
	end

	if #contents == 1 then
		return
	end
	local truncate_line = lib.wrap.Make_truncate_line(contents)
	table.insert(contents, 2, truncate_line)
	local content_wrap = {
		contents = contents,
		filetype = "Lspui_code_action",
		enter = true,
		modify = false,
	}

	local new_buffer, win_id = lib.windows.Create_window(content_wrap)
	api.nvim_win_set_cursor(win_id, { 3, 1 })
	return new_buffer, win_id
end

return M
