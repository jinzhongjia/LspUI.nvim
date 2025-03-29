local lsp, api, fn = vim.lsp, vim.api, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local config = require("LspUI.config")
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

local function starts_with_backticks(str)
    return string.find(str, "^```") ~= nil
end

local function is_only_whitespace(str)
    return str:match("^%s*$") ~= nil
end

--- @param markdown_lines string[]
local function markdown_lines_handle(markdown_lines)
    if #markdown_lines <= 3 then
        return markdown_lines
    end
    --- @type string[]
    local res = {}

    local i = 2
    local prev_is_added = false
    while i <= #markdown_lines - 1 do
        local prev_whitespace = is_only_whitespace(markdown_lines[i - 1])
        local current_backticks = starts_with_backticks(markdown_lines[i])
        local next_whitespace = is_only_whitespace(markdown_lines[i + 1])
        if
            not (prev_whitespace and current_backticks) and not prev_is_added
        then
            table.insert(res, markdown_lines[i - 1])
        end
        table.insert(res, markdown_lines[i])
        if next_whitespace and current_backticks then
            i = i + 2
            prev_is_added = false
        else
            i = i + 1
            prev_is_added = true
        end
    end
    return res
end

--- @param client vim.lsp.Client
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
--- @return integer window_id window's id
--- @return integer buffer_id buffer's id
function M.render(hover_tuple, hover_tuple_number)
    local new_window_wrap = lib_windows.new_window(hover_tuple.buffer_id)

    -- stylua: ignore
    local title = hover_tuple_number > 1 and string.format("hover[1/%d]", hover_tuple_number) or "hover"
    lib_windows.set_height_window(new_window_wrap, hover_tuple.height)
    lib_windows.set_width_window(new_window_wrap, hover_tuple.width)
    lib_windows.set_right_title_window(new_window_wrap, title)
    lib_windows.set_relative_window(new_window_wrap, "cursor")
    lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_style_window(new_window_wrap, "minimal")
    lib_windows.set_focusable_window(new_window_wrap, true)
    lib_windows.set_enter_window(new_window_wrap, false)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    lib_windows.set_col_window(new_window_wrap, 1)
    lib_windows.set_row_window(new_window_wrap, 1)

    local window_id = lib_windows.display_window(new_window_wrap)
    hover_tuple_current_index = 1

    -- stylua: ignore
    api.nvim_set_option_value("winhighlight", "Normal:Normal", { win = window_id })
    -- stylua: ignore
    api.nvim_set_option_value("wrap", true, { win = window_id })
    -- stylua: ignore
    api.nvim_set_option_value("winblend", config.options.hover.transparency, { win = window_id })
    -- stylua: ignore
    api.nvim_set_option_value("filetype", "LspUI_hover", { buf = hover_tuple.buffer_id })
    api.nvim_set_option_value("conceallevel", 3, { win = window_id })
    api.nvim_set_option_value("concealcursor", "nvic", { win = window_id })

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

    return window_id, hover_tuple.buffer_id
end

--- @param window_id integer float window's id
--- @param forward boolean true is next, false is prev
--- @return integer
local function next_render(window_id, forward)
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
    api.nvim_win_set_buf(window_id, hover_tuple.buffer_id)
    -- stylua: ignore
    api.nvim_set_option_value("filetype", "LspUI_hover", { buf = hover_tuple.buffer_id })
    if markview ~= false then
        markview.render(hover_tuple.buffer_id)
    end
    local hover_tuple_count = #hover_tuples
    -- stylua: ignore
    local title =  string.format("hover[%d/%d]",hover_tuple_current_index, hover_tuple_count)
    api.nvim_win_set_config(window_id, {
        width = hover_tuple.width,
        height = hover_tuple.height,
        title = title,
        title_pos = "right",
    })

    return hover_tuple.buffer_id
end

--- audo for hover
--- this must be called in vim.schedule
--- @param current_buffer integer current buffer id, not float window's buffer id'
--- @param window_id integer  float window's id
function M.autocmd(current_buffer, window_id)
    -- autocmd
    api.nvim_create_autocmd(
        { "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" },
        {
            buffer = current_buffer,
            callback = function(arg)
                -- stylua: ignore
                if enter_lock then return end
                lib_windows.close_window(window_id)
                api.nvim_del_autocmd(arg.id)
            end,
            desc = lib_util.command_desc("auto close hover when cursor moves"),
        }
    )
end

--- @param window_id integer window's id
--- @param buffer_id integer buffer's id
function M.keybind(window_id, buffer_id)
    local mapping_list = {
        {
            key = config.options.hover.key_binding.next,
            cb = function()
                if #hover_tuples == 1 then
                    return
                end
                local next_buffer = next_render(window_id, true)
                M.keybind(window_id, next_buffer)
            end,
            desc = lib_util.command_desc("next hover"),
        },
        {
            key = config.options.hover.key_binding.prev,
            cb = function()
                if #hover_tuples == 1 then
                    return
                end
                local next_buffer = next_render(window_id, false)
                M.keybind(window_id, next_buffer)
            end,
            desc = lib_util.command_desc("prev hover"),
        },
        {
            key = config.options.hover.key_binding.quit,
            cb = function()
                lib_windows.close_window(window_id)
            end,
            desc = lib_util.command_desc("hover, close window"),
        },
    }

    for _, mapping in pairs(mapping_list) do
        local opts = {
            nowait = true,
            noremap = true,
            callback = mapping.cb,
            desc = mapping.desc,
        }
        api.nvim_buf_set_keymap(buffer_id, "n", mapping.key, "", opts)
    end
end

--- @param callback function
function M.enter_wrap(callback)
    enter_lock = true
    callback()
    enter_lock = false
end

return M
