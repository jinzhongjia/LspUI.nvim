local api = vim.api
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

local M = {}

--- @type table<string, { run: function, args: string[]|function|nil }>
local command_store = {}

--- @type string[]|nil cached sorted command names
local sorted_commands_cache = nil

--- Invalidate the sorted commands cache
local function invalidate_cache()
    sorted_commands_cache = nil
end

--- Get sorted command names (cached)
--- @return string[]
local function get_sorted_commands()
    if not sorted_commands_cache then
        sorted_commands_cache = vim.tbl_keys(command_store)
        table.sort(sorted_commands_cache)
    end
    return sorted_commands_cache
end

--- Filter list by prefix
--- @param list string[]
--- @param prefix string
--- @return string[]
local function filter_by_prefix(list, prefix)
    if prefix == "" then
        return list
    end
    local result = {}
    for _, item in ipairs(list) do
        if item:find(prefix, 1, true) == 1 then
            table.insert(result, item)
        end
    end
    return result
end

--- Complete function for LspUI command
--- @param arg_lead string
--- @param cmd_line string
--- @param cursor_pos integer
--- @return string[]
local function complete(arg_lead, cmd_line, cursor_pos)
    -- Parse command line: "LspUI subcmd arg1 arg2..."
    local parts = vim.split(cmd_line, "%s+", { trimempty = false })
    -- parts[1] = "LspUI", parts[2] = subcmd, parts[3+] = args

    -- Completing subcommand
    if #parts <= 2 then
        return filter_by_prefix(get_sorted_commands(), arg_lead)
    end

    -- Completing subcommand arguments
    local subcmd = parts[2]
    local cmd_entry = command_store[subcmd]
    if not cmd_entry or not cmd_entry.args then
        return {}
    end

    local completes = cmd_entry.args
    if type(completes) == "function" then
        return completes(arg_lead, cmd_line, cursor_pos) or {}
    elseif type(completes) == "table" then
        return filter_by_prefix(completes, arg_lead)
    end

    return {}
end

--- Initialize the command module
function M.init()
    api.nvim_create_user_command("LspUI", function(args)
        local fargs = args.fargs
        local key = fargs[1]

        if not key then
            notify.Info(string.format("LspUI version %s", tools.version()))
            return
        end

        local cmd_entry = command_store[key]
        if not cmd_entry then
            notify.Warn(string.format("Unknown command: %s", key))
            return
        end

        -- Pass remaining arguments to the command (LuaJIT uses unpack)
        local cmd_args = { unpack(fargs, 2) }
        local ok, err = pcall(cmd_entry.run, unpack(cmd_args))
        if not ok then
            notify.Error(
                string.format(
                    "Command '%s' failed: %s",
                    key,
                    err or "unknown error"
                )
            )
        end
    end, {
        nargs = "*",
        desc = "LspUI commands",
        complete = complete,
    })
end

--- Register a command
--- @param command_key string
--- @param run function
--- @param args string[]|function|nil
function M.register_command(command_key, run, args)
    command_store[command_key] = { run = run, args = args }
    invalidate_cache()
end

--- Unregister a command
--- @param command_key string
function M.unregister_command(command_key)
    command_store[command_key] = nil
    invalidate_cache()
end

return M
