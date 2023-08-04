local M = {}

-- this function is for debug
-- it will print all information
--- @param ... any
M.debug = function(...)
	local date = os.date("%Y-%m-%d %H:%M:%S")
	local args = { ... }
	for _, value in pairs(args) do
		print(date, vim.inspect(value))
	end
end

return M
