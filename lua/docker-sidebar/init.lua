local config = require("docker-sidebar.config")

local M = {}

--- Initialize the configuration for the docker-sidebar plugin and register user commands.
--- @param opts DockerSidebar.Config|nil User-provided configuration options to override defaults
function M.setup(opts)
	if opts ~= nil then
		vim.validate("opts", opts, "table")
		vim.validate("opts.runner", opts.runner, { "nil", "string", "function" }, true)
		vim.validate("opts.compose", opts.compose, "table", true)
		vim.validate("opts.sidebar", opts.sidebar, "table", true)
		vim.validate("opts.icons", opts.icons, "table", true)
		vim.validate("opts.highlight", opts.highlight, "table", true)
	end
	local new_config = vim.tbl_deep_extend("force", config.current or config.default, opts or {})
	config.update(new_config)

	vim.api.nvim_create_user_command("DockerSidebarToggle", M.toggle, { nargs = 0 })
	vim.api.nvim_create_user_command("DockerSidebarRefresh", M.refresh, { nargs = 0 })
end

function M.toggle()
	require("docker-sidebar.sidebar").toggle()
end

function M.refresh()
	require("docker-sidebar.sidebar").refresh()
end

return M
