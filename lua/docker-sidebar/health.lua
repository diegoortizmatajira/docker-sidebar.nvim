local M = {}

function M.check()
	vim.health.start("docker-sidebar")

	local utils = require("docker-sidebar.utils")

	-- Hard requirements: this plugin is Docker-only, unlike db-cli-adapter's multi-adapter
	-- warn-only checks, so a missing `docker` CLI is an error, not a warning.
	utils.check_executable("docker", "error")

	if utils.is_executable("docker") then
		local ok, result = pcall(function()
			return vim.system({ "docker", "compose", "version" }, { text = true }):wait()
		end)
		if ok and result.code == 0 then
			vim.health.ok("'docker compose' (Compose v2 plugin) is available")
		else
			vim.health.error("'docker compose' is not available", {
				"Install the Docker Compose v2 plugin (https://docs.docker.com/compose/install/)",
			})
		end
	end

	local has_nui = pcall(require, "nui.split")
	if has_nui then
		vim.health.ok("nui.nvim installed")
	else
		vim.health.error("nui.nvim not found", { "Install MunifTanjim/nui.nvim" })
	end

	local has_overseer = pcall(require, "overseer")
	if has_overseer then
		vim.health.ok("overseer.nvim installed")
	else
		vim.health.warn(
			"overseer.nvim not found (optional, needed for runner = 'overseer')",
			{ "Install stevearc/overseer.nvim" }
		)
	end
end

return M
