local lib_notify = require("LspUI.lib.notify")

return {
    -- init `LspUI` plugin
    --- @param user_config LspUI_config? user's plugin config
    setup = function(user_config)
        if vim.fn.has("nvim-0.10") == 1 then
            local async, message = vim.uv.new_async(function()
                local config = require("LspUI.config")
                local command = require("LspUI.command")
                local modules = require("LspUI.modules")
                config.setup(user_config)
                vim.schedule(function()
                    command.init()
                    for _, module in pairs(modules) do
                        module.init()
                    end
                end)
            end)
            if async then
                async:send()
            else
                lib_notify.Error(string.format("err,%s", message))
            end
        else
            lib_notify.Warn(
                "The version of neovim needs to be at least 0.10!! you can use branch legacy"
            )
        end
    end,
    api = vim.fn.has("nvim-0.10") == 0 and {} or require("LspUI.api"),
}
