local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

M.Lock_cursor = function(buffer, win_id, action_num)
	api.nvim_create_autocmd("CursorMoved", {
		buffer = buffer,
		callback = function()
			local _, lnum, col, _ = unpack(vim.fn.getpos("."))
			if lnum <= 2 then
				api.nvim_win_set_cursor(win_id, { 3, 1 })
				return
			elseif lnum > action_num + 2 then
				api.nvim_win_set_cursor(win_id, { 3, 1 })
				return
			end
			if col ~= 2 then
				api.nvim_win_set_cursor(win_id, { lnum, 1 })
			end
		end,
		desc = lib.util.Command_des("Lock the cursor"),
	})
end

M.Keybinding = function(buffer, win_id, actions, ctx)
	-- bind the func to next
	api.nvim_buf_set_keymap(buffer, "n", config.option.code_action.keybind.next, "", {
		callback = function()
			local _, lnum, _, _ = unpack(vim.fn.getpos("."))
			lnum = lnum + 1
			if lnum > #actions + 2 then
				api.nvim_win_set_cursor(win_id, { 3, 1 })
			else
				api.nvim_win_set_cursor(win_id, { lnum, 1 })
			end
		end,
		desc = lib.util.Command_des("go to next action"),
	})
	-- bind the func to prev
	api.nvim_buf_set_keymap(buffer, "n", config.option.code_action.keybind.prev, "", {
		callback = function()
			local _, lnum, _, _ = unpack(vim.fn.getpos("."))
			lnum = lnum - 1
			if lnum < 3 then
				api.nvim_win_set_cursor(win_id, { #actions + 2, 1 })
			else
				api.nvim_win_set_cursor(win_id, { lnum, 1 })
			end
		end,
		desc = lib.util.Command_des("go to next action"),
	})
	-- bind the func to quit
	api.nvim_buf_set_keymap(buffer, "n", config.option.code_action.keybind.quit, "", {
		callback = function()
			-- the buffer will be deleted automatically when windows closed
			api.nvim_win_close(win_id, true)
		end,
		desc = lib.util.Command_des("quit from code_action"),
	})
	-- bind the func to exec
	api.nvim_buf_set_keymap(buffer, "n", config.option.code_action.keybind.exec, "", {
		callback = function()
			-- the buffer will be deleted automatically when windows closed
			local action_num = tonumber(fn.expand("<cword>"))
			local action_tuple = actions[action_num]
			M.Exec_action(action_tuple, ctx)
			api.nvim_win_close(win_id, true)
		end,
		desc = lib.util.Command_des("exec code action"),
	})
	-- bind number keys to exec

	for index, action_tuple in pairs(actions) do
		api.nvim_buf_set_keymap(buffer, "n", tostring(index), "", {
			callback = function()
				M.Exec_action(action_tuple, ctx)
				api.nvim_win_close(win_id, true)
			end,
			desc = lib.util.Command_des("exec code action by number keys"),
		})
	end
end

local function apply_action(action, client, ctx)
	if action.edit then
		lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
	end
	if action.command then
		local command = type(action.command) == "table" and action.command or action
		local func = client.commands[command.command] or vim.lsp.commands[command.command]
		if func then
			local enriched_ctx = vim.deepcopy(ctx)
			enriched_ctx.client_id = client.id
			func(command, enriched_ctx)
		else
			-- Not using command directly to exclude extra properties,
			-- see https://github.com/python-lsp/python-lsp-server/issues/146
			local params = {
				command = command.command,
				arguments = command.arguments,
				workDoneToken = command.workDoneToken,
			}

			client.request("workspace/executeCommand", params, nil, ctx.bufnr)
		end
	end
end

M.Exec_action = function(action_tuple, ctx)
	local action = action_tuple.action
	local client = lsp.get_client_by_id(action_tuple.id)
	if
		not action.edit
		and client
		and vim.tbl_get(client.server_capabilities, "codeActionProvider", "resolveProvider")
	then
		client.request("codeAction/resolve", action, function(err, resolved_action)
			if err then
				lib.Error(err.code .. ": " .. err.message)
				return
			end
			apply_action(resolved_action, client, ctx)
		end)
	else
		apply_action(action, client, ctx)
	end
end

M.diagnostic_vim_to_lsp = function(diagnostics)
	return vim.tbl_map(function(diagnostic)
		return vim.tbl_extend("keep", {
			range = {
				start = {
					line = diagnostic.lnum,
					character = diagnostic.col,
				},
				["end"] = {
					line = diagnostic.end_lnum,
					character = diagnostic.end_col,
				},
			},
			severity = type(diagnostic.severity) == "string" and vim.diagnostic.severity[diagnostic.severity]
				or diagnostic.severity,
			message = diagnostic.message,
			source = diagnostic.source,
			code = diagnostic.code,
		}, diagnostic.user_data and (diagnostic.user_data.lsp or {}) or {})
	end, diagnostics)
end

return M
