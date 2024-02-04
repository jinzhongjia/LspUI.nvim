local api, fn, uv = vim.api, vim.fn, vim.uv
local M = {}

local version = "v2-undefined"

local key_bind_opt = { noremap = true, silent = true }
local move_keys = {
    "h",
    "ge",
    "e",
    "0",
    "$",
    "l",
    "w",
    "b",
    "<Bs>",
    "j",
    "k",
    "<Left>",
    "<Right>",
    "<Up>",
    "<Down>",
}
local other_keys = { "x", "y", "v", "o", "O", "q" }

-- disable keys about moving
--- @param buffer_id integer
M.disable_move_keys = function(buffer_id)
    for _, key in pairs(move_keys) do
        api.nvim_buf_set_keymap(buffer_id, "n", key, "", key_bind_opt)
    end
    for _, key in pairs(other_keys) do
        api.nvim_buf_set_keymap(buffer_id, "n", key, "", key_bind_opt)
    end
end

-- check buffer is listed ?
--- @param buffer_id integer
--- @return boolean
M.buffer_is_listed = function(buffer_id)
    return fn.buflisted(buffer_id) == 1
end

-- force to delete buffer
--- @param buffer_id integer
M.delete_buffer = function(buffer_id)
    api.nvim_buf_delete(buffer_id, {
        force = true,
    })
end

-- generate command description
--- @param desc string
--- @return string
M.command_desc = function(desc)
    return "[LspUI]: " .. desc
end

-- execute once
--- @param callback function
M.exec_once = function(callback)
    local is_exec = false
    return function(...)
        if not is_exec then
            callback(...)
            is_exec = true
        end
    end
end

-- debounce
--- @param func function
---@param delay integer
M.debounce = function(func, delay)
    local timer = nil
    return function(...)
        local args = { ... }
        if timer then
            timer:stop()
            timer = nil
        end

        timer = vim.defer_fn(function()
            func(unpack(args))
            timer = nil
        end, delay)
    end
end

-- lib function: get version of LspUI
--- @return string
M.version = function()
    return version
end

--- @param buffer_id integer
--- @param uri lsp.URI
--- @param rows integer[]
--- @return string[]
M.get_uri_lines = function(buffer_id, uri, rows)
    local lines = {}
    if api.nvim_buf_is_loaded(buffer_id) then
        for _, row in ipairs(rows) do
            if not lines[row] then
                lines[row] = (api.nvim_buf_get_lines(
                    buffer_id,
                    row,
                    row + 1,
                    false
                ) or { "" })[1]
            end
        end
        return lines
    end

    if string.sub(uri, 1, 4) ~= "file" then
        fn.bufload(buffer_id)
        for _, row in ipairs(rows) do
            if not lines[row] then
                lines[row] = (api.nvim_buf_get_lines(
                    buffer_id,
                    row,
                    row + 1,
                    false
                ) or { "" })[1]
            end
        end
        return lines
    end

    -- get file name through buffer
    local file_full_name = api.nvim_buf_get_name(buffer_id)

    -- open file handle
    local fd = uv.fs_open(file_full_name, "r", 438)
    if not fd then
        return lines
    end

    -- get file status
    local stat = uv.fs_fstat(fd)
    if not stat then
        return lines
    end

    -- read all file content
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    if not data then
        return lines
    end

    local need = 0 -- keep track of how many unique rows we need
    for _, row in pairs(rows) do
        if not lines[row] then
            need = need + 1
        end
        lines[row] = true
    end

    local found = 0
    local lnum = 0

    ---@diagnostic disable-next-line: param-type-mismatch
    for line in string.gmatch(data, "([^\n]*)\n?") do
        if lines[lnum] == true then
            lines[lnum] = line
            found = found + 1
            if found == need then
                break
            end
        end
        lnum = lnum + 1
    end

    for i, line in pairs(lines) do
        if line == true then
            lines[i] = ""
        end
    end

    return lines
end

-- push tagstack
--- @param window_id integer
M.create_push_tagstack = function(window_id)
    local pos = vim.api.nvim_win_get_cursor(0)
    local current_word = vim.fn.expand("<cword>")
    local from = { vim.api.nvim_get_current_buf(), pos[1], pos[2], 0 }
    local items = { { tagname = current_word, from = from } }

    return function()
        vim.api.nvim_win_call(window_id, function()
            vim.cmd("norm! m'")
            vim.fn.settagstack(window_id, { items = items }, "t")
        end)
    end
end

--- @param buffer_id integer
---@param key string
M.get_buf_var = function(buffer_id, key)
    local status, result = pcall(api.nvim_buf_get_var, buffer_id, key)
    if status then
        return result
    end
    return nil
end

--- @param uri_1 lsp.URI
--- @param uri_2 lsp.URI
--- @return boolean
M.compare_uri = function(uri_1, uri_2)
    local path_1 = vim.uri_to_fname(uri_1)
    local path_2 = vim.uri_to_fname(uri_2)
    if vim.fn.has("win32") then
        path_1 = string.lower(path_1)
        path_2 = string.lower(path_2)
    end
    return path_1 == path_2
end

return M
