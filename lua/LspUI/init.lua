local lib = require("LspUI.lib")
local config = require("LspUI.config")
local command = require("LspUI.command")
local M = {}

local modules = require("LspUI.modules")

local function init()
	command.init()
	for _, module in pairs(modules) do
		module.init()
	end
end

M.setup = function(opt)
	opt = opt or {}
	lib.util.Merge_config(config, opt)
	init()
end

return M
