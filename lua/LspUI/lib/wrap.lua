local lsp, fn, api = vim.lsp, vim.fn, vim.api
local config = require("LspUI.config")

local M = {}

local function wrap_text(text, width)
	local res = {}
	local display_width = fn.strwidth(text)
	if display_width < width then
		table.insert(res, text)
		return res
	end
	table.insert(res, string.sub(text, 1, width))
	local rest = wrap_text(string.sub(text, width, -1), width)
	for _, val in pairs(rest) do
		table.insert(res, val)
	end
	return res
end

M.Wrap = function(contents, width)
	local res = {}
	for _, content in pairs(contents) do
		local display_width = vim.fn.strwidth(content)
		if display_width > width then
			local texts = wrap_text(content, width)
			for _, value in pairs(texts) do
				table.insert(res, value)
			end
		else
			table.insert(res, content)
		end
	end
	return res
end

M.Make_truncate_line = function(contents)
	local width = 0
	local char = "─"
	local truncate_line = char

	for _, line in ipairs(contents) do
		local line_width = vim.fn.strwidth(line)
		width = math.max(line_width, width)
	end

	for _ = 1, width, 1 do
		truncate_line = truncate_line .. char
	end

	return truncate_line
end

return M
