local notify = require("LspUI.layer.notify")

return {
    setup = function(user_config)
        if vim.fn.has("nvim-0.11") ~= 1 then
            return notify.Warn(
                "The version of neovim needs to be at least 0.11!! you can use branch legacy"
            )
        end

        vim.uv
            .new_async(function()
                local config = require("LspUI.config")
                local command = require("LspUI.command")
                local modules = require("LspUI.modules")

                config.setup(user_config)

                vim.schedule(function()
                    -- 初始化命令系统
                    if command and command.init then
                        command.init()
                    else
                        notify.Error(
                            "LspUI: Command module initialization failed"
                        )
                    end

                    -- 初始化各个模块
                    for name, module in pairs(modules) do
                        if module and type(module.init) == "function" then
                            local ok, err = pcall(module.init)
                            if not ok then
                                notify.Error(
                                    string.format(
                                        "Failed to initialize module %s: %s",
                                        name,
                                        err
                                    )
                                )
                            end
                        else
                            notify.Warn(
                                string.format(
                                    "Module %s is missing init method or is not a valid module",
                                    name
                                )
                            )
                        end
                    end
                end)
            end)
            :send()
    end,
    api = vim.fn.has("nvim-0.11") == 1 and require("LspUI.api") or {},
}
