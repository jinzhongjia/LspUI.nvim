local api, lsp = vim.api, vim.lsp
local signature_feature = lsp.protocol.Methods.textDocument_signatureHelp

local config = require("LspUI.config")
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")

local M = {}

-- this a list to store those buffers which can use signature
--- @type {[number]: boolean}
local buffer_list = {}

local signature_group =
    api.nvim_create_augroup("Lspui_signature", { clear = true })

--- @type { data: lsp.SignatureHelp?, }
local backup = {}

--- @param buffer_id number buffer's id
--- @param callback fun(result: lsp.SignatureHelp|nil)  callback function
M.request = function(buffer_id, callback)
    -- this buffer id maybe invalid
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end

    local clients = M.get_clients(buffer_id)
    if not clients then
        return
    end

    local params = lsp.util.make_position_params()
    -- NOTE: we just use one client to get the lsp signature
    local client = clients[1]
    -- for _, client in pairs(clients or {}) do
    client.request(
        signature_feature,
        params,
        --- @param err  lsp.ResponseError
        --- @param result lsp.SignatureHelp?
        function(err, result, _, _)
            if err then
                lib_notify.Error(
                    string.format(
                        "sorry, lsp %s report siganature error:%d, &s",
                        client.name,
                        err.code,
                        err.message
                    )
                )
                return
            end
            callback(result)
        end,
        buffer_id
    )
    -- end
end

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = signature_feature })
    return #clients == 0 and nil or clients
end

--- @type function
local func

local signature_handle = function()
    local current_buffer = api.nvim_get_current_buf()
    -- when current buffer can not use signature
    if not buffer_list[current_buffer] then
        backup.data = nil
        return
    end
    M.request(current_buffer, function(result)
        backup.data = result
        -- TODO: add render to here
    end)
end

local build_func = function()
    if not config.options.signature.debounce then
        func = signature_handle
        return
    end

    --- @type integer
    local time = type(config.options.lightbulb.debounce) == "number"
            ---@diagnostic disable-next-line: param-type-mismatch
            and math.floor(config.options.signature.debounce)
        or 300

    func = lib_util.debounce(signature_handle, time)
end

M.render = function() end

M.clean_render = function() end

-- this is autocmd init for signature
M.autocmd = function()
    -- build debounce function
    build_func()

    api.nvim_create_autocmd("LspAttach", {
        group = signature_group,
        callback = function()
            -- get current buffer
            local current_buffer = api.nvim_get_current_buf()

            local clients = M.get_clients(current_buffer)
            if not clients then
                -- no clients support signature help
                return
            end

            buffer_list[current_buffer] = true
        end,
        desc = lib_util.command_desc("Lsp attach signature cmd"),
    })

    -- maybe this can also use CurosrHold
    api.nvim_create_autocmd({ "CursorMovedI", "CursorMoved" }, {
        group = signature_group,
        callback = vim.schedule_wrap(func),
        desc = lib_util.command_desc("Signature update when CursorHoldI"),
    })

    -- when buffer is deleted, disable buffer siganture
    api.nvim_create_autocmd({ "BufDelete" }, {
        group = signature_group,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            if buffer_list[current_buffer] then
                buffer_list[current_buffer] = false
            end
        end,
        desc = lib_util.command_desc("Exec signature clean cmd when QuitPre"),
    })
end

M.deautocmd = function()
    api.nvim_del_augroup_by_id(signature_group)
end

--- @class siganture_info
--- @field label string
--- @field hint integer?
--- @field parameters string[]
--- @field doc string?

--- @return siganture_info?
M.status_line = function()
    local data = backup.data
    if not data then
        return nil
    end
    if #data.signatures == 0 then
        return nil
    end

    local active_signature = data.activeSignature and data.activeSignature + 1
        or 1
    local active_parameter = data.activeParameter and data.activeParameter + 1
        or 1

    --- @type siganture_info
    ---@diagnostic disable-next-line: missing-fields
    local res = {}

    local signature = data.signatures[active_signature]

    res.label = signature.label
    ---@diagnostic disable-next-line: assign-type-mismatch
    res.doc = type(signature.documentation) == "table"
            and signature.documentation.value
        or signature.documentation

    if not signature.parameters or (#signature.parameters == 0) then
        return res
    end

    --- @type lsp.ParameterInformation[]
    local parameters = signature.parameters

    --- @type string[]
    local params = {}
    for _, parameter in ipairs(parameters) do
        if type(parameter.label) == "string" then
            table.insert(params, parameter.label)
        else
            local str = string.sub(
                signature.label,
                parameter.label[1] + 1,
                parameter.label[2]
            )
            table.insert(params, str)
        end
    end

    res.parameters = params
    res.hint = active_parameter

    return res
end

return M
