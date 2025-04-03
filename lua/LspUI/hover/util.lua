local lsp, api, fn = vim.lsp, vim.api, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local config = require("LspUI.config")
local layer = require("LspUI.layer")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

--- @alias hover_tuple { client: vim.lsp.Client, buffer_id: integer, width: integer, height: integer }

local M = {}

local markview = nil

-- for hover enter lock
local enter_lock = false

--- @type hover_tuple[]
local hover_tuples = {}

--- @type integer
local hover_tuple_current_index

-- get all valid clients for hover
--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil clients array or nil
function M.get_clients(buffer_id)
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = hover_feature,
    })
    return clients
end

--- @class LspUI_hover_ctx
--- @field clients vim.lsp.Client[]
--- @field requested_client_count integer
--- @field invalid_clients string[]
--- @field callback fun(hover_tuples: hover_tuple[])

--- @param hover_ctx LspUI_hover_ctx
local function hover_req_cb(client, hover_ctx)
    --- @param err lsp.ResponseError
    --- @param result lsp.Hover
    --- @param _ LspUI_LspContext
    --- @param lsp_config table
    return function(err, result, _, lsp_config)
        lsp_config = lsp_config or {}

        -- this is for detecting error
        local is_err = err ~= nil and lsp_config.silent ~= true
        if is_err then
            local _err_msg = string.format(
                "server %s, err code is %d, err code is %s",
                client.name,
                err.code,
                err.message
            )
            lib_notify.Warn(_err_msg)
        end

        if err == nil then
            if not (result and result.contents) then
                if lsp_config.silent ~= true then
                    table.insert(hover_ctx.invalid_clients, client.name)
                end
            else
                -- stylua: ignore
                local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)

                -- create a new buffer
                local new_buffer = api.nvim_create_buf(false, true)

                -- stylua: ignore
                api.nvim_buf_set_lines(new_buffer, 0, -1, true, markdown_lines)

                -- stylua: ignore
                -- note: don't change filetype, this will cause syntx failing
                api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buffer })
                -- stylua: ignore
                -- stylua: ignore
                api.nvim_set_option_value("modifiable", false, { buf = new_buffer })

                local width = 0
                for _, str in pairs(markdown_lines) do
                    local _tmp_width = fn.strdisplaywidth(str)
                    width = math.max(width, _tmp_width)
                end

                -- stylua: ignore
                width = math.min(width, math.floor(lib_windows.get_max_width() * 0.6))

                local height = #markdown_lines

                table.insert(
                    hover_tuples,
                    --- @type hover_tuple
                    {
                        client = client,
                        buffer_id = new_buffer,
                        -- contents = markdown_lines,
                        width = width,
                        -- stylua: ignore
                        height = math.min(height, math.floor(lib_windows.get_max_height() * 0.8)),
                    }
                )
            end
        end

        hover_ctx.requested_client_count = hover_ctx.requested_client_count + 1

        if hover_ctx.requested_client_count ~= #hover_ctx.clients then
            return
        end
        if not vim.tbl_isempty(hover_ctx.invalid_clients) then
            local names = ""
            for index, client_name in pairs(hover_ctx.invalid_clients) do
                if index == 1 then
                    names = names .. client_name
                else
                    names = names .. string.format(", %s", client_name)
                end
            end
            lib_notify.Info(string.format("No valid hover, %s", names))
        end

        hover_ctx.callback(hover_tuples)
    end
end

-- get hovers from lsp
--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param callback fun(hover_tuples: hover_tuple[])
function M.get_hovers(clients, buffer_id, callback)
    -- remove past hover
    hover_tuples = {}
    -- make hover params
    -- TODO: inplement workDoneProgreeParam
    -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#hoverParams
    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)

    --- @type LspUI_hover_ctx
    local hover_ctx = {
        clients = clients,
        requested_client_count = 0,
        invalid_clients = {},
        callback = callback,
    }

    for _, client in pairs(clients) do
        -- stylua: ignore
        client:request(hover_feature, params, hover_req_cb(clients,hover_ctx), buffer_id)
    end
end

-- render hover
--- @param hover_tuple hover_tuple
--- @param hover_tuple_number integer
--- @return ClassView view window's id
function M.render(hover_tuple, hover_tuple_number)
    -- stylua: ignore
    local title = hover_tuple_number > 1 and string.format("hover[1/%d]", hover_tuple_number) or "hover"
    hover_tuple_current_index = 1

    local view = layer.ClassView
        :New(false)
        :SwitchBuffer(hover_tuple.buffer_id)
        :Title(title, "right")
        :Size(hover_tuple.width, hover_tuple.height)
        :Relative("cursor")
        :Border("rounded")
        :Style("minimal")
        :Focusable(true)
        :Enter(false)
        :Anchor("NW")
        :Pos(1, 1)
        :Render()
        :Winhl("Normal:Normal")
        :Option("wrap", true)
        :Option("conceallevel", 3)
        :Option("concealcursor", "nvic")
        :Winbl(config.options.hover.transparency)
        :BufOption("filetype", "LspUI_hover")

    -- hooks for markview
    -- render-markdown no need to hook
    if markview == nil then
        local status
        status, markview = pcall(require, "markview")
        if not status then
            markview = false
        end
    end

    if markview ~= false then
        markview.render(hover_tuple.buffer_id)
    end

    return view
end

--- @param view ClassView float window's id
--- @param forward boolean true is next, false is prev
local function next_render(view, forward)
    if forward then
        -- next
        if hover_tuple_current_index == #hover_tuples then
            hover_tuple_current_index = 1
        else
            hover_tuple_current_index = hover_tuple_current_index + 1
        end
    else
        -- prev
        if hover_tuple_current_index == 1 then
            hover_tuple_current_index = #hover_tuples
        else
            hover_tuple_current_index = hover_tuple_current_index - 1
        end
    end

    --- @type hover_tuple
    local hover_tuple = hover_tuples[hover_tuple_current_index]
    view:SwitchBuffer(hover_tuple.buffer_id)
    view:BufOption("filetype", "LspUI_hover")

    if markview ~= false then
        markview.render(hover_tuple.buffer_id)
    end

    -- stylua: ignore
    local title =  string.format("hover[%d/%d]",hover_tuple_current_index, #hover_tuples)
    view:Updates(function()
        view:Size(hover_tuple.width, hover_tuple.height)
        view:Title(title, "right")
    end)
end

--- audo for hover
--- this must be called in vim.schedule
--- @param current_buffer integer current buffer id, not float window's buffer id'
--- @param view ClassView  float window's id
function M.autocmd(current_buffer, view)
    -- autocmd
    api.nvim_create_autocmd(
        { "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" },
        {
            buffer = current_buffer,
            callback = function(_)
                -- stylua: ignore
                if enter_lock then return end
                view:Destory()
                return true
            end,
            desc = lib_util.command_desc("auto close hover when cursor moves"),
        }
    )
end

--- @param view ClassView window's id
function M.keybind(view)
    local mapping_list = {
        {
            key = config.options.hover.key_binding.next,
            cb = function()
                if #hover_tuples == 1 then
                    return
                end
                ---@diagnostic disable-next-line: param-type-mismatch
                next_render(view, true)
                ---@diagnostic disable-next-line: param-type-mismatch
                M.keybind(view)
            end,
            desc = "next hover",
        },
        {
            key = config.options.hover.key_binding.prev,
            cb = function()
                if #hover_tuples == 1 then
                    return
                end
                next_render(view, false)
                ---@diagnostic disable-next-line: param-type-mismatch
                M.keybind(view)
            end,
            desc = "prev hover",
        },
        {
            key = config.options.hover.key_binding.quit,
            cb = function()
                view:Destory()
            end,
            desc = "hover, close window",
        },
    }

    for _, mapping in pairs(mapping_list) do
        view:KeyMap("n", mapping.key, mapping.cb, mapping.desc)
    end
end

--- @param callback function
function M.enter_wrap(callback)
    enter_lock = true
    callback()
    enter_lock = false
end

return M
