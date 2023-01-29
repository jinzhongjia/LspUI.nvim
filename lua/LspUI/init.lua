local lib = require("LspUI.lib")
local config = require("LspUI.config")
local command = require("LspUI.command")
local M = {}

local modules = require("LspUI.modules")

local initialized = false

local function init()
	command.init()
	for _, module in pairs(modules) do
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
