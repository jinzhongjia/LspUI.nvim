local api, fn = vim.api, vim.fn
local lib_windows = require("LspUI.lib.windows")
local M = {}

-- convert severity to string
--- @param severity integer
--- @return string?
local diagnostic_severity_to_string = function(severity)
	local arr = {
		"Error",
		"Warn",
		"Info",
		"Hint",
	}
	return arr[severity] or nil
end

-- generate title
--- @param severity integer
--- @param lnum integer
--- @param col integer
--- @param source string?
--- @return string?
local generate_title = function(width, severity, lnum, col, source)
	local severity_string = diagnostic_severity_to_string(severity)
	if severity_string == nil then
		return nil
	end
	--- @type string
	local title_left = string.format("%s ❮%d:%d❯", severity_string, lnum + 1, col + 1)
	if source == nil then
		return nil
	end
	--- @type string
	local title_right = source

	--- @type string
	local title = string.format("%s %s", title_left, title_right)

	return title
end

-- render the float window
--- @param diagnostic Diagnostic?
M.render = function(diagnostic)
	if diagnostic == nil then
		return
	end
end

return M
