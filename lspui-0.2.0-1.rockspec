package = "LspUI"
version = "0.2.0-1"
source = {
    url = "git+ssh://git@github.com/jinzhongjia/LspUI.nvim.git",
}
description = {
    summary = "A plugin which wraps Neovim LSP operations with a nicer UI.",
    detailed = "A plugin which wraps Neovim LSP operations with a nicer UI.",
    homepage = "https://github.com/jinzhongjia/LspUI.nvim",
    license = "MIT",
}
dependencies = {
    "lua >= 5.1",
}
build = {
    type = "builtin",
    modules = {
        ["LspUI._meta"] = "lua/LspUI/_meta.lua",
        ["LspUI.api"] = "lua/LspUI/api.lua",
        ["LspUI.call_hierarchy.init"] = "lua/LspUI/call_hierarchy/init.lua",
        ["LspUI.call_hierarchy.util"] = "lua/LspUI/call_hierarchy/util.lua",
        ["LspUI.code_action.init"] = "lua/LspUI/code_action/init.lua",
        ["LspUI.code_action.register"] = "lua/LspUI/code_action/register.lua",
        ["LspUI.code_action.util"] = "lua/LspUI/code_action/util.lua",
        ["LspUI.command"] = "lua/LspUI/command.lua",
        ["LspUI.config"] = "lua/LspUI/config.lua",
        ["LspUI.declaration.init"] = "lua/LspUI/declaration/init.lua",
        ["LspUI.declaration.util"] = "lua/LspUI/declaration/util.lua",
        ["LspUI.definition.init"] = "lua/LspUI/definition/init.lua",
        ["LspUI.definition.util"] = "lua/LspUI/definition/util.lua",
        ["LspUI.diagnostic.init"] = "lua/LspUI/diagnostic/init.lua",
        ["LspUI.diagnostic.util"] = "lua/LspUI/diagnostic/util.lua",
        ["LspUI.global"] = "lua/LspUI/global.lua",
        ["LspUI.hover.init"] = "lua/LspUI/hover/init.lua",
        ["LspUI.hover.util"] = "lua/LspUI/hover/util.lua",
        ["LspUI.implementation.init"] = "lua/LspUI/implementation/init.lua",
        ["LspUI.implementation.util"] = "lua/LspUI/implementation/util.lua",
        ["LspUI.init"] = "lua/LspUI/init.lua",
        ["LspUI.inlay_hint.init"] = "lua/LspUI/inlay_hint/init.lua",
        ["LspUI.lib.debug"] = "lua/LspUI/lib/debug.lua",
        ["LspUI.lib.lsp"] = "lua/LspUI/lib/lsp.lua",
        ["LspUI.lib.notify"] = "lua/LspUI/lib/notify.lua",
        ["LspUI.lib.util"] = "lua/LspUI/lib/util.lua",
        ["LspUI.lib.windows"] = "lua/LspUI/lib/windows.lua",
        ["LspUI.lightbulb.init"] = "lua/LspUI/lightbulb/init.lua",
        ["LspUI.lightbulb.util"] = "lua/LspUI/lightbulb/util.lua",
        ["LspUI.modules"] = "lua/LspUI/modules.lua",
        ["LspUI.pos_abstract"] = "lua/LspUI/pos_abstract.lua",
        ["LspUI.reference.init"] = "lua/LspUI/reference/init.lua",
        ["LspUI.reference.util"] = "lua/LspUI/reference/util.lua",
        ["LspUI.rename.init"] = "lua/LspUI/rename/init.lua",
        ["LspUI.rename.util"] = "lua/LspUI/rename/util.lua",
        ["LspUI.type_definition.init"] = "lua/LspUI/type_definition/init.lua",
        ["LspUI.type_definition.util"] = "lua/LspUI/type_definition/util.lua",
    },
}
