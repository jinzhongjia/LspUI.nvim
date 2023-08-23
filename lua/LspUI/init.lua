local lib_notify = require("LspUI.lib.notify")

return {
    -- init `LspUI` plugin
    --- @param user_config LspUI_config? user's plugin config
    setup = function(user_config)
        if vim.fn.has("nvim-0.10") == 1 then
            local command = require("LspUI.command")
            local config = require("LspUI.config")
            local modules = require("LspUI.modules")

            config.setup(user_config)
            command.init()
            for _, module in pairs(modules) do
                module.init()
            end
        else
            lib_notify.Warn("The version of neovim needs to be at least 0.10!! you can use branch legacy")
        end
    end,
    api = vim.fn.has("nvim-0.10") == 0 and {} or require("LspUI.api"),
}
