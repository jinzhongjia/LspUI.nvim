local M = {}

--- @param t any
--- @return boolean
function M.islist(t)
    return vim.islist(t)
end

--- @param contents string[]
--- @param width integer
--- @param width_calculator fun(str: string): integer
--- @return integer
function M.compute_height_for_contents(contents, width, width_calculator)
    if not width or width <= 0 then
        return #contents
    end

    local height = 0
    for _, line in ipairs(contents) do
        local line_width = width_calculator(line)
        height = height + math.max(1, math.ceil(line_width / width))
    end

    return height
end

return M
