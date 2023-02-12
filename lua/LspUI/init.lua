local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local initialized = false

local function init()
	require("LspUI.command").init()
	for _, module in pairs(require("LspUI.modules")) do
		module.init()
	end
end

M.setup = function(opt)
	if initialized then
		return
	end
	opt = opt or {}
	lib.util.Merge_config(opt)
	init()
	initialized = true
end

return M
