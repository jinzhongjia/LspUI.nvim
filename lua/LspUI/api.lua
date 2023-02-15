local modules = require("LspUI.modules")

local M = {}
M.api = {
	peek_definition = modules.peek_definition.run,
	code_action = modules.code_action.run,
	hover = modules.hover.run,
	rename = modules.rename.run,
  -- args: next prev
	diagnostic = modules.diagnostic.run,
}

return M
