local api, fn, uv = vim.api, vim.fn, vim.uv
local M = {}

--- @param buffer_id integer
--- @param uri lsp.URI
--- @param rows integer[]
--- @return string[]
function M.GetUriLines(buffer_id, uri, rows)
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

return M
