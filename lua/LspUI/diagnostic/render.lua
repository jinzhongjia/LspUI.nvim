local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}
local util = require("LspUI.diagnostic.util")
local auto_cmd = require("LspUI.diagnostic.auto_cmd")

M.virtual_render = function(diagnostic)
	local highlight_arr = {}

	-- get the string of severity
	local severity = util.severity(diagnostic.severity)

	-- create the header of contents
	local header_left = config.option.diagnostic.icons[severity] .. severity

	table.insert(highlight_arr, {
		line = 0,
		start_col = #header_left + 1,
		end_col = -1,
	})

	local header_right = " in "
		.. "❮"
		.. tostring(diagnostic.lnum + 1)
		.. ":"
		.. tostring(diagnostic.col + 1)
		.. "❯"

	local header = header_left .. header_right

	local body_left = vim.tbl_filter(function(s)
		return string.len(s) ~= 0
	end, vim.split(diagnostic.message, "\n"))

	local body_right = diagnostic.source .. "(" .. diagnostic.code .. ")"

	local max_width = lib.windows.Get_max_float_width()

	for key, value in pairs(body_left) do
		if fn.strwidth(value) > max_width then
			-- here is table
			local res = lib.wrap.Wrap(value, max_width)
			table.remove(body_left, key)
			for index, val in pairs(res) do
				table.insert(body_left, key + index - 1)
			end
		end
	end

	local body_left_bottom = body_left[#body_left]

	if fn.strwidth(body_left_bottom .. body_right) > max_width then
		local new_line = " "
		for i = 1, max_width - fn.strwidth(body_right), 1 do
			new_line = new_line .. " "
		end
		new_line = new_line .. body_right
		table.insert(body_left, new_line)
		table.insert(highlight_arr, {
			line = #body_left + 1,
			start_col = 1,
			end_col = -1,
		})
	else
		table.insert(highlight_arr, {
			line = #body_left + 1,
			start_col = #(body_left[#body_left] .. " "),
			end_col = -1,
		})
		body_left[#body_left] = body_left[#body_left] .. " " .. body_right
	end

	-- create the body of contents
	local body = body_left

	local contents = {
		header,
	}

	for key, value in pairs(body) do
		table.insert(contents, value)
	end

	local truncate_line = lib.wrap.Make_truncate_line(contents)
	table.insert(contents, 2, truncate_line)

	return contents,
		{
			hl_name = util.highlight_name(diagnostic.severity),
			height = #contents,
			hl_arr = highlight_arr,
		}
end

M.display = function(diagnostic)
	local current_buffer = api.nvim_get_current_buf()

	local contents, hl_wrap = M.virtual_render(diagnostic)

	lib.windows.Move_cursor(0, diagnostic.lnum + 1, diagnostic.col)

	local new_buffer, win_id = lib.windows.Create_window({
		contents = contents,
		filetype = "Lspui-diagnostic",
		modify = false,
		enter = false,
		title = "1/1",
		title_pos = "right",
	})

	util.highlight(new_buffer, hl_wrap)
	vim.schedule(function()
		auto_cmd.autocmd(current_buffer, win_id)
	end)
end

return M
