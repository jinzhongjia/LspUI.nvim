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
            -- 修改：传递所有参数
            local ok, err = pcall(command_store[key].run, unpack(cmd_args))
            if not ok then
                notify.Error(
                    string.format(
                        "Command %s failed: %s",
                        key,
                        err or "unknown error"
                    )
                )
            end
        else
            notify.Warn(string.format("command %s not exist!", key))
        end
    end, {
        nargs = "*",
        desc = "LspUI commands",
        complete = function(ArgLead, CmdLine, CursorPos)
            local args = vim.split(CmdLine, "%s+")
            local n = #args

            -- 如果只有一个参数 (LspUI 命令本身)，或者第二个参数正在被补全
            if n <= 1 or (n == 2 and CmdLine:match("%s+$")) then
                local result = {}
                for cmd, _ in pairs(command_store) do
                    if ArgLead == "" or cmd:find(ArgLead, 1, true) then
                        table.insert(result, cmd)
                    end
                end
                table.sort(result)
                return result
            -- 如果已经输入了子命令，并且该子命令有定义补全选项
            elseif n >= 2 then
                local subcmd = args[2]
                if command_store[subcmd] and command_store[subcmd].args then
                    local completes = command_store[subcmd].args
                    if type(completes) == "function" then
                        return completes(ArgLead, CmdLine, CursorPos)
                    elseif type(completes) == "table" then
                        local result = {}
                        local current_arg = args[n]
                        for _, v in ipairs(completes) do
                            if
                                current_arg == ""
                                or v:find(current_arg, 1, true)
                            then
                                table.insert(result, v)
                            end
                        end
                        return result
                    end
                end
                return {}
            end

            return {}
        end,
    })
end

-- register command
--- @param command_key string
--- @param run function
--- @param args string[]|function
M.register_command = function(command_key, run, args)
    command_store[command_key] = { run = run, args = args }
end

-- unregister command
--- @param command_key string
M.unregister_command = function(command_key)
    command_store[command_key] = nil
end

return M
