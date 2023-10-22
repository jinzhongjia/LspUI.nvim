local lib_notify = require("LspUI.lib.notify")

return {
    -- init `LspUI` plugin
    --- @param user_config LspUI_config? user's plugin config
    setup = function(user_config)
        if vim.fn.has("nvim-0.10") == 1 then
            vim.schedule(function()
                local config = require("LspUI.config")
                config.setup(user_config)

                local command = require("LspUI.command")
                command.init()

                local modules = require("LspUI.modules")
                for _, module in pairs(modules) do
                    module.init()
                end
            end)
        else
            lib_notify.Warn(
                "The version of neovim needs to be at least 0.10!! you can use branch legacy"
            )
        end
    end,
    api = vim.fn.has("nvim-0.10") == 0 and {} or require("LspUI.api"),
}
