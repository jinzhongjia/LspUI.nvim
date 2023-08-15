local api = require("LspUI.api")
local command = require("LspUI.command")
local config = require("LspUI.config")
local modules = require("LspUI.modules")

return {
    -- init `LspUI` plugin
    --- @param user_config LspUI_config? user's plugin config
    setup = function(user_config)
        config.setup(user_config)
        command.init()
        for _, module in pairs(modules) do
            module.init()
        end
    end,
    api = api.api,
}
