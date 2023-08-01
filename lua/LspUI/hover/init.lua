local lsp, fn, api = vim.lsp, vim.fn, vim.api

local lib = require("LspUI.lib")
local config = require("LspUI.config")

local M = {}

local request = require("LspUI.hover.request")
local autoCmd = require("LspUI.hover.autoCmd")
local util = require("LspUI.hover.util")

local hover_win_id = -1

M.init = function()
	if not config.option.hover.enable then
		return
	end

	if not lib.lsp.Check_lsp_active() then
		return
	end
end

M.run = function()
	if not config.option.hover.enable then
		return
	end

	if not lib.lsp.Check_lsp_active() then
		return
	end

	request.Request(function(content_list)
		if api.nvim_win_is_valid(hover_win_id) then
			api.nvim_set_current_win(hover_win_id)
		else
			if vim.tbl_isempty(content_list) then
				lib.log.Info("No hover document!")
				return
			end
			local res = content_list[1]

			--- why add this judgement?
			--- because some language server implmenment is not perface, such as py-lsp will return empty
			--- string on some variable keyword
			if type(res) == "string" then
				if string.len(res) > 0 then
					lib.log.Info(res)
				end
				return
			end

			-- why add this judgement ?
			-- because some language server's document implmement is not perfect, for example "zls"
			-- such as some empty hover document will return a table like { { } },
			-- this is clearly a mistake
			if vim.tbl_isempty(res) then
				lib.log.Info("No hover document!")
				return
			end

			local content_id = 1

			local current_buffer = api.nvim_get_current_buf()
			local new_buffer = api.nvim_create_buf(false, true)

			local width, height, content = util.Handle_content(new_buffer, res)

			content = lib.wrap.Wrap(content, width)

			width, height = lib.windows.Min_size_from_content(content)

			local content_wrap = {
				contents = content,
				buffer = new_buffer,
				height = height,
				width = width,
				enter = false,
				modify = false,
				title = tostring(content_id) .. "/" .. tostring(#content_list),
			}

			_, hover_win_id = lib.windows.Create_window(content_wrap)

			api.nvim_win_set_option(hover_win_id, "conceallevel", 2)
			api.nvim_win_set_option(hover_win_id, "concealcursor", "n")
			api.nvim_win_set_option(hover_win_id, "wrap", false)
			--  Here is autocmd
			autoCmd.auto_cmd(current_buffer, new_buffer, hover_win_id)

			-- Here is keybind
			--
			-- next hover document render
			api.nvim_buf_set_keymap(new_buffer, "n", config.option.hover.keybind.next, "", {
				callback = function()
					if #content_list == 1 then
						return
					end
					if content_id == #content_list then
						content_id = 1
					else
						content_id = content_id + 1
					end

					util.Update_win(new_buffer, hover_win_id, content_list, content_id)
				end,
				desc = lib.util.Command_des("go to next hover"),
			})
			-- prev hover document render
			api.nvim_buf_set_keymap(new_buffer, "n", config.option.hover.keybind.prev, "", {
				callback = function()
					if #content_list == 1 then
						return
					end
					if content_id == 1 then
						content_id = #content_list
					else
						content_id = content_id - 1
					end
					util.Update_win(new_buffer, hover_win_id, content_list, content_id)
				end,
				desc = lib.util.Command_des("go to prev hover"),
			})
			-- quit
			api.nvim_buf_set_keymap(new_buffer, "n", config.option.hover.keybind.quit, "", {
				callback = function()
					api.nvim_win_close(hover_win_id, true)
				end,
				desc = lib.util.Command_des("quit hover document"),
			})
		end
	end)
end

return M
