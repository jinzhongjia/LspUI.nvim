local fn, api = vim.fn, vim.api
local ClassLsp = require("LspUI.layer.lsp")
local config = require("LspUI.config")
local global = require("LspUI.global")
local tools = require("LspUI.layer.tools")

local M = {}

local autogroup_name = "Lspui_lightBulb"

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    return ClassLsp:GetCodeActionClients(buffer_id)
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

    -- 减少计算量，使用一次性回调
    local __callback = tools.exec_once(callback)

    -- 创建参数
    local params = ClassLsp:MakeCodeActionParams(buffer_id)

    -- 使用轻量级选项请求代码操作
    local options = {
        skip_lsp = false, -- 包括LSP服务器操作
        skip_registered = false, -- 包括注册的操作
        skip_gitsigns = false, -- 包括gitsigns操作
    }

    ClassLsp:RequestCodeActions(buffer_id, params, function(action_tuples)
        -- 如果发现任何代码操作，显示灯泡
        __callback(#action_tuples > 0)
    end, options)
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
        return func, nil
    elseif config.options.lightbulb.debounce == true then
        return tools.debounce(func, 250)
    end

    return tools.debounce(
        func,
        ---@diagnostic disable-next-line: param-type-mismatch
        math.floor(config.options.lightbulb.debounce)
    )
end

-- 存储每个 buffer 的清理函数
local buffer_cleanups = {}

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

        local new_func, cleanup = debounce_func(current_buffer)
        
        -- 保存清理函数
        if cleanup then
            buffer_cleanups[current_buffer] = cleanup
        end

        api.nvim_create_autocmd({ "CursorHold" }, {
            group = group_id,
            buffer = current_buffer,
            callback = vim.schedule_wrap(new_func),
            desc = tools.command_desc("Lightbulb update when CursorHold"),
        })

        api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
            group = group_id,
            buffer = current_buffer,
            callback = M.clear_render,
            desc = tools.command_desc("Lightbulb update when InsertEnter"),
        })

        api.nvim_create_autocmd({ "BufDelete" }, {
            group = group_id,
            buffer = current_buffer,
            callback = function()
                -- 清理防抖计时器
                if buffer_cleanups[current_buffer] then
                    buffer_cleanups[current_buffer]()
                    buffer_cleanups[current_buffer] = nil
                end
                api.nvim_del_augroup_by_id(group_id)
            end,
            desc = tools.command_desc(
                "Lightbulb delete autocmd when BufDelete"
            ),
        })
    end

    -- here is just no cache option
    api.nvim_create_autocmd("LspAttach", {
        group = lightbulb_group,
        callback = _tmp,
        desc = tools.command_desc("Lsp attach lightbulb cmd"),
    })
end

function M.un_autocmd()
    -- 清理所有 buffer 的防抖计时器
    for _, cleanup in pairs(buffer_cleanups) do
        if cleanup then
            cleanup()
        end
    end
    buffer_cleanups = {}
    
    api.nvim_del_augroup_by_name(autogroup_name)
end

return M
