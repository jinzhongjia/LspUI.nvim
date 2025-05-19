local api, fn = vim.api, vim.fn
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

local command_store = {}
local M = {}

-- init for the command
M.init = function()
    api.nvim_create_user_command("LspUI", function(args)
        local key = args.fargs[1]
        local cmd_args = { unpack(args.fargs, 2) }

        if not key then
            -- default function when command `LspUI` executes without args
            notify.Info(string.format("Hello, version is %s", tools.version()))
            return
        end

        if command_store[key] then
            pcall(command_store[key].run, cmd_args)
        else
            notify.Warn(string.format("command %s not exist!", key))
        end
    end, {
        range = true,
        nargs = "*",
        complete = function(_, cmdline, _)
            local cmd = fn.split(cmdline)

            if #cmd <= 1 then
                return vim.tbl_keys(command_store)
            end

            local args = vim.tbl_get(command_store, cmd[2], "args")
            return args or {}
        end,
    })
end

-- register command
--- @param command_key string
--- @param run function
--- @param args string[]
M.register_command = function(command_key, run, args)
    command_store[command_key] = { run = run, args = args }
end

-- unregister command
--- @param command_key string
M.unregister_command = function(command_key)
    command_store[command_key] = nil
end

return M
