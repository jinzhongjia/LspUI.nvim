local lib = require("LspUI.lib")
local config = require("LspUI.config")
local command = require("LspUI.command")
local modules = require("LspUI.modules")
local api = require("LspUI.api")

local M = {}

local initialized = false

local function init()
	for _, module in pairs(modules) do
		module.init()
	end
	command.init()
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

M.api = api.api

return M
