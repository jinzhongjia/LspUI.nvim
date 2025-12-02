-- lua/LspUI/layer/hover.lua
local api, lsp, fn = vim.api, vim.lsp, vim.fn
local hover_feature = lsp.protocol.Methods.textDocument_hover
local ClassLsp = require("LspUI.layer.lsp")
local ClassView = require("LspUI.layer.view")
local config = require("LspUI.config")
local notify = require("LspUI.layer.notify")
local tools = require("LspUI.layer.tools")

--- @alias hover_tuple { client: vim.lsp.Client, buffer_id: integer, width: integer, height: integer }

--- @class ClassHover
--- @field private _view ClassView|nil
--- @field private _hover_tuples hover_tuple[]
--- @field private _current_index integer
--- @field private _enter_lock boolean
local ClassHover = {
    _view = nil,
    _hover_tuples = {},
    _current_index = 1,
    _enter_lock = false,
}

ClassHover.__index = ClassHover

--- @return ClassHover
function ClassHover:New()
    local obj = {}
    setmetatable(obj, self)
    return obj
end

--- Apply Treesitter markdown highlighting (same as neovim native hover)
--- @param bufnr integer
--- @param winnr integer
local function apply_treesitter_highlight(bufnr, winnr)
    vim.wo[winnr].conceallevel = 2
    vim.wo[winnr].concealcursor = "n"
    vim.bo[bufnr].filetype = "markdown"
    pcall(vim.treesitter.start, bufnr)
end

--- Create a hover buffer from markdown lines
--- @param markdown_lines string[]
--- @return integer buffer_id
--- @return integer width
--- @return integer height
local function create_hover_buffer(markdown_lines)
    local new_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(new_buffer, 0, -1, true, markdown_lines)
    vim.bo[new_buffer].bufhidden = "wipe"
    vim.bo[new_buffer].modifiable = false

    -- Calculate dimensions
    local width = 0
    for _, str in ipairs(markdown_lines) do
        width = math.max(width, fn.strdisplaywidth(str))
    end
    width = math.min(width, math.floor(tools.get_max_width() * 0.5))
    local height = math.min(#markdown_lines, math.floor(tools.get_max_height() * 0.6))

    return new_buffer, width, height
end

--- @param buffer_id integer
--- @return vim.lsp.Client[]|nil
function ClassHover:GetClients(buffer_id)
    local clients = lsp.get_clients({ bufnr = buffer_id, method = hover_feature })
    return vim.tbl_isempty(clients) and nil or clients
end

--- @param clients vim.lsp.Client[]
--- @param buffer_id integer
--- @param callback fun(hover_tuples: hover_tuple[])
function ClassHover:GetHovers(clients, buffer_id, callback)
    local lsp_instance = ClassLsp:New()
    local ready, reason = lsp_instance:CheckClientsReady(clients)
    if not ready then
        notify.Warn(reason or "LSP client not ready")
        return
    end

    self._hover_tuples = {}
    local params = lsp.util.make_position_params(0, clients[1].offset_encoding)
    local pending = #clients

    for _, client in ipairs(clients) do
        client:request(hover_feature, params, function(err, result, _, lsp_config)
            lsp_config = lsp_config or {}

            if err and lsp_config.silent ~= true then
                notify.Warn(string.format(
                    "server %s, err code is %d, err msg is %s",
                    client.name, err.code, err.message
                ))
            elseif result and result.contents then
                local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
                local buf, width, height = create_hover_buffer(markdown_lines)
                table.insert(self._hover_tuples, {
                    client = client,
                    buffer_id = buf,
                    width = width,
                    height = height,
                })
            end

            pending = pending - 1
            if pending == 0 then
                callback(self._hover_tuples)
            end
        end, buffer_id)
    end
end

--- @param hover_tuple hover_tuple
--- @param total integer
--- @param options table|nil
--- @return ClassView
function ClassHover:Render(hover_tuple, total, options)
    options = options or {}
    self._current_index = 1

    local title = total > 1 and string.format("hover[1/%d]", total) or "hover"

    local view = ClassView:New(false)
        :SwitchBuffer(hover_tuple.buffer_id)
        :Title(title, "right")
        :Size(hover_tuple.width, hover_tuple.height)
        :Relative("cursor")
        :Border(config.options.hover.border)
        :Style("minimal")
        :Focusable(true)
        :Enter(false)
        :Anchor("NW")
        :Pos(1, 1)
        :Render()
        :Winhl("Normal:Normal")
        :Option("wrap", true)
        :Option("linebreak", true)
        :Option("breakindent", true)
        :Winbl(options.transparency or 0)

    local winnr = view:GetWinID()
    if winnr then
        apply_treesitter_highlight(hover_tuple.buffer_id, winnr)
    end

    self._view = view
    return view
end

--- @param forward boolean
function ClassHover:NextRender(forward)
    if not self._view or #self._hover_tuples <= 1 then
        return
    end

    local total = #self._hover_tuples
    if forward then
        self._current_index = self._current_index % total + 1
    else
        self._current_index = (self._current_index - 2) % total + 1
    end

    local hover_tuple = self._hover_tuples[self._current_index]
    self._view:SwitchBuffer(hover_tuple.buffer_id)

    local winnr = self._view:GetWinID()
    if winnr then
        apply_treesitter_highlight(hover_tuple.buffer_id, winnr)
    end

    local title = string.format("hover[%d/%d]", self._current_index, total)
    self._view:Updates(function()
        self._view:Size(hover_tuple.width, hover_tuple.height)
        self._view:Title(title, "right")
    end)
end

--- @param key_bindings table
function ClassHover:SetKeyBindings(key_bindings)
    if not self._view then
        return
    end

    self._view:KeyMap("n", key_bindings.next, function()
        self:NextRender(true)
    end, "next hover")

    self._view:KeyMap("n", key_bindings.prev, function()
        self:NextRender(false)
    end, "prev hover")

    self._view:KeyMap("n", key_bindings.quit, function()
        self:Close()
    end, "close hover")
end

--- @param buffer_id integer
function ClassHover:SetAutoCommands(buffer_id)
    if not self._view then
        return
    end

    api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufDelete", "BufLeave" }, {
        buffer = buffer_id,
        callback = function()
            if not self._enter_lock then
                self:Close()
                return true
            end
        end,
        desc = tools.command_desc("auto close hover when cursor moves"),
    })
end

--- @param callback function
function ClassHover:EnterWithLock(callback)
    self._enter_lock = true
    callback()
    self._enter_lock = false
end

--- @return boolean
function ClassHover:IsValid()
    return self._view ~= nil and self._view:Valid()
end

function ClassHover:Focus()
    if self:IsValid() then
        self._view:Focus()
    end
end

function ClassHover:Close()
    if self:IsValid() then
        self._view:Destroy()
        self._view = nil
    end
end

return ClassHover
