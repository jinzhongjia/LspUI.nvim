local api, fn, lsp = vim.api, vim.fn, vim.lsp
local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

---
--- int this file, we will render two window
--- one window's content is the file name and code line, we call it secondary view
--- another is preview the file, we call it main view
---

local M = {}

-- create a namespace
local main_namespace = api.nvim_create_namespace("LspUI_main")

local secondary_namespace = api.nvim_create_namespace("LspUI_secondary")

-- key is buffer id, value is the map info
--- @type { [integer]: { [string]: any } } the any should be the result of maparg
local buffer_keymap_history = {}

-- function for push tagstack
local push_tagstack = nil

-- create auto group

--- @alias lsp_range { start: lsp.Position, finish: lsp.Position }
--- @alias lsp_position  { buffer_id: integer, fold: boolean, range: lsp_range[]}
--- @alias Lsp_position_wrap  { [lsp.URI]: lsp_position}

-- more info, see M.method
--- @type { method: string, name: "definition"|"type_definition"|"declaration"|"reference"|"implementation", fold: boolean }
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

-- these are methods which are exposed
M.method = {
    definition = {
        method = lsp.protocol.Methods.textDocument_definition,
        name = "definition",
        fold = false,
    },
    type_definition = {
        method = lsp.protocol.Methods.textDocument_typeDefinition,
        name = "type_definition",
        fold = false,
    },
    declaration = {
        method = lsp.protocol.Methods.textDocument_declaration,
        name = "declaration",
        fold = false,
    },
    reference = {
        method = lsp.protocol.Methods.textDocument_references,
        name = "reference",
        fold = true,
    },
    implementation = {
        method = lsp.protocol.Methods.textDocument_implementation,
        name = "implementation",
        fold = true,
    },
}

-- get pos through lnum
--- @param lnum integer
--- @return string? uri
--- @return lsp_range? range
local get_lsp_position_by_lnum = function(lnum)
    for uri, data in pairs(M.datas()) do
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

-- highlight main view
--- @param data lsp_position
local main_set_hl = function(data)
    for _, val in pairs(data.range) do
        for row = val.start.line, val.finish.line, 1 do
            local start_col = 0
            local end_col = -1
            if row == val.start.line then
                start_col = val.start.character
            end

            if row == val.finish.line then
                end_col = val.finish.character
            end

            api.nvim_buf_add_highlight(
                M.main_view_buffer(),
                main_namespace,
                "Search",
                row,
                start_col,
                end_col
            )
        end
    end
end

-- highlight secondary view, only highlight file name
--- @param hl integer[]
local secondary_set_hl = function(hl)
    for _, lnum in pairs(hl) do
        api.nvim_buf_add_highlight(
            M.secondary_view_buffer(),
            secondary_namespace,
            "Directory",
            lnum - 1,
            3,
            -1
        )
    end
end

-- clear main highlight
local main_clear_hl = function()
    if api.nvim_buf_is_valid(M.main_view_buffer()) then
        vim.api.nvim_buf_clear_namespace(
            M.main_view_buffer(),
            main_namespace,
            0,
            -1
        )
    end
end

-- clear secondary highlight
local secondary_clear_hl = function()
    if api.nvim_buf_is_valid(M.secondary_view_buffer()) then
        vim.api.nvim_buf_clear_namespace(
            M.secondary_view_buffer(),
            secondary_namespace,
            0,
            -1
        )
    end
end

local main_view_restore_keybind = function(map_infos, buffer_id)
    for key, value in pairs(map_infos) do
        -- pcall(fn.mapset, "n", 0, value)
        if not vim.tbl_isempty(value) then
            api.nvim_buf_del_keymap(buffer_id, "n", key)
            fn.mapset("n", false, value)
        else
            api.nvim_buf_del_keymap(buffer_id, "n", key)
            -- pcall(vim.api.nvim_buf_del_keymap, buffer_id, "n", key)
        end
    end
end

-- keybind for main view
local main_view_keybind = function()
    local back_map =
        fn.maparg(config.options.pos_keybind.main.back, "n", false, true)

    local hide_map = fn.maparg(
        config.options.pos_keybind.main.hide_secondary,
        "n",
        false,
        true
    )

    if not buffer_keymap_history[M.main_view_buffer()] then
        buffer_keymap_history[M.main_view_buffer()] = {
            [config.options.pos_keybind.main.back] = back_map,
            [config.options.pos_keybind.main.hide_secondary] = hide_map,
        }
    end

    -- back keybind
    api.nvim_buf_set_keymap(
        M.main_view_buffer(),
        "n",
        config.options.pos_keybind.main.back,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.back_secondary()
            end,
        }
    )

    -- hide secondary view
    api.nvim_buf_set_keymap(
        M.main_view_buffer(),
        "n",
        config.options.pos_keybind.main.hide_secondary,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.hide_secondary()
            end,
        }
    )
end

local secondary_cmd = {}

local function main_view_autocmd()
    local main_group =
        api.nvim_create_augroup("Lspui_main_view", { clear = true })
    local main_win = M.main_view_window()
    api.nvim_create_autocmd("WinClosed", {
        group = main_group,
        pattern = {
            tostring(main_win),
        },
        once = true,
        callback = function()
            print("close main")
            -- note: The judgment here is to prevent the following closing function
            -- from being executed when the main view is hidden.
            if not M.main_view_hide() then
                main_clear_hl()
                api.nvim_set_option_value(
                    "winbar",
                    vim.wo.winbar or "",
                    { win = main_win }
                )
                api.nvim_set_option_value(
                    "winhighlight",
                    vim.wo.winhighlight or "",
                    {
                        win = main_win,
                    }
                )

                lib_windows.close_window(M.secondary_view_window())
                pcall(api.nvim_del_autocmd, secondary_cmd.CursorMoved)
                for buffer_id, value in pairs(buffer_keymap_history) do
                    api.nvim_buf_call(buffer_id, function()
                        main_view_restore_keybind(value, buffer_id)
                    end)
                end
                buffer_keymap_history = {}
            end
        end,
    })
end

-- keybind for secondary view
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
                M.action.jump()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.jump_tab,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.jump_tab()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.jump_split,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.jump_split()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.jump_vsplit,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.jump_vsplit()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.toggle_fold,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.toggle_fold()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.next_entry,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.next_entry()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.prev_entry,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.prev_entry()
            end,
        }
    )

    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.enter,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.enter_main()
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
            nowait = true,
            noremap = true,
            callback = function()
                M.action.secondary_quit()
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
            nowait = true,
            noremap = true,
            callback = function()
                M.action.hide_main()
            end,
        }
    )

    -- fold all
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.fold_all,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.fold_secondary_all()
            end,
        }
    )

    -- expand all
    api.nvim_buf_set_keymap(
        M.secondary_view_buffer(),
        "n",
        config.options.pos_keybind.secondary.expand_all,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                M.action.expand_secondary_all()
            end,
        }
    )
end

-- auto cmd for secondary view
local secondary_view_autocmd = function()
    local secondary_group =
        api.nvim_create_augroup("Lspui_secondary_view", { clear = true })

    secondary_cmd.close = api.nvim_create_autocmd("WinClosed", {
        group = secondary_group,
        pattern = {
            tostring(M.secondary_view_window()),
        },
        once = true,
        callback = function()
            -- note: The judgment here is to prevent the following closing function
            -- from being executed when the secondary view is hidden.
            pcall(api.nvim_del_autocmd, secondary_cmd.CursorMoved)
            if not M.secondary_view_hide() then
                main_clear_hl()
                local main_win = M.main_view_window()
                api.nvim_set_option_value(
                    "winbar",
                    vim.wo.winbar or "",
                    { win = main_win }
                )
                api.nvim_set_option_value(
                    "winhighlight",
                    vim.wo.winhighlight or "",
                    { win = main_win }
                )
                lib_windows.close_window(main_win)
                for buffer_id, value in pairs(buffer_keymap_history) do
                    api.nvim_buf_call(buffer_id, function()
                        main_view_restore_keybind(value, buffer_id)
                    end)
                end
                buffer_keymap_history = {}
            end
        end,
        desc = lib_util.command_desc(" secondary view winclose"),
    })

    local _tmp = function()
        -- get current cursor position

        --- @type integer
        ---@diagnostic disable-next-line: assign-type-mismatch
        local lnum = fn.line(".")

        local uri, range = get_lsp_position_by_lnum(lnum)
        if not uri then
            return
        end

        -- set current cursorhold
        current_item = {
            uri = uri,
            buffer_id = M.datas()[uri].buffer_id,
            range = range,
        }

        if range then
            local uri_buffer = M.datas()[uri].buffer_id

            -- change main view buffer
            M.main_view_buffer(uri_buffer)

            if not M.main_view_hide() then
                -- render main vie
                M.main_view_render()

                -- set cursor
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
    end

    local cursor_moved_cb = lib_util.debounce(_tmp, 100)

    secondary_cmd.CursorMoved = api.nvim_create_autocmd("CursorMoved", {
        group = secondary_group,
        -- pattern = {
        --     tostring(M.secondary_view_window()),
        -- },
        -- note: we can't use buffer and pattern together
        -- CursorMoved can't effect on pattern
        buffer = M.secondary_view_buffer(),
        callback = cursor_moved_cb,
    })
end

--- @param buffer_id integer?
--- @return integer
M.main_view_buffer = function(buffer_id)
    if buffer_id then
        if not M.main_view_hide() then
            -- remove old buffer's highlight
            main_clear_hl()
        end

        -- set new main view buffer
        main_view.buffer = buffer_id

        -- TODO: maybe these can be optional run with main_view_hide
        -- load main view buffer
        if not api.nvim_buf_is_loaded(M.main_view_buffer()) then
            fn.bufload(M.main_view_buffer())
        end

        -- TODO: why we must do `BufRead`
        api.nvim_buf_call(M.main_view_buffer(), function()
            if
                api.nvim_get_option_value("filetype", {
                    buf = M.main_view_buffer(),
                }) == ""
            then
                vim.cmd("do BufRead")
            end
        end)

        if not M.main_view_hide() then
            -- highlight new main_view_buffer
            main_set_hl(M.datas()[current_item.uri])
        end
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
    if hide ~= nil and hide ~= M.main_view_hide() then
        main_view.hide = hide
        if hide then
            main_clear_hl()
        else
            main_set_hl(M.datas()[current_item.uri])
        end
    end
    return main_view.hide
end

--- @param buffer_id integer?
--- @return integer
M.secondary_view_buffer = function(buffer_id)
    if buffer_id and buffer_id ~= M.secondary_view_buffer() then
        secondary_view.buffer = buffer_id
        secondary_view_keybind()
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
    if hide ~= nil and hide ~= M.secondary_view_hide() then
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

-- this is for handle csharp_ls decompile
-- https://github.com/razzmatazz/csharp-language-server#decompile-for-your-editor--with-the-example-of-neovim
-- this code is from https://github.com/Decodetalkers/csharpls-extended-lsp.nvim, thanks
--- @param uri lsp.URI
--- @param _client vim.lsp.Client
--- @return lsp.URI
local function csharp_ls_handle(_client, uri)
    if _client.name ~= "csharp_ls" then
        return uri
    end
    local csharp_host = "csharp:/metadata"

    -- check whether need to decompile
    if string.sub(uri, 1, string.len(csharp_host)) ~= csharp_host then
        return uri
    end

    local _params = {
        timeout = 5000,
        textDocument = {
            uri = uri,
        },
    }
    local _res, _ = _client:request_sync("csharp/metadata", _params, 10000, 0)

    ---@diagnostic disable-next-line: need-check-nil
    local _result = _res.result

    ---@diagnostic disable-next-line: need-check-nil, undefined-field
    local normalized = string.gsub(_result.source, "\r\n", "\n")
    local source_lines = vim.split(normalized, "\n")

    ---@diagnostic disable-next-line: need-check-nil, undefined-field
    local normalized_source_name = string.gsub(_result.assemblyName, "\\", "/")
    local file_name = "/" .. normalized_source_name

    local get_or_create_buf = function(name)
        local buffers = vim.api.nvim_list_bufs()
        for _, buf in pairs(buffers) do
            local bufname = vim.api.nvim_buf_get_name(buf)

            -- if we are looking for $metadata$ buffer, search for entire string anywhere
            -- in buffer name. On Windows nvim_buf_set_name might change the buffer name and include some stuff before.
            if string.find(name, "^/%$metadata%$/.*$") then
                local normalized_bufname = string.gsub(bufname, "\\", "/")
                if string.find(normalized_bufname, name) then
                    return buf
                end
            else
                if bufname == name then
                    return buf
                    -- Match a bufname like C:\System.Console
                elseif
                    string.find(string.gsub(bufname, "%u:\\", "/"), name)
                then
                    return buf
                end
            end
        end

        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, name)
        return bufnr
    end
    -- this will be /$metadata$/...
    local bufnr = get_or_create_buf(file_name)
    -- TODO: check if bufnr == 0 -> error
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", false, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
    vim.api.nvim_set_option_value("filetype", "cs", { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
    vim.api.nvim_set_option_value("modified", false, { buf = bufnr })

    -- attach lsp client ??
    -- vim.lsp.buf_attach_client(bufnr, _client.id)
    return vim.uri_from_bufnr(bufnr)
end

-- abstruct lsp request, this will request all clients which are passed
-- this function only can be called by `definition` or `declaration`
-- or `type definition` or `reference` or `implementation`
--- @param buffer_id integer which buffer do method
--- @param clients vim.lsp.Client[]
--- @param params table
--- @param callback fun(datas: Lsp_position_wrap|nil)
M.lsp_clients_request = function(buffer_id, clients, params, callback)
    -- tmp_number is only for counts
    local tmp_number = 0

    local client_number = #clients

    local origin_uri = vim.uri_from_bufnr(buffer_id)

    --- @type Lsp_position_wrap
    local data = {}

    for _, client in pairs(clients) do
        client:request(method.method, params, function(err, result, _, _)
            -- always add one
            tmp_number = tmp_number + 1

            if err ~= nil then
                lib_notify.Warn(
                    string.format(
                        "method %s meet error, error code is %d, msg is %s",
                        method.name,
                        err.code,
                        err.message
                    )
                )
            else
                local function _handle_result(_result)
                    -- response is a position
                    local uri = _result.uri or _result.targetUri
                    local range = _result.range or _result.targetRange

                    if method.name == "definition" then
                        uri = csharp_ls_handle(client, uri)
                    end

                    local uri_buffer = vim.uri_to_bufnr(uri)
                    if data[uri] == nil then
                        data[uri] = {
                            buffer_id = uri_buffer,
                            fold = method.fold
                                and not lib_util.compare_uri(origin_uri, uri),
                            range = {},
                        }
                    end

                    table.insert(data[uri].range, {
                        start = range.start,
                        finish = range["end"],
                    })
                end
                if result and not vim.tbl_isempty(result) then
                    if result.uri then
                        _handle_result(result)
                    else
                        for _, response in ipairs(result) do
                            _handle_result(response)
                        end
                    end
                end
            end

            if tmp_number == client_number then
                if vim.tbl_isempty(data) then
                    callback(nil)
                else
                    callback(data)
                end
            end
        end, buffer_id)
    end
end

--- @return integer width
--- @return integer height
local generate_secondary_view = function()
    if not api.nvim_buf_is_valid(M.secondary_view_buffer()) then
        -- in this scope, we will create a new buffer
        M.secondary_view_buffer(api.nvim_create_buf(false, true))
    else
        -- is this scope, we will reuse old buffer, so we need clear old highlight
        secondary_clear_hl()
    end

    -- enable change for this buffer
    api.nvim_set_option_value("modifiable", true, {
        buf = M.secondary_view_buffer(),
    })

    -- set the secondary buffer filetype
    api.nvim_set_option_value(
        "filetype",
        string.format("LspUI-%s", method.name),
        {
            buf = M.secondary_view_buffer(),
        }
    )

    -- hl_num for highlight lnum recording
    local hl_num = 0
    -- this array stores the highlighted line number
    local hl = {}

    -- the buffer's new content
    local content = {}

    -- calculate the max width that we need
    local max_width = 0
    -- calculate the height for render
    local height = 0

    for uri, data in pairs(M.datas()) do
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

        hl_num = hl_num + 1
        table.insert(hl, hl_num)

        -- get file_fmt length
        local file_fmt_len = fn.strdisplaywidth(file_fmt)

        -- detect max width
        if file_fmt_len > max_width then
            max_width = file_fmt_len
        end

        local uri_rows = {}
        do
            for _, range in ipairs(data.range) do
                local row = range.start.line
                table.insert(uri_rows, row)
            end
        end

        local lines = lib_util.get_uri_lines(data.buffer_id, uri, uri_rows)
        for _, row in pairs(uri_rows) do
            local line_code = fn.trim(lines[row])
            local code_fmt = string.format("   %s", line_code)
            if not data.fold then
                table.insert(content, code_fmt)
                hl_num = hl_num + 1
            end
            height = height + 1

            local code_fmt_length = fn.strdisplaywidth(code_fmt)

            if code_fmt_length > max_width then
                max_width = code_fmt_length
            end
        end
    end

    api.nvim_buf_set_lines(M.secondary_view_buffer(), 0, -1, true, content)

    -- now we have calculated the highlight line numbers
    secondary_set_hl(hl)

    -- disable change for this buffer
    api.nvim_set_option_value("modifiable", false, {
        buf = M.secondary_view_buffer(),
    })

    local res_width = max_width + 2 > 30 and 30 or max_width + 2

    local max_columns =
        math.floor(api.nvim_get_option_value("columns", {}) * 0.3)

    if max_columns > res_width then
        res_width = max_columns
    end

    -- For aesthetics, increase the width
    return res_width, height + 1
end

-- render main view
M.main_view_render = function()
    -- detect the buffer is valid
    if not api.nvim_buf_is_valid(M.main_view_buffer()) then
        lib_notify.Error(
            "render main view fails, main view buffer is not valid"
        )
        return
    end

    local main_win = M.main_view_window()
    if lib_windows.is_valid_window(main_win) then
        -- if now windows is valid, just set buffer
        api.nvim_win_set_buf(main_win, M.main_view_buffer())
    else
        -- window is not valid, create a new window
        local main_window_wrap = lib_windows.new_window(M.main_view_buffer())

        -- set width and height
        lib_windows.set_width_window(
            main_window_wrap,
            lib_windows.get_max_width()
        )
        lib_windows.set_height_window(
            main_window_wrap,
            lib_windows.get_max_height() - 2
        )

        -- set whether enter the main_view_window
        lib_windows.set_enter_window(main_window_wrap, false)

        lib_windows.set_anchor_window(main_window_wrap, "NW")

        -- set none border, TODO: add more border here
        lib_windows.set_border_window(main_window_wrap, "none")

        lib_windows.set_relative_window(main_window_wrap, "editor")

        lib_windows.set_zindex_window(main_window_wrap, 10)

        lib_windows.set_row_window(main_window_wrap, 0)
        lib_windows.set_col_window(main_window_wrap, 0)

        -- set new main view window
        M.main_view_window(lib_windows.display_window(main_window_wrap))
    end
    do
        -- prevent extra shadows
        api.nvim_set_option_value(
            "winhighlight",
            "Normal:Normal,WinBar:Comment",
            {
                win = M.main_view_window(),
            }
        )

        api.nvim_set_option_value(
            "winblend",
            config.options.pos_keybind.transparency,
            {
                win = M.main_view_window(),
            }
        )
    end
    local window_id = M.main_view_window()
    local fname = vim.uri_to_fname(current_item.uri)
    local filepath = vim.fs.normalize(vim.fn.fnamemodify(fname, ":p:~:h"))
    api.nvim_set_option_value("winbar", string.format(" %s", filepath), {
        win = window_id,
    })

    M.main_view_hide(false)

    main_view_autocmd()
end

-- render secondary view
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
            row = 0,
            col = lib_windows.get_max_width() - width - 2,
            relative = "editor",
        })
    else
        local second_window_wrap =
            lib_windows.new_window(M.secondary_view_buffer())

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

        M.secondary_view_window(lib_windows.display_window(second_window_wrap))
    end
    -- prevent extra shadows
    -- vim.schedule(function()
    api.nvim_win_call(M.secondary_view_window(), function()
        api.nvim_set_option_value("winhighlight", "Normal:Normal", {
            win = M.secondary_view_window(),
        })
        api.nvim_set_option_value(
            "winblend",
            config.options.pos_keybind.transparency,
            {
                win = M.secondary_view_window(),
            }
        )
    end)

    -- end)

    api.nvim_win_set_config(M.secondary_view_window(), {
        title_pos = "center",
        title = method.name,
    })

    M.secondary_view_hide(false)

    secondary_view_autocmd()
end

--- @param param_uri string
local cursor_for_item = function(param_uri)
    local lnum = 0
    for uri, data in pairs(M.datas()) do
        lnum = lnum + 1
        if uri == param_uri then
            return lnum
        end
        if not data.fold then
            for _, _ in pairs(data.range) do
                lnum = lnum + 1
            end
        end
    end
    if method.fold then
        return 1
    end
    return 2
end

--- @param cmd "tabe"|"vsplit"|"split"|?
local action_jump = function(cmd)
    if current_item.range then
        -- push tagstack must be called before close window
        ---@diagnostic disable-next-line: need-check-nil
        push_tagstack()

        local main_win = M.main_view_window()
        api.nvim_set_option_value(
            "winbar",
            vim.wo.winbar or "",
            { win = main_win }
        )
        api.nvim_set_option_value("winhighlight", vim.wo.winhighlight or "", {
            win = main_win,
        })
        lib_windows.close_window(M.secondary_view_window())

        if not lib_util.buffer_is_listed(current_item.buffer_id) then
            lib_util.delete_buffer(M.main_view_buffer())
        end

        if cmd then
            if cmd == "tabe" then
                vim.cmd("tab split")
            else
                vim.cmd(cmd)
            end
        end

        if lib_util.buffer_is_listed(current_item.buffer_id) then
            vim.cmd(string.format("buffer %s", current_item.buffer_id))
        else
            vim.cmd(
                string.format(
                    "edit %s",
                    fn.fnameescape(vim.uri_to_fname(current_item.uri))
                )
            )
        end

        -- if cmd then
        --     vim.cmd(
        --         string.format("%s %s", cmd, vim.uri_to_fname(current_item.uri))
        --     )
        -- else
        --     vim.cmd(
        --         string.format(
        --             "edit %s",
        --             fn.fnameescape(vim.uri_to_fname(current_item.uri))
        --         )
        --     )
        -- end

        api.nvim_win_set_cursor(0, {
            current_item.range.start.line + 1,
            current_item.range.start.character,
        })
        vim.cmd("norm! zz")
    else
        datas[current_item.uri].fold = not M.datas()[current_item.uri].fold
        M.secondary_view_render()
    end
end

local action_toggle_fold = function()
    datas[current_item.uri].fold = not M.datas()[current_item.uri].fold
    M.secondary_view_render()
end

-- next file entry
local action_next_entry = function()
    -- when current_item not exist, just return
    if not current_item.uri then
        return
    end
    local current_uri = current_item.uri
    local line = 1
    local has_seen_current = false
    for uri, val in pairs(M.datas()) do
        if has_seen_current then
            api.nvim_win_set_cursor(M.secondary_view_window(), { line, 0 })
            break
        end
        line = line + 1
        if not val.fold then
            line = line + #val.range
        end

        if uri == current_uri then
            has_seen_current = true
        end
    end
end

-- prev file entry
local action_prev_entry = function()
    -- when current_item not exist, just return
    if not current_item.uri then
        return
    end
    local current_uri = current_item.uri
    local line = 1
    local prev_range_nums = 0
    for uri, val in pairs(M.datas()) do
        if uri == current_uri then
            line = line - prev_range_nums
            if line > 1 then
                line = line - 1
            end
            api.nvim_win_set_cursor(M.secondary_view_window(), { line, 0 })
            break
        end

        line = line + 1
        if not val.fold then
            prev_range_nums = #val.range
            line = line + prev_range_nums
        else
            prev_range_nums = 0
        end
    end

    print(string.format("prev file is %d", line))

    -- api.nvim_win_set_cursor(M.secondary_view_window(), { line, 0 })
end

local action_enter_main = function()
    if not M.main_view_hide() then
        api.nvim_set_current_win(M.main_view_window())
        -- clear background
        api.nvim_set_option_value("winhighlight", "Normal:Normal", {
            win = M.main_view_window(),
        })
        main_view_keybind()
    end
end

local action_secondary_quit = function()
    lib_windows.close_window(M.secondary_view_window())
    -- when main view buffer is valid, delete it
    if
        api.nvim_buf_is_valid(M.main_view_buffer())
        and not lib_util.buffer_is_listed(M.main_view_buffer())
    then
        lib_util.delete_buffer(M.main_view_buffer())
    end
end

local action_hide_main = function()
    M.main_view_hide(not M.main_view_hide())
    if M.main_view_hide() then
        lib_windows.close_window(M.main_view_window())
    else
        M.main_view_render()
        local range = current_item.range
        if range then
            lib_windows.window_set_cursor(
                M.main_view_window(),
                range.start.line + 1,
                range.start.character
            )
            api.nvim_win_call(M.main_view_window(), function()
                vim.cmd("norm! zv")
                vim.cmd("norm! zz")
            end)
        end
    end
end

local action_back_secondary = function()
    if not M.secondary_view_hide() then
        local map_infos = buffer_keymap_history[M.main_view_buffer()]
        main_view_restore_keybind(map_infos, M.main_view_buffer())
        buffer_keymap_history[M.main_view_buffer()] = nil

        api.nvim_set_current_win(M.secondary_view_window())
        -- remove background
        api.nvim_set_option_value("winhighlight", "Normal:Normal", {
            win = M.secondary_view_window(),
        })
    end
end

local action_hide_secondary = function()
    M.secondary_view_hide(not M.secondary_view_hide())
    if M.secondary_view_hide() then
        lib_windows.close_window(M.secondary_view_window())
    else
        M.secondary_view_render()
    end
end

--- @param param boolean
local action_fold_all = function(param)
    local tmp_switch = false
    local tmp_uri = current_item.uri
    local tmp_datas = M.datas()
    for key, value in pairs(tmp_datas) do
        if param ~= value.fold then
            tmp_switch = true
            tmp_datas[key].fold = param
        end
    end

    if not tmp_switch then
        return
    end
    M.datas(tmp_datas)

    M.secondary_view_render()
    api.nvim_win_set_cursor(
        M.secondary_view_window(),
        { cursor_for_item(tmp_uri), 0 }
    )
end

-- define actions
M.action = {
    jump = function()
        action_jump()
    end,
    jump_vsplit = function()
        action_jump("vsplit")
    end,
    jump_split = function()
        action_jump("split")
    end,
    jump_tab = function()
        action_jump("tabe")
    end,
    toggle_fold = function()
        action_toggle_fold()
    end,
    next_entry = function()
        action_next_entry()
    end,
    prev_entry = function()
        action_prev_entry()
    end,
    enter_main = function()
        action_enter_main()
    end,
    back_secondary = function()
        action_back_secondary()
    end,
    secondary_quit = function()
        action_secondary_quit()
    end,
    hide_main = function()
        action_hide_main()
    end,
    hide_secondary = function()
        action_hide_secondary()
    end,
    fold_secondary_all = function()
        action_fold_all(true)
    end,
    expand_secondary_all = function()
        action_fold_all(false)
    end,
}

--- @param params lsp.TextDocumentPositionParams
local find_position_from_params = function(params)
    local lnum = 0
    local param_uri = params.textDocument.uri

    local file_lnum = nil
    local code_lnum = nil

    --- @type integer|nil
    local tmp = nil

    for uri, data in pairs(M.datas()) do
        lnum = lnum + 1
        if not data.fold then
            for _, val in pairs(data.range) do
                lnum = lnum + 1
                if lib_util.compare_uri(uri, param_uri) then
                    if not file_lnum then
                        file_lnum = lnum
                    end
                    if val.start.line == params.position.line then
                        if tmp then
                            if
                                math.abs(
                                    val.start.character
                                        - params.position.character
                                )
                                < tmp
                            then
                                tmp = math.abs(
                                    val.start.character
                                        - params.position.character
                                )
                                code_lnum = lnum
                            end
                        else
                            tmp = math.abs(
                                val.start.character - params.position.character
                            )
                            code_lnum = lnum
                        end
                    end
                end
            end
        end
    end
    if code_lnum then
        return code_lnum
    end
    if file_lnum then
        return file_lnum
    end
    if method.fold then
        return 1
    end
    return 2
end

--- @param buffer_id integer
M.is_secondary_buffer = function(buffer_id)
    return M.secondary_view_buffer() == buffer_id
end

M.get_current_item = function()
    return current_item
end

M.get_current_method = function()
    return method
end

--- @param params table
M.set_secondary_view_cursor = function(params)
    -- set the cursor position
    api.nvim_win_set_cursor(
        M.secondary_view_window(),
        { find_position_from_params(params), 0 }
    )
end

--- @param buffer_id integer which buffer do method
--- @param window_id integer? which window do method
--- @param clients vim.lsp.Client[]
--- @param params table
--- @param new_method { method: string, name: string, fold: boolean }
--- @param callback fun(Lsp_position_wrap?)?
M.go = function(new_method, buffer_id, window_id, clients, params, callback)
    -- set method
    method = new_method

    M.lsp_clients_request(buffer_id, clients, params, function(data)
        -- if the buffer_id is not valid, just return
        if not api.nvim_buf_is_valid(buffer_id) then
            return
        end

        if not data then
            if callback then
                callback()
            else
                lib_notify.Info(string.format("no valid %s", method.name))
            end
            return
        end

        if callback then
            callback(data)
        end

        M.datas(data)

        if window_id then
            push_tagstack = lib_util.create_push_tagstack(window_id)
        end

        M.secondary_view_render()

        -- set current window
        api.nvim_set_current_win(M.secondary_view_window())

        -- set secondary view cursor
        M.set_secondary_view_cursor(params)
    end)
end

-- autochange secondary window
api.nvim_create_autocmd("VimResized", {
    callback = function()
        if not api.nvim_win_is_valid(M.secondary_view_window()) then
            return
        end
        M.secondary_view_render()
    end,
})

return M
