local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local request = require("LspUI.hover.request")

local method = "textDocument/hover"

M.init = function()
	if not config.hover.enable then
		return
	end

	if not lib.lsp.Check_lsp_active() then
		return
	end
end

local function document_handle(contents)
	local new_contents = {}
	local markdown_line = lsp.util.convert_input_to_markdown_lines(contents)
	markdown_line = lsp.util.trim_empty_lines(markdown_line)
	new_contents = markdown_line

	return new_contents
end

M.run = function()
	if not config.hover.enable then
		return
	end

	if not lib.lsp.Check_lsp_active() then
		return
	end

	request.Request(function(res)
		local contents = document_handle(res)
		if vim.tbl_isempty(contents) then
			lib.Info("No hover document!")
			return
		end
		local current_buffer = api.nvim_get_current_buf()
		local new_buffer = api.nvim_create_buf(false, true)

		contents = lsp.util.stylize_markdown(new_buffer, contents)

		local width, height = lib.windows.Min_size_from_content(contents)

		local content_wrap = {
			contents = contents,
			buffer = new_buffer,
			height = height,
			width = width,
			enter = false,
			modify = false,
		}
		local _, win_id = lib.windows.Create_window(content_wrap)
		lib.util.debug(content_wrap)
		api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufHidden" }, {
			buffer = current_buffer,
			callback = function(arg)
				api.nvim_win_close(win_id, true)
				api.nvim_del_autocmd(arg.id)
			end,
			desc = lib.util.Command_des("Auto close hover document when current windows cursor move"),
		})
	end)
end

return M
