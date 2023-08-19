local api, fn, lsp = vim.api, vim.fn, vim.lsp
local config = require("LspUI.config")
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

local M = {}

--- @alias lsp_range { start: lsp.Position, finish: lsp.Position }
--- @alias lsp_position  { buffer_id: integer, fold: boolean, range: lsp_range[]}
--- @alias Lsp_position_wrap  { [lsp.URI]: lsp_position}

--- @type { method: string, name: string }
local method = nil

--- @type Lsp_position_wrap
local datas = {}

--- @type { uri: string, buffer_id: integer, range: lsp_range? }
local current_item = {}

-- main view
local main_view = {
    buffer = -1,
    window = -1,
    hide = false,
}

-- secondary view
local secondary_view = {
    buffer = -1,
    window = -1,
    hide = false,
}

-- expose method
M.method = {
    definition = {
        method = lsp.protocol.Methods.textDocument_definition,
        name = "definition",
    },
    type_definition = {
        method = lsp.protocol.Methods.textDocument_typeDefinition,
        name = "type definition",
    },
    declaration = {
        method = lsp.protocol.Methods.textDocument_declaration,
        name = "declaration",
    },
    reference = {
        method = lsp.protocol.Methods.textDocument_references,
        name = "reference",
    },
    implemention = {
        method = lsp.protocol.Methods.textDocument_implementation,
        name = "implemention",
    },
}

--- @param lnum integer
--- @return string? uri
--- @return lsp_range? range
local get_lsp_position_by_lnum = function(lnum)
    for uri, data in pairs(datas) do
        lnum = lnum - 1
        if lnum == 0 then
            return uri, nil
        end
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum - 1
                if lnum == 0 then
                    return uri, val
                end
            end
        end
    end
end

-- local main_view_keybind = function()
--     local origin_back = api.nvim_buf_get_keymap(main_view.buffer, "n")
--     lib_debug.debug(origin_back)
--     -- back keybind
--     api.nvim_buf_set_keymap(
--         main_view.buffer,
--         "n",
--         config.options.pos_keybind.main.back,
--         "",
--         {
--             callback = function()
--                 if M.secondary_view_hide() then
--                     lib_windows.close_window(main_view.window)
--                 else
--                     api.nvim_set_current_win(secondary_view.window)
--                 end
--             end,
--         }
--     )
--     -- hide secondary view
--     api.nvim_buf_set_keymap(
--         main_view.buffer,
--         "n",
--         config.options.pos_keybind.main.hide_secondary,
--         "",
--         {
--             callback = function()
--                 M.secondary_view_hide(not M.secondary_view_hide())
--                 if M.secondary_view_hide() then
--                     lib_windows.close_window(secondary_view.window)
--                 else
--                     M.secondary_view_render("definition")
--                 end
--             end,
--         }
--     )
-- end

-- local main_view_autocmd = function() end

local secondary_view_keybind = function()
    -- keybind for jump
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.jump,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                if current_item.range then
                    lib_windows.close_window(M.secondary_view_window())
                    if fn.buflisted(current_item.buffer_id) == 1 then
                        vim.cmd(
                            string.format("buffer %s", current_item.buffer_id)
                        )
                    else
                        vim.cmd(
                            string.format(
                                "edit %s",
                                fn.fnameescape(
                                    vim.uri_to_fname(current_item.uri)
                                )
                            )
                        )
                    end
                else
                    datas[current_item.uri].fold =
                        not datas[current_item.uri].fold
                    M.secondary_view_render()
                end
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.enter,
        "",
        {
            callback = function()
                -- when main is not hidden, we can enter it
                if not M.main_view_hide() then
                    api.nvim_set_current_win(M.main_view_window())
                end
            end,
        }
    )

    -- quit for secondary
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.quit,
        "",
        {
            callback = function()
                lib_windows.close_window(M.secondary_view_window())
                lib_windows.close_window(M.main_view_window())
            end,
        }
    )

    -- hide main for keybind
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.hide_main,
        "",
        {
            callback = function()
                -- first we need to set main hide
                M.main_view_hide(not M.main_view_hide())
                if M.main_view_hide() then
                    lib_windows.close_window(M.main_view_window())
                else
                    M.main_view_render()
                end
            end,
        }
    )
end

local secondary_view_autocmd = function()
    api.nvim_create_autocmd("WinClosed", {
        buffer = M.secondary_view_buffer(),
        callback = function()
            -- when secondary hide, just return
            if M.secondary_view_hide() then
                return
            end
            lib_windows.close_window(M.main_view_window())
        end,
    })
    api.nvim_create_autocmd("CursorMoved", {
        buffer = M.secondary_view_buffer(),
        callback = function()
            -- when main hide, just return

            local cursor_position =
                api.nvim_win_get_cursor(M.secondary_view_window())
            local lnum = cursor_position[1]
            local uri, range = get_lsp_position_by_lnum(lnum)
            if not uri then
                return
            end

            -- set current cursorhold
            current_item = {
                uri = uri,
                buffer_id = datas[uri].buffer_id,
                range = range,
            }

            if range then
                do
                end

                local uri_buffer = datas[uri].buffer_id
                M.main_view_buffer(uri_buffer)

                if not M.main_view_hide() then
                    M.main_view_render()
                end
                api.nvim_buf_call(M.main_view_buffer(), function()
                    if
                        vim.api.nvim_buf_get_option(
                            M.main_view_buffer(),
                            "filetype"
                        ) == ""
                    then
                        vim.cmd("do BufRead")
                    end
                end)
                if not M.main_view_hide() then
                    lib_windows.window_set_cursor(
                        M.main_view_window(),
                        range.start.line + 1,
                        range.start.character
                    )

                    -- move center
                    api.nvim_win_call(M.main_view_window(), function()
                        vim.cmd("norm! zv")
                        vim.cmd("norm! zz")
                    end)
                end
            end
        end,
    })
end

--- @param buffer_id integer?
--- @return integer
M.main_view_buffer = function(buffer_id)
    if buffer_id then
        main_view.buffer = buffer_id
    end
    return main_view.buffer
end

--- @param window_id integer?
--- @return integer
M.main_view_window = function(window_id)
    if window_id then
        main_view.window = window_id
    end
    return main_view.window
end

--- @param hide boolean?
--- @return boolean
M.main_view_hide = function(hide)
    if hide ~= nil then
        main_view.hide = hide
    end
    return main_view.hide
end

--- @param buffer_id integer?
--- @return integer
M.secondary_view_buffer = function(buffer_id)
    if buffer_id and buffer_id ~= M.secondary_view_buffer() then
        secondary_view.buffer = buffer_id
        secondary_view_keybind()
        secondary_view_autocmd()
    end
    return secondary_view.buffer
end

--- @param window_id integer?
--- @return integer
M.secondary_view_window = function(window_id)
    if window_id then
        secondary_view.window = window_id
    end
    return secondary_view.window
end

--- @param hide boolean?
--- @return boolean
M.secondary_view_hide = function(hide)
    if hide ~= nil then
        secondary_view.hide = hide
    end
    return secondary_view.hide
end

--- @param param Lsp_position_wrap?
--- @return Lsp_position_wrap
M.datas = function(param)
    if param then
        datas = param
    end
    return datas
end

-- abstruct lsp request, this will request all clients which are passed
-- this function only can be called by `definition` or `declaration`
-- or `type definition` or `reference` or `implementation`
--- @param buffer_id integer which buffer do method
--- @param clients lsp.Client[]
--- @param method string
--- @param params table
--- @param callback fun(datas: Lsp_position_wrap|nil)
M.lsp_clients_request = function(buffer_id, clients, method, params, callback)
    local tmp_number = 0
    local client_number = #clients

    local origin_uri = vim.uri_from_bufnr(buffer_id)

    --- @type Lsp_position_wrap
    local data = {}
    for _, client in pairs(clients) do
        client.request(method, params, function(err, result, _, _)
            if not result then
                callback(nil)
                return
            end
            if err ~= nil then
                lib_notify.Warn(string.format("when %s, err: %s", method, err))
            end
            tmp_number = tmp_number + 1

            if result.uri then
                -- response is a position
                local uri = result.uri
                local range = result.range
                local uri_buffer = vim.uri_to_bufnr(uri)
                if data[uri] == nil then
                    data[uri] = {
                        buffer_id = uri_buffer,
                        fold = origin_uri ~= uri and true or false,
                        range = {},
                    }
                end

                table.insert(data[uri].range, {
                    start = range.start,
                    finish = range["end"],
                })
            else
                for _, response in ipairs(result) do
                    local uri = response.uri or response.targetUri
                    local range = response.range or response.targetRange
                    local uri_buffer = vim.uri_to_bufnr(uri)
                    if data[uri] == nil then
                        data[uri] = {
                            buffer_id = uri_buffer,
                            fold = origin_uri ~= uri and true or false,
                            range = {},
                        }
                    end
                    table.insert(data[uri].range, {
                        start = range.start,
                        finish = range["end"],
                    })
                end
            end

            if tmp_number == client_number then
                callback(data)
            end
        end, buffer_id)
    end
end

--- @return integer width
--- @return integer height
local generate_secondary_view = function()
    if not api.nvim_buf_is_valid(M.secondary_view_buffer()) then
        M.secondary_view_buffer(api.nvim_create_buf(false, true))
    end

    local content = {}
    local max_width = 0
    local height = 0
    for uri, data in pairs(datas) do
        -- get full file name
        local file_full_name = vim.uri_to_fname(uri)
        -- get file name
        local file_fmt = string.format(
            " %s %s",
            data.fold and "" or "",
            fn.fnamemodify(file_full_name, ":t")
        )

        table.insert(content, file_fmt)
        height = height + 1

        -- get file_fmt length
        local file_fmt_len = fn.strdisplaywidth(file_fmt)

        -- detect max width
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        local uri_rows = {}
        do
            -- local tmp_store = {}
            for _, range in ipairs(data.range) do
                local row = range.start.line
                -- if not tmp_store[row] then
                table.insert(uri_rows, row)
                -- tmp_store[row] = true
                -- end
            end
        end

        local lines = lib_util.get_uri_lines(data.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = fn.trim(lines[row])
            local code_fmt = string.format("   %s", line_code)
            if not data.fold then
                table.insert(content, code_fmt)
            end
            height = height + 1

            local code_fmt_length = fn.strdisplaywidth(code_fmt)

            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    api.nvim_buf_set_lines(M.secondary_view_buffer(), 0, -1, true, content)

    -- For aesthetics, increase the width
    return max_width + 2 > 30 and 30 or max_width + 2, height + 1
end

-- render main view
M.main_view_render = function()
    if not api.nvim_buf_is_valid(M.main_view_buffer()) then
        lib_notify.Error(
            "render main view fails, main view buffer is not valid"
        )
        return
    end
    if not api.nvim_buf_is_loaded(M.main_view_buffer()) then
        fn.bufload(M.main_view_buffer())
    end

    if lib_windows.is_valid_window(M.main_view_window()) then
        -- if now windows is valid, just set buffer
        api.nvim_win_set_buf(M.main_view_window(), M.main_view_buffer())
        return
    end

    -- window is not valid, create a new window
    local main_window_wrap = lib_windows.new_window(M.main_view_buffer())
    lib_windows.set_width_window(main_window_wrap, lib_windows.get_max_width())
    lib_windows.set_height_window(
        main_window_wrap,
        lib_windows.get_max_height() - 3
    )
    lib_windows.set_enter_window(main_window_wrap, false)
    lib_windows.set_anchor_window(main_window_wrap, "NW")
    -- set none border, TODO: add more border here
    lib_windows.set_border_window(main_window_wrap, "none")
    lib_windows.set_relative_window(main_window_wrap, "editor")
    lib_windows.set_zindex_window(main_window_wrap, 10)
    lib_windows.set_col_window(main_window_wrap, 0)
    lib_windows.set_row_window(main_window_wrap, 1)

    M.main_view_window(lib_windows.display_window(main_window_wrap))
end

--- TODO: remove name
M.secondary_view_render = function()
    -- generate buffer, get width and height
    local width, height = generate_secondary_view()

    if lib_windows.is_valid_window(M.secondary_view_window()) then
        api.nvim_win_set_buf(
            M.secondary_view_window(),
            M.secondary_view_buffer()
        )
        api.nvim_win_set_config(M.secondary_view_window(), {
            width = width,
            height = height,
        })
        return
    end

    local second_window_wrap = lib_windows.new_window(M.secondary_view_buffer())

    -- set width
    lib_windows.set_width_window(second_window_wrap, width)
    -- set height
    lib_windows.set_height_window(second_window_wrap, height)
    -- whether enter window
    lib_windows.set_enter_window(second_window_wrap, false)
    -- fixed position
    lib_windows.set_relative_window(second_window_wrap, "editor")
    lib_windows.set_col_window(
        second_window_wrap,
        lib_windows.get_max_width() - width - 2
    )
    lib_windows.set_style_window(second_window_wrap, "minimal")
    lib_windows.set_border_window(second_window_wrap, "single")
    lib_windows.set_zindex_window(second_window_wrap, 11)
    lib_windows.set_anchor_window(second_window_wrap, "NW")
    lib_windows.set_center_title_window(second_window_wrap, method.name)

    M.secondary_view_window(lib_windows.display_window(second_window_wrap))
    api.nvim_win_set_option(
        M.secondary_view_window(),
        "winhighlight",
        "Normal:Normal"
    )
end

--- @param buffer_id integer which buffer do method
--- @param clients lsp.Client[]
--- @param params table
--- @param new_method { method: string, name: string }
M.go = function(new_method, buffer_id, clients, params)
    -- set method
    method = new_method

    M.lsp_clients_request(
        buffer_id,
        clients,
        method.method,
        params,
        function(data)
            if not data then
                lib_notify.Info("no valid definition")
                return
            end
            M.datas(data)

            M.secondary_view_render()

            -- set current window
            api.nvim_set_current_win(M.secondary_view_window())
        end
    )
end

return M
