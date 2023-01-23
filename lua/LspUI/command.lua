local lsp, fn, api = vim.lsp, vim.fn, vim.api
local M = {}

local lib = require("LspUI.lib")
local config = require("LspUI.config")
local modules = require("LspUI.modules")

local Commands = {
	definition = {
		run = nil,
		args = {},
	},
	code_action = {
		run = modules.code_action.run,
		args = {},
	},
	hover = {
		run = modules.hover.run,
		args = {},
	},
	reference = {
		run = nil,
		args = {},
	},
	rename = {
		run = modules.rename.run,
		args = {},
	},
	diagnostic = {
		run = nil,
		args = {
			"next",
			"prev",
		},
	},
	lightbulb = {
		run = modules.lighthub.run,
		args = {},
	},
}
local function keys()
	local res = {}
	local command_list = vim.tbl_keys(Commands)
	for _, key in pairs(command_list) do
		if not lib.util.Tb_has_key(config, key) then
			goto continue
		end
		if config[key].enable and lib.util.Tb_has_key(config[key], "command_enable") and config[key].command_enable then
			table.insert(res, key)
		end
		::continue::
	end
	return res
end

local function call()
	lib.log.Info("Hello, version: " .. config.version())
end

local function run(key, arg)
	if key == nil then
		call()
	else
		pcall(Commands[key].run, arg)
	end
end

M.init = function()
	api.nvim_create_user_command("LspUI", function(args)
		run(unpack(args.fargs))
	end, {
		range = true,
		nargs = "*",
		complete = function(arg, cmdLine, pos)
			local cmd = fn.split(cmdLine)
			local key_list = keys()
			if #cmd <= 1 then
				return key_list
			end

			if not lib.util.Tb_has_value(key_list, cmd[2]) then
				return {}
			end

			return Commands[cmd[2]].args
		end,
	})
end

return M
