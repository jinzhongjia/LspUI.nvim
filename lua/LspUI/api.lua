local modules = require("LspUI.modules")

local M = {}

-- A brief description:
-- you can just require this file through
-- ```lua
-- local api = require("LspUI").api
-- api.peek_definition()
-- api.code_action()
-- api.hover()
-- api.rename()
-- api.diagnostic("next")
-- api.diagnostic("prev")
-- ````
--
-- Note: now the hover, there are still some problems with rendering markdown colors,
-- although I have referred to the official solution (there are also cases where rendering colors are wrong)

M.api = {
	peek_definition = modules.peek_definition.run,
	code_action = modules.code_action.run,
	hover = modules.hover.run,
	rename = modules.rename.run,
	-- args: next prev
	diagnostic = modules.diagnostic.run,
}

return M
