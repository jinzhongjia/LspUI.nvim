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
                    -- 先初始化命令系统
                    if command and command.init then
                        command.init()
                    else
                        lib_notify.Error("LspUI: 命令模块初始化失败")
                    end

                    -- 添加防御性检查和错误处理，确保每个模块都有init方法
                    for name, module in pairs(modules) do
                        if module and type(module.init) == "function" then
                            local ok, err = pcall(module.init)
                            if not ok then
                                lib_notify.Error(
                                    string.format(
                                        "初始化模块 %s 失败: %s",
                                        name,
                                        err
                                    )
                                )
                            end
                        else
                            lib_notify.Warn(
                                string.format(
                                    "模块 %s 缺少init方法或不是有效模块",
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
