local notify = require("LspUI.layer.notify")

return {
    --- 插件入口；接受用户传入的配置并 deep-merge 到默认配置上，然后初始化所有模块
    --- @param user_config LspUI_config? 用户配置；省略时使用默认配置
    setup = function(user_config)
        if vim.fn.has("nvim-0.11") ~= 1 then
            return notify.Warn(
                "The version of neovim needs to be at least 0.11!! you can use branch legacy"
            )
        end

        vim.schedule(function()
            local config = require("LspUI.config")
            local command = require("LspUI.command")
            local modules = require("LspUI.modules")

            config.setup(user_config)

            -- 初始化命令系统
            if command and command.init then
                command.init()
            else
                notify.Error("LspUI: Command module initialization failed")
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
    end,
    api = vim.fn.has("nvim-0.11") == 1 and require("LspUI.api") or {},
}
