local api, fn = vim.api, vim.fn
local lib_notify = require("LspUI.lib.notify")
local lib_util = require("LspUI.lib.util")
local config = require("LspUI.config")
local util = require("LspUI.lighthulb.util")

local M = {}

-- whether this module has initialized
local is_initialized = false

local lightbulb_group = api.nvim_create_augroup("Lspui_lightBulb", { clear = true })

M.init = function()
	if not config.options.lighthulb.enable then
		return
	end

	if is_initialized then
		return
	end

	is_initialized = true

	-- register sign, should only be called once
	util.register_sign()

	-- here is just no cache option
	api.nvim_create_autocmd("LspAttach", {
		group = lightbulb_group,
		callback = function()
			-- get current buffer
			local current_buffer = api.nvim_get_current_buf()
			local group_id = api.nvim_create_augroup("Lspui_lightBulb_" .. tostring(current_buffer), { clear = true })

			api.nvim_create_autocmd({ "CursorHold" }, {
				group = group_id,
				buffer = current_buffer,
				callback = vim.schedule_wrap(function()
					util.request(current_buffer, function(result)
						if result then
							util.clear_render()
							util.render(current_buffer, fn.line("."))
						end
					end)
				end),
				desc = lib_util.command_desc("Lightbulb update when CursorHold"),
			})

			api.nvim_create_autocmd({ "InsertEnter" }, {
				group = group_id,
				buffer = current_buffer,
				callback = function()
					util.clear_render()
				end,
				desc = lib_util.command_desc("Lightbulb update when InsertEnter"),
			})

			api.nvim_create_autocmd({ "BufWipeout" }, {
				group = group_id,
				buffer = current_buffer,
				callback = function()
					api.nvim_del_augroup_by_id(group_id)
				end,
				desc = lib_util.command_desc("Exec clean cmd when QuitPre"),
			})
		end,
		desc = lib_util.command_desc("Lsp attach lightbulb cmd"),
	})
end

M.run = function()
	lib_notify.Info("lighthulb has no run func")
end

return M
