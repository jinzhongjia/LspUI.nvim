local lsp, api, fn, uv = vim.lsp, vim.api, vim.fn, vim.uv
local rename_feature = lsp.protocol.Methods.textDocument_rename
local prepare_rename_feature = lsp.protocol.Methods.textDocument_prepareRename

local config = require("LspUI.config")
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local lib_windows = require("LspUI.lib.windows")

--- @alias LspUI_prepare_rename_res lsp.Range | { range: lsp.Range, placeholder: string } | { defaultBehavior: boolean } | nil

-- TODO: add progress support !!
-- maybe no need to implemention, because rename is a simple operation

local M = {}

-- get all valid clients of rename
--- @param buffer_id integer
--- @return vim.lsp.Client[]? clients array or nil
M.get_clients = function(buffer_id)
    -- note: we need get lsp clients attached to current buffer
    local clients = lsp.get_clients({
        bufnr = buffer_id,
        method = rename_feature,
    })
    if vim.tbl_isempty(clients) then
        return nil
    end
    return clients
end

-- rename
--- @param client vim.lsp.Client lsp client instance, must be element of func `get_clients`
--- @param buffer_id integer buffer id
--- @param position_param lsp.RenameParams  this param must be generated by `vim.lsp.util.make_position_params`, has newname attribute
--- @param callback function
M.rename = function(client, buffer_id, position_param, callback)
    local handler = client.handlers[rename_feature]
        or lsp.handlers[rename_feature]
    vim.schedule(function()
        client.request(rename_feature, position_param, function(...)
            handler(...)
            callback()
        end, buffer_id)
    end)
end

-- prepare rename, whether we can execute rename
-- if request return eroor, that mean we can't rename, and we should skip this
--- @param client vim.lsp.Client lsp client instance, must be element of func `get_clients`
--- @param buffer_id integer buffer id
--- @param position_param lsp.PrepareRenameParams  this param must be generated by `vim.lsp.util.make_position_params`
--- @param callback fun(result:LspUI_prepare_rename_res?)
M.prepare_rename = function(client, buffer_id, position_param, callback)
    local function __tmp()
        client.request(
            prepare_rename_feature,
            position_param,
            --- @type lsp.Handler
            --- @diagnostic disable-next-line: unused-local
            function(err, result, ctx, _)
                if err then
                    lib_notify.Error(
                        "error code:" .. err.code .. ", " .. err.message
                    )

                    return
                end
                --- @type LspUI_prepare_rename_res
                local res = result
                if result == nil then
                    callback()
                    return
                end
                callback(res)
            end,
            buffer_id
        )
    end
    vim.schedule(__tmp)
end

-- do rename, a wrap function for prepare_rename and rename
--- @param id integer
--- @param clients vim.lsp.Client[] lsp client instance, must be element of func `get_clients`
--- @param buffer_id integer buffer id
--- @param position_param lsp.PrepareRenameParams|lsp.RenameParams this param must be generated by `vim.lsp.util.make_position_params`, has newname attribute
M.do_rename = function(id, clients, buffer_id, position_param)
    local function next_rename()
        local next_id, _ = next(clients, id)
        M.do_rename(next_id, clients, buffer_id, position_param)
    end

    local async = uv.new_async(function()
        local client = clients[id]
        if not client then
            return
        end
        if client.supports_method(prepare_rename_feature) then
            M.prepare_rename(
                client,
                buffer_id,
                --- @cast position_param lsp.PrepareRenameParams
                position_param,
                -- we no need to resuse the result, we just use it todetect whether we can do rename
                function(result)
                    if not result then
                        next_rename()
                        return
                    end
                    --- @cast position_param lsp.RenameParams
                    M.rename(client, buffer_id, position_param, next_rename)
                end
            )
        else
            --- @cast position_param lsp.RenameParams
            M.rename(client, buffer_id, position_param, next_rename)
        end
    end)

    if async then
        async:send()
    else
        lib_notify.Error("async wrap doreaname failed")
    end
end

-- wrap windows.close_window
-- add detect insert mode
--- @param window_id integer
local close_window = function(window_id)
    if vim.fn.mode() == "i" then
        vim.cmd([[stopinsert]])
    end
    lib_windows.close_window(window_id)
end

-- calculate display length
--- @param str string
local calculate_length = function(str)
    local len = fn.strdisplaywidth(str) + 2
    return len > 10 and len or 10
end

-- render the window
--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param current_win integer
--- @param old_name string
M.render = function(clients, buffer_id, current_win, old_name)
    local position_param = lsp.util.make_position_params(current_win)

    -- Here we need to define window

    local new_buffer = api.nvim_create_buf(false, true)

    -- note: this must set before modifiable, when modifiable is false, this function will fail
    api.nvim_buf_set_lines(new_buffer, 0, -1, false, {
        --- @cast old_name string
        old_name,
    })

    api.nvim_set_option_value("filetype", "LspUI-rename", { buf = new_buffer })
    api.nvim_set_option_value("modifiable", true, { buf = new_buffer })
    api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buffer })

    local new_window_wrap = lib_windows.new_window(new_buffer)

    -- For aesthetics, the minimum width is 8
    local width = calculate_length(old_name)

    lib_windows.set_width_window(new_window_wrap, width)
    lib_windows.set_height_window(new_window_wrap, 1)
    lib_windows.set_enter_window(new_window_wrap, true)
    lib_windows.set_anchor_window(new_window_wrap, "NW")
    lib_windows.set_border_window(new_window_wrap, "rounded")
    lib_windows.set_focusable_window(new_window_wrap, true)
    lib_windows.set_relative_window(new_window_wrap, "cursor")
    lib_windows.set_col_window(new_window_wrap, 1)
    lib_windows.set_row_window(new_window_wrap, 1)
    lib_windows.set_style_window(new_window_wrap, "minimal")
    lib_windows.set_right_title_window(new_window_wrap, "rename")

    local window_id = lib_windows.display_window(new_window_wrap)

    api.nvim_set_option_value("winhighlight", "Normal:Normal", {
        win = window_id,
    })
    api.nvim_set_option_value("winblend", config.options.rename.transparency, {
        win = window_id,
    })

    if config.options.rename.auto_select then
        api.nvim_win_call(window_id, function()
            vim.cmd([[normal! V]])
            api.nvim_feedkeys(
                api.nvim_replace_termcodes("<C-g>", true, true, true),
                "n",
                true
            )
        end)
    end

    -- keybinding and autocommand
    M.keybinding_autocmd(
        window_id,
        old_name,
        clients,
        buffer_id,
        new_buffer,
        position_param
    )
end

-- keybinding and autocommand
--- @param window_id integer rename float window's id
--- @param old_name string the word's old name
--- @param clients vim.lsp.Client[] lsp clients
--- @param old_buffer integer the buffer which word belongs to
--- @param new_buffer integer the buffer which attach to rename float window
--- @param position_param lsp.PrepareRenameParams|lsp.RenameParams this param must be generated by `vim.lsp.util.make_position_params`
M.keybinding_autocmd = function(
    window_id,
    old_name,
    clients,
    old_buffer,
    new_buffer,
    position_param
)
    -- keybinding exec
    for _, mode in pairs({ "i", "n", "v" }) do
        api.nvim_buf_set_keymap(
            new_buffer,
            mode,
            config.options.rename.key_binding.exec,
            "",
            {
                nowait = true,
                noremap = true,
                callback = function()
                    local new_name = vim.trim(api.nvim_get_current_line())
                    if old_name ~= new_name then
                        position_param.newName = new_name
                        M.do_rename(1, clients, old_buffer, position_param)
                    end
                    close_window(window_id)
                end,
                desc = lib_util.command_desc("exec rename"),
            }
        )
    end

    -- keybinding quit
    api.nvim_buf_set_keymap(
        new_buffer,
        "n",
        config.options.rename.key_binding.quit,
        "",
        {
            nowait = true,
            noremap = true,
            callback = function()
                close_window(window_id)
            end,
            desc = lib_util.command_desc("quit rename"),
        }
    )

    local autocmd_group_id =
        vim.api.nvim_create_augroup("LspUI-rename_autocmd_group", {
            clear = true,
        })

    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = autocmd_group_id,
        buffer = new_buffer,
        callback = function()
            local now_name = api.nvim_get_current_line()
            local len = calculate_length(now_name)
            api.nvim_win_set_config(window_id, {
                width = len,
            })
        end,
        desc = lib_util.command_desc(
            "automatically lengthen the rename input box"
        ),
    })

    -- auto command: auto close window, when focus leave rename float window
    api.nvim_create_autocmd("WinLeave", {
        group = autocmd_group_id,
        buffer = new_buffer,
        once = true,
        callback = function()
            close_window(window_id)
        end,
        desc = lib_util.command_desc(
            "rename auto close windows when focus leave"
        ),
    })
end

return M
