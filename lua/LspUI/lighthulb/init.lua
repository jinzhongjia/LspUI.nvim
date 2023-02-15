local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local store = require("LspUI.lighthulb.store")
local render = require("LspUI.lighthulb.render")
local request = require("LspUI.lighthulb.request")

--[[
	because the lightbulb is  no real-time response required, so we can put it at the end of the loop task
	with use vim.schedule
]]

fn.sign_define(store.SIGN_NAME, { text = config.option.lightbulb.icon })

-- The function is useless but remains
M.run = function()
	if not config.option.lightbulb.enable then
		return
	end
	if not lib.lsp.Check_lsp_active() then
		return
	end
end

M.init = function()
	if not config.option.lightbulb.enable then
		return
	end
	local lightbulb_group = api.nvim_create_augroup("LspuiLightBulb", { clear = true })

	-- This autocmd will delete when nvim is closed.
	api.nvim_create_autocmd("LspAttach", {
		group = lightbulb_group,
		callback = vim.schedule_wrap(function()
			-- get current buffer
			local current_buf = api.nvim_get_current_buf()
			-- The following logic prevents the event from being executed twice, and check the attached server whether support code_action
			if
				lib.util.Tb_has_value(store.buffers, current_buf)
				or (not lib.lsp.Check_lsp_support_codeaction(current_buf))
			then
				return
			end
			-- store it in store.buffers
			table.insert(store.buffers, current_buf)

			local group_id = api.nvim_create_augroup("LspuiLightBulb-" .. tostring(current_buf), { clear = true })

			-- CursorHold CursorMoved
			api.nvim_create_autocmd({ "CursorHold" }, {
				group = group_id,
				buffer = current_buf,
				callback = vim.schedule_wrap(function()
					request.request(current_buf, function(result)
						local status = pcall(render.clean_render, current_buf)
						if status and result then
							render.render(current_buf)
						end
					end)
				end),
				desc = lib.util.Command_des("Lightbulb update when CursorHold"),
			})

			-- clean render when WinLeave
			api.nvim_create_autocmd({ "WinLeave" }, {
				group = group_id,
				buffer = current_buf,
				callback = vim.schedule_wrap(function()
					pcall(render.clean_render, current_buf)
				end),
				desc = lib.util.Command_des("Lightbulb clean render when WinLeave"),
			})
			-- Called when the buffer changes
			-- api.nvim_buf_attach(current_buf, false, {
			-- 	on_lines = function(_, _, _, start_line, _, end_line, _)
			-- 		vim.schedule(function()
			-- 			local current_line = fn.line(".") - 1
			-- 			if start_line <= current_line and current_line <= end_line then
			-- 				request.request(current_buf, function(result)
			-- 					render.clean_render(current_buf)
			-- 					if result then
			-- 						render.render(current_buf)
			-- 					end
			-- 				end)
			-- 			end
			-- 		end)
			-- 	end,
			-- })

			api.nvim_create_autocmd({ "InsertEnter" }, {
				group = group_id,
				buffer = current_buf,
				callback = vim.schedule_wrap(function()
					pcall(render.clean_render, current_buf)
				end),
				desc = lib.util.Command_des("Lightbulb update when InsertEnter"),
			})

			api.nvim_create_autocmd({ "BufWipeout" }, {
				group = group_id,
				buffer = current_buf,
				callback = function()
					lib.util.Tb_remove_value(store.buffers, current_buf)
					api.nvim_del_augroup_by_id(group_id)
				end,
				desc = lib.util.Command_des("Exec clean cmd when QuitPre"),
			})
		end),
		desc = lib.util.Command_des("Lsp attach lightbulb cmd"),
	})
end

return M
