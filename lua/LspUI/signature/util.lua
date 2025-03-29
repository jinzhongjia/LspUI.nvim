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
--- @field active_parameter integer?
--- @field parameters {label: string, doc: (string|lsp.MarkupContent)?}[]?
--- @field doc string?

--- @param help lsp.SignatureHelp|nil
--- @param _ string|nil client name
--- @return signature_info? res len will not be zero
local function build_signature_info(help, _)
    if not help then
        return nil
    end
    if #help.signatures == 0 then
        return nil
    end

    local active_signature = 1

    if help.activeSignature then
        active_signature = help.activeSignature + 1
    end

    local active_parameter = 1

    if help.activeParameter then
        active_parameter = help.activeParameter + 1
    end

    --- @type signature_info
    --- @diagnostic disable-next-line: missing-fields
    local res = {}

    local current_signature = help.signatures[active_signature]

    res.label = current_signature.label
    if type(current_signature.documentation) == "table" then
        res.doc = current_signature.documentation.value
    else
        ---@diagnostic disable-next-line: assign-type-mismatch
        res.doc = current_signature.documentation
    end

    if
        not current_signature.parameters or (#current_signature.parameters == 0)
    then
        return res
    end

    if current_signature.activeParameter then
        active_parameter = current_signature.activeParameter + 1
    end

    -- Prevent irregular servers from crossing boundaries
    if
        active_parameter > #current_signature.parameters
        or active_parameter < 1
    then
        active_parameter = 1
    end

    --- @type lsp.ParameterInformation[]
    local parameters = current_signature.parameters

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
                current_signature.label,
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
    res.active_parameter = active_parameter

    return res
end

-- this a list to store those buffers which can use signature
--- @type {[number]: boolean}
local buffer_list = {}

--- @type integer
local signature_group

local signature_namespace = api.nvim_create_namespace("LspUI_signature")

--- @type signature_info|nil
local cached_signature_info = nil

--- @param buffer_id number buffer's id
--- @param callback fun(result: lsp.SignatureHelp|nil,client_name:string|nil)  callback function
local function request(buffer_id, callback)
    -- this buffer id maybe invalid
    if not api.nvim_buf_is_valid(buffer_id) then
        return
    end

    local clients = M.get_clients(buffer_id)
    if (not clients) or #clients < 1 then
        return
    end

    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)

    -- NOTE: we just use one client to get the lsp signature
    -- TODO: Perhaps users should be allowed to choose which server
    local client = clients[1]

    --- @param err  lsp.ResponseError
    --- @param result lsp.SignatureHelp?
    local function req_callback(err, result, _, _)
        if err then
            -- stylua: ignore
            local err_msg = string.format("sorry, lsp %s report siganature error:%d, &s", client.name, err.code, err.message)
            lib_notify.Error(err_msg)
            return
        end
        callback(result, client.name)
    end

    client:request(signature_feature, params, req_callback, buffer_id)
end

-- get all valid clients for lightbulb
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    local clients =
        lsp.get_clients({ bufnr = buffer_id, method = signature_feature })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

local function signature_handle()
    local current_buffer = api.nvim_get_current_buf()
    -- when current buffer can not use signature
    if not buffer_list[current_buffer] then
        cached_signature_info = nil
        return
    end

    --- @type fun(result: lsp.SignatureHelp|nil,client_name:string|nil)
    local function req_callback(result, client_name)
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
        M.render(result, current_buffer, current_window, client_name)
    end
    request(current_buffer, req_callback)
end

--- the true running function
--- @type function
local func

--- @param data lsp.SignatureHelp|nil
--- @param buffer_id integer
--- @param _ integer window id
--- @param client_name string|nil
function M.render(data, buffer_id, _, client_name)
    local info = build_signature_info(data, client_name)
    cached_signature_info = info
    if not info then
        return
    end

    if not info.active_parameter then
        return
    end

    --- @type integer
    ---@diagnostic disable-next-line: assign-type-mismatch
    local row = fn.line(".") == 1 and 1 or fn.line(".") - 2
    --- @type integer
    local col = fn.virtcol(".") - 1

    -- stylua: ignore
    local render_text = string.format("%s %s", config.options.signature.icon, info.parameters[info.active_parameter].label)

    api.nvim_buf_set_extmark(buffer_id, signature_namespace, row, 0, {
        virt_text = { { render_text, "LspUI_Signature" } },
        virt_text_win_col = col,
        hl_mode = "blend",
    })
    is_there_virtual_text = true
end

-- clean signature virtual text
--- @param buffer_id integer
function M.clean_render(buffer_id)
    if not is_there_virtual_text then
        return
    end

    api.nvim_buf_clear_namespace(buffer_id, signature_namespace, 0, -1)
    is_there_virtual_text = false
end

-- this is autocmd init for signature
function M.autocmd()
    signature_group =
        api.nvim_create_augroup("Lspui_signature", { clear = true })

    func = signature_handle
    if config.options.signature.debounce then
        local time = 300

        if type(config.options.signature.debounce) == "number" then
            ---@diagnostic disable-next-line: param-type-mismatch
            time = math.floor(config.options.signature.debounce)
        end

        func = lib_util.debounce(signature_handle, time)
    end

    local function lsp_attach_cb()
        -- get current buffer
        local current_buffer = api.nvim_get_current_buf()

        local clients = M.get_clients(current_buffer)
        if not clients then
            -- no clients support signature help
            return
        end

        buffer_list[current_buffer] = true
    end

    api.nvim_create_autocmd("LspAttach", {
        group = signature_group,
        callback = lsp_attach_cb,
        desc = lib_util.command_desc("Lsp attach signature cmd"),
    })

    -- maybe this can also use CurosrHold
    api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
        group = signature_group,
        callback = func,
        desc = lib_util.command_desc(
            "Signature update when CursorHoldI or InsertEnter"
        ),
    })

    local function lsp_detach_cb()
        local current_buffer = api.nvim_get_current_buf()
        M.clean_render(current_buffer)
        if buffer_list[current_buffer] then
            buffer_list[current_buffer] = false
        end
    end

    -- when buffer is deleted, disable buffer siganture
    api.nvim_create_autocmd({ "LspDetach" }, {
        group = signature_group,
        callback = lsp_detach_cb,
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
    return cached_signature_info
end

return M
