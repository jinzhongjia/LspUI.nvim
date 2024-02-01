local api, lsp, fn = vim.api, vim.lsp, vim.fn
local signature_feature = lsp.protocol.Methods.textDocument_signatureHelp

local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")

local M = {}

-- this variable records whether there is a virtual_text
--- @type boolean
local is_there_virtual_text = false

--- @class signature_info
--- @field label string
--- @field hint integer?
--- @field parameters {label: string, doc: (string|lsp.MarkupContent)?}[]?
--- @field doc string?

--- @param help lsp.SignatureHelp|nil
--- @return signature_info? res len will not be zero
local build_signature_info = function(help)
    if not help then
        return nil
    end
    if #help.signatures == 0 then
        return nil
    end

    local active_signature = help.activeSignature and help.activeSignature + 1
        or 1
    local active_parameter = help.activeParameter and help.activeParameter + 1
        or 1

    --- @type signature_info
    ---@diagnostic disable-next-line: missing-fields
    local res = {}

    local signature = help.signatures[active_signature]
    if signature.activeParameter then
        active_parameter = signature.activeParameter + 1
    end

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

    --- @type { label: string, doc: (string|lsp.MarkupContent)? }[]
    local params = {}
    for _, parameter in ipairs(parameters) do
        if type(parameter.label) == "string" then
            table.insert(params, {
                label = parameter.label,
                doc = parameter.documentation,
            })
        else
            local str = string.sub(
                signature.label,
                parameter.label[1] + 1,
                parameter.label[2]
            )
            table.insert(params, {
                label = str,
                doc = parameter.documentation,
            })
        end
    end

    res.parameters = params
    res.hint = active_parameter

    return res
end

-- this a list to store those buffers which can use signature
--- @type {[number]: boolean}
local buffer_list = {}

--- @type integer
local signature_group

local signature_namespace = api.nvim_create_namespace("LspUI_signature")

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

        local mode_info = vim.api.nvim_get_mode()
        local mode = mode_info["mode"]
        local is_insert = mode:find("i") ~= nil or mode:find("ic") ~= nil
        if not is_insert then
            return
        end

        M.clean_render(current_buffer)

        local callback_current_buffer = api.nvim_get_current_buf()
        -- when call current buffer is not equal to current buffer, return
        if callback_current_buffer ~= current_buffer then
            return
        end

        local current_window = api.nvim_get_current_win()
        M.render(result, current_buffer, current_window)
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

--- @param data lsp.SignatureHelp|nil
--- @param buffer_id integer
--- @param windows_id integer
M.render = function(data, buffer_id, windows_id)
    local info = build_signature_info(data)
    if not info then
        return
    end

    if not info.hint then
        return
    end

    --- @type integer
    ---@diagnostic disable-next-line: assign-type-mismatch
    local row = fn.line(".") == 1 and 1 or fn.line(".") - 2
    --- @type integer
    local col = fn.virtcol(".") - 1

    api.nvim_buf_set_extmark(buffer_id, signature_namespace, row, 0, {
        virt_text = {
            {
                string.format(
                    "%s %s",
                    config.options.signature.icon,
                    info.parameters[info.hint].label
                ),
                "LspUI_Signature",
            },
        },
        virt_text_win_col = col,
        hl_mode = "blend",
    })
    is_there_virtual_text = true
end

-- clean signature virtual text
--- @param buffer_id integer
M.clean_render = function(buffer_id)
    if not is_there_virtual_text then
        return
    end

    api.nvim_buf_clear_namespace(buffer_id, signature_namespace, 0, -1)
    is_there_virtual_text = false
end

-- this is autocmd init for signature
M.autocmd = function()
    signature_group =
        api.nvim_create_augroup("Lspui_signature", { clear = true })

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
    api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
        group = signature_group,
        callback = vim.schedule_wrap(func),
        desc = lib_util.command_desc("Signature update when CursorHoldI"),
    })

    -- when buffer is deleted, disable buffer siganture
    api.nvim_create_autocmd({ "BufDelete" }, {
        group = signature_group,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            M.clean_render(current_buffer)
            if buffer_list[current_buffer] then
                buffer_list[current_buffer] = false
            end
        end,
        desc = lib_util.command_desc("Exec signature clean cmd when QuitPre"),
    })

    api.nvim_create_autocmd({ "InsertLeave", "WinLeave" }, {
        group = signature_group,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            M.clean_render(current_buffer)
        end,
        desc = lib_util.command_desc(
            "Exec signature virtual text clean cmd when InsertLeave or WinLeave"
        ),
    })
end

M.deautocmd = function()
    api.nvim_del_augroup_by_id(signature_group)
end

--- @return signature_info?
M.status_line = function()
    return build_signature_info(backup.data)
end

return M
