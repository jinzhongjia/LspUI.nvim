local lsp, fn, api = vim.lsp, vim.fn, vim.api
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction

local code_action_register = require("LspUI.code_action.register")
local config = require("LspUI.config")
local global = require("LspUI.global")
local lib_lsp = require("LspUI.lib.lsp")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")

local M = {}

local autogroup_name = "Lspui_lightBulb"

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = code_action_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- render sign
--- @param buffer_id integer buffer's id
--- @param line integer the line number, and this will be set as sign id
--- @return integer? sign_identifier sign's identifier, -1 means failing
function M.render(buffer_id, line)
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    return fn.sign_place(
        line,
        global.lightbulb.sign_group,
        global.lightbulb.sign_name,
        buffer_id,
        {
            lnum = line,
        }
    )
end

-- clear sign
function M.clear_render()
    -- TODO:Do you need to add pcall here???
    fn.sign_unplace(global.lightbulb.sign_group)
end

-- register the sign
-- note: this func only can be called once!
function M.register_sign()
    fn.sign_define(
        global.lightbulb.sign_name,
        { text = config.options.lightbulb.icon }
    )
end

-- unregister the sign
function M.unregister_sign()
    fn.sign_undefine(global.lightbulb.sign_name)
end

-- this function will request all lsp clients
--- @param buffer_id integer buffer's id
--- @param callback function callback is a function, has a param boolean
function M.request(buffer_id, callback)
    -- this buffer id maybe invalid
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end
    -- when switch buffer too quickly, window will be not correct
    -- maybe this problem is caused by neovim event loop
    if buffer_id ~= api.nvim_win_get_buf(api.nvim_get_current_win()) then
        return
    end
    local params = lsp.util.make_range_params()
    local context = {
        triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
        diagnostics = lib_lsp.diagnostic_vim_to_lsp(
            vim.diagnostic.get(buffer_id, {
                lnum = fn.line(".") - 1,
            })
        ),
    }
    params.context = context

    -- reduce a little calculations
    local __callback = lib_util.exec_once(callback)

    -- here will Check for new content
    -- TODO: maybe we can add more integreation
    if config.options.code_action.gitsigns then
        local status, gitsigns = pcall(require, "gitsigns")
        if not status then
            goto _continue
        end
        local gitsigns_actions = gitsigns.get_actions()
        if gitsigns_actions and not vim.tbl_isempty(gitsigns_actions) then
            __callback(true)
            return
        end
        ::_continue::
    end

    -- stylua: ignore
    local register_res =code_action_register.handle(params.textDocument.uri, params.range)

    if not vim.tbl_isempty(register_res) then
        __callback(true)
        return
    end

    local clients = M.get_clients(buffer_id)
    local tmp_number = 0

    for _, client in pairs(clients or {}) do
        local _tmp = function(err, result, _, _)
            tmp_number = tmp_number + 1

            if
                err == nil
                and result
                and type(result) == "table"
                and not vim.tbl_isempty(result)
            then
                __callback(true)
                return
            end

            if err ~= nil then
                lib_notify.Warn(
                    string.format(
                        "lightbulb meet error, server %s, error code is %d, msg is %s",
                        client.name,
                        err.code,
                        err.message
                    )
                )
            end

            if tmp_number == #clients then
                __callback(false)
            end
        end
        client.request(code_action_feature, params, _tmp, buffer_id)
    end
end

local function debounce_func(buffer_id)
    local _rq_cb = function(result)
        M.clear_render()
        if result then
            local line = fn.line(".")
            if line == nil then
                return
            end
            M.render(buffer_id, line)
        end
    end

    local func = function()
        M.request(buffer_id, _rq_cb)
    end

    if not config.options.lightbulb.debounce then
        return func
    elseif config.options.lightbulb.debounce == true then
        return lib_util.debounce(func, 250)
    end

    return lib_util.debounce(
        func,
        ---@diagnostic disable-next-line: param-type-mismatch
        math.floor(config.options.lightbulb.debounce)
    )
end

-- auto command for lightbulb
function M.autocmd()
    local lightbulb_group =
        api.nvim_create_augroup(autogroup_name, { clear = true })

    local function _tmp()
        -- get current buffer
        local current_buffer = api.nvim_get_current_buf()
        local group_id = api.nvim_create_augroup(
            "Lspui_lightBulb_" .. tostring(current_buffer),
            { clear = true }
        )

        local new_func = debounce_func(current_buffer)

        api.nvim_create_autocmd({ "CursorHold" }, {
            group = group_id,
            buffer = current_buffer,
            callback = vim.schedule_wrap(new_func),
            desc = lib_util.command_desc("Lightbulb update when CursorHold"),
        })

        api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
            group = group_id,
            buffer = current_buffer,
            callback = M.clear_render,
            desc = lib_util.command_desc("Lightbulb update when InsertEnter"),
        })

        api.nvim_create_autocmd({ "BufDelete" }, {
            group = group_id,
            buffer = current_buffer,
            callback = function()
                api.nvim_del_augroup_by_id(group_id)
            end,
            desc = lib_util.command_desc(
                "Lightbulb delete autocmd when BufDelete"
            ),
        })
    end

    -- here is just no cache option
    api.nvim_create_autocmd("LspAttach", {
        group = lightbulb_group,
        callback = _tmp,
        desc = lib_util.command_desc("Lsp attach lightbulb cmd"),
    })
end

function M.un_autocmd()
    api.nvim_del_augroup_by_name(autogroup_name)
end

return M
