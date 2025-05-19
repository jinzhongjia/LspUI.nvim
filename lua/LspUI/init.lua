local lib_notify = require("LspUI.layer.notify")

return {
    -- init `LspUI` plugin
    --- @param user_config LspUI_config? user's plugin config
    setup = function(user_config)
        if vim.fn.has("nvim-0.11") == 1 then
            local async, message = vim.uv.new_async(function()
                local config = require("LspUI.config")
                local command = require("LspUI.command")
                local modules = require("LspUI.modules")

                config.setup(user_config)

                vim.schedule(function()
                    -- Initialize the command system first
                    if command and command.init then
                        command.init()
                    else
                        lib_notify.Error(
                            "LspUI: Command module initialization failed"
                        )
                    end

                    -- Add defensive checks and error handling to ensure each module has an init method
                    for name, module in pairs(modules) do
                        if module and type(module.init) == "function" then
                            local ok, err = pcall(module.init)
                            if not ok then
                                lib_notify.Error(
                                    string.format(
                                        "Failed to initialize module %s: %s",
                                        name,
                                        err
                                    )
                                )
                            end
                        else
                            lib_notify.Warn(
                                string.format(
                                    "Module %s is missing init method or is not a valid module",
                                    name
                                )
                            )
                        end
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
                "The version of neovim needs to be at least 0.11!! you can use branch legacy"
            )
        end
    end,
    api = vim.fn.has("nvim-0.11") == 0 and {} or require("LspUI.api"),
}
