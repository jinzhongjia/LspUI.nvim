local lsp, api, fn = vim.lsp, vim.api, vim.fn
local code_action_feature = lsp.protocol.Methods.textDocument_codeAction
local exec_command_feature = lsp.protocol.Methods.workspace_executeCommand
local code_action_resolve_feature = lsp.protocol.Methods.codeAction_resolve

local config = require("LspUI.config")
local lib_lsp = require("LspUI.lib.lsp")
local lib_debug = require("LspUI.lib.debug")
local lib_notify = require("LspUI.lib.notify")
local lib_windows = require("LspUI.lib.windows")

--- @alias action_tuple { action: lsp.CodeAction|lsp.Command, client: lsp.Client }

local M = {}

-- get all valid clients for lighthulb
--- @param buffer_id integer
--- @return lsp.Client[]|nil clients array or nil
M.get_clients = function(buffer_id)
	local clients = lsp.get_clients({ bufnr = buffer_id, method = code_action_feature })
	return #clients == 0 and nil or clients
end

-- make range params
--- @param buffer_id integer
M.get_range_params = function(buffer_id)
	local mode = api.nvim_get_mode().mode
	local params
	if mode == "v" or mode == "V" then
		--this logic here is taken from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L125-L153
		-- [bufnum, lnum, col, off]; both row and column 1-indexed
		local start = vim.fn.getpos("v")
		local end_ = vim.fn.getpos(".")
		local start_row = start[2]
		local start_col = start[3]
		local end_row = end_[2]
		local end_col = end_[3]

		-- A user can start visual selection at the end and move backwards
		-- Normalize the range to start < end
		if start_row == end_row and end_col < start_col then
			end_col, start_col = start_col, end_col
		elseif end_row < start_row then
			start_row, end_row = end_row, start_row
			start_col, end_col = end_col, start_col
		end
		params = lsp.util.make_given_range_params({ start_row, start_col - 1 }, { end_row, end_col - 1 })
	else
		params = lsp.util.make_range_params()
	end

	local context = {
		triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
		diagnostics = lib_lsp.diagnostic_vim_to_lsp(vim.diagnostic.get(buffer_id, {
			lnum = fn.line(".") - 1,
		})),
	}

	params.context = context

	return params
end

-- get action tuples
--- @param clients lsp.Client[]
--- @param params table
--- @param buffer_id integer
--- @param callback function
M.get_action_tuples = function(clients, params, buffer_id, callback)
	local action_tuples = {}
	local tmp_number = 0
	for _, client in pairs(clients) do
		client.request(code_action_feature, params, function(err, result, _, _)
			if err ~= nil then
				lib_notify.Warn(string.format("there some error, %s", err))
				return
			end

			tmp_number = tmp_number + 1

			for _, action in pairs(result or {}) do
				-- add a detectto prevent action.title is blank
				if action.title ~= "" then
					-- here must be suitable for alias action_tuple
					table.insert(action_tuples, { action = action, client = client })
				end
			end

			if tmp_number == #clients then
				callback(action_tuples)
			end
		end, buffer_id)
	end
end

-- render the menu for the code actions
--- @param action_tuples action_tuple[]
M.render = function(action_tuples)
	if #action_tuples == 0 then
		lib_notify.Info("no code action!")
		return
	end
	local contents = {}
	local title = "code_action"
	local max_width = 0

	for index, action_tuple in pairs(action_tuples) do
		local action_title = ""
		if action_tuple.action.title then
			action_title = string.format("[%d] %s", index, action_tuple.action.title)
			local action_title_len = fn.strcharlen(action_title)
			max_width = max_width < action_title_len and action_title_len or max_width
		end
		table.insert(contents, action_title)
	end

	local height = #contents

	local new_buffer = api.nvim_create_buf(false, true)

	api.nvim_buf_set_lines(new_buffer, 0, -1, false, contents)
	api.nvim_buf_set_option(new_buffer, "filetype", "LspUI-code_action")
	api.nvim_buf_set_option(new_buffer, "modifiable", false)
	api.nvim_buf_set_option(new_buffer, "bufhidden", "wipe")

	local new_window_wrap = lib_windows.new_window(new_buffer)

	lib_windows.set_width_window(new_window_wrap, max_width + 1)
	lib_windows.set_height_window(new_window_wrap, height)
	lib_windows.set_enter_window(new_window_wrap, true)
	lib_windows.set_anchor_window(new_window_wrap, "NW")
	lib_windows.set_border_window(new_window_wrap, "rounded")
	lib_windows.set_focusable_window(new_window_wrap, true)
	lib_windows.set_relative_window(new_window_wrap, "cursor")
	lib_windows.set_col_window(new_window_wrap, 1)
	lib_windows.set_row_window(new_window_wrap, 1)
	lib_windows.set_style_window(new_window_wrap, "minimal")
	lib_windows.set_right_title_window(new_window_wrap, title)

	local window_id = lib_windows.display_window(new_window_wrap)

	api.nvim_win_set_option(window_id, "winhighlight", "Normal:Normal")
end

-- exec command
-- execute a lsp command, either via client command function (if available)
-- or via workspace/executeCommand (if supported by the server)
-- this func is referred from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp.lua#L1666-L1697C6
--- @param client lsp.Client
--- @param command lsp.Command
--- @param buffer_id integer
--- @param handler? lsp-handler only called if a server command
M.exec_command = function(client, command, buffer_id, handler)
	local cmdname = command.command
	local func = client.commands[cmdname] or lsp.commands[cmdname]
	if func then
		func(command, { bufnr = buffer_id, client_id = client.id })
		return
	end

	-- get the server all available commands
	local command_provider = client.server_capabilities.executeCommandProvider
	local commands = type(command_provider) == "table" and command_provider.commands or {}

	if not vim.list_contains(commands, cmdname) then
		lib_notify.Warn(string.format("Language server `%s` does not support command `%s`", client.name, cmdname))
		return
	end

	local params = {
		command = command.command,
		arguments = command.arguments,
	}

	client.request(exec_command_feature, params, handler, buffer_id)
end

--- @param action lsp.CodeAction|lsp.Command
--- @param client lsp.Client
--- @param buffer_id integer
M.apply_action = function(action, client, buffer_id)
	if action.edit then
		lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
	end
	if action.command then
		local command = type(action.command) == "table" and action.command or action
		M.exec_command(client, command, buffer_id)
	end
end

-- choice action tuple
-- this function is referred from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L639-L675C6
--- @param action_tuple action_tuple
--- @param buffer_id integer
M.choice_action_tupe = function(action_tuple, buffer_id)
	local action = action_tuple.action
	local client = action_tuple.client
	local reg = client.dynamic_capabilities:get(code_action_feature, { bufnr = buffer_id })

	local supports_resolve = vim.tbl_get(reg or {}, "registerOptions", "resolveProvider")
		or client.supports_method(code_action_resolve_feature)
	if not action.edit and client and supports_resolve then
		client.request(
			code_action_resolve_feature,
			action,
			--- @param err lsp.ResponseError
			--- @param resolved_action any
			function(err, resolved_action)
				if err then
					vim.notify(err.code .. ": " .. err.message, vim.log.levels.ERROR)
					return
				end
				M.apply_action(resolved_action, client, buffer_id)
			end,
			buffer_id
		)
	else
		M.apply_action(action, client, buffer_id)
	end
end

return M
