local lsp, fn, api = vim.lsp, vim.fn, vim.api

local config = require("LspUI.config")

local M = {}

local log = require("LspUI.lib.log")

local key_bind_opt = { nowait = true, noremap = true, silent = true }
local move_keys = { "h", "ge", "e", "0", "$", "l", "w", "b", "<Bs>", "j", "k", "<Left>", "<Right>", "<Up>", "<Down>" }
local other_keys = { "x", "y", "v", "o", "O", "q" }

M.Merge_config = function(param)
	config.option = vim.tbl_deep_extend("force", config.option, param)
end

M.Tb_has_key = function(tb, val)
	for key, _ in pairs(tb) do
		if key == val then
			return true
		end
	end
	return false
end

M.Tb_remove_value = function(tb, val)
	for key, value in pairs(tb) do
		if value == val then
			tb[key] = nil
			return
		end
	end
end

M.Tb_has_value = function(tb, val)
	if type(tb) == "table" then
		for _, v in pairs(tb) do
			if v == val then
				return true
			end
		end
	elseif type(tb) == "string" then
		if tb == val then
			return true
		end
	end
end

M.Disable_move_keys = function(buffer)
	for _, key in pairs(move_keys) do
		api.nvim_buf_set_keymap(buffer, "n", key, "", key_bind_opt)
	end
	for _, key in pairs(other_keys) do
		api.nvim_buf_set_keymap(buffer, "n", key, "", key_bind_opt)
	end
end

M.Command_des = function(des)
	return "[LspUI]: " .. des
end

M.Remove_empty_line = function(contents)
	local new_contents = {}
	for key, value in pairs(contents) do
		if #value ~= 0 then
			table.insert(new_contents, value)
		end
	end
	return new_contents
end

local function getBytes(char)
	if not char then
		return 0
	end
	local code = string.byte(char)
	if code < 127 then
		return 1
	elseif code <= 223 then
		return 2
	elseif code <= 239 then
		return 3
	elseif code <= 247 then
		return 4
	else
		return 0
	end
end

M.Sub = function(str, startIndex, endIndex)
	local tempStr = str
	local byteStart = 1 -- string.sub截取的开始位置
	local byteEnd = -1 -- string.sub截取的结束位置
	local index = 0 -- 字符记数
	local bytes = 0 -- 字符的字节记数

	startIndex = math.max(startIndex, 1)
	endIndex = endIndex or -1
	while string.len(tempStr) > 0 do
		if index == startIndex - 1 then
			byteStart = bytes + 1
		elseif index == endIndex then
			byteEnd = bytes
			break
		end
		bytes = bytes + getBytes(tempStr)
		tempStr = string.sub(str, bytes + 1)

		index = index + 1
	end
	return string.sub(str, byteStart, byteEnd)
end

M.debug = function(...)
	local date = os.date("%Y-%m-%d %H:%M:%S")
	local args = { ... }
	for _, value in pairs(args) do
		print(date, vim.inspect(value))
	end
end

return M
