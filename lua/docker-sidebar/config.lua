local C = {
	--- @type DockerSidebar.Config
	default = {
		-- nil (default)  -> built-in jobstart runner (background) / built-in terminal split (interactive)
		-- "overseer"     -> route both modes through overseer.nvim (terminal strategy)
		-- function(spec, callback) ... end -> fully custom runner
		runner = nil,

		compose = {
			project_dirs = function()
				return { vim.fn.getcwd() }
			end,
			file_patterns = { "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml" },
			scan_depth = 3,
		},

		sidebar = {
			keybindings = {
				toggle_expand = { "t", "<CR>" },
				expand = { "o" },
				collapse = { "c" },
				quit = { "q" },
				refresh = { "r" },
				refresh_all = { "R" },
				start = { "s" },
				stop = { "S" },
				restart = { "x" },
				pause = { "p" },
				unpause = { "P" },
				remove = { "d" },
				logs = { "l" },
				exec = { "e" },
				up = { "u" },
				down = { "U" },
				help = { "?" },
			},
			-- Gate deployment `down` and service/container `remove` behind a vim.fn.confirm prompt
			confirm_destructive = true,
		},

		icons = {
			tree = {
				chevron_open = " ",
				chevron_closed = " ",
				deployments_group = " ",
				standalone_group = " ",
				deployment = "󰡨 ",
				services_group = " ",
				networks_group = "󰛳 ",
				volumes_group = "󰆺 ",
				network = "󰛳 ",
				volume = "󰆺 ",
			},
			status = {
				running = "● ",
				stopped = "○ ",
				paused = "⏸ ",
				restarting = "↻ ",
				other = "? ",
			},
		},

		highlight = {
			tree = {
				chevron = "@constant",
				default_icon = "@symbol",
				folder = "@symbol",
				deployment = "@type",
				network = "@macro",
				volume = "@macro",
			},
			status = {
				running = "DiagnosticOk",
				stopped = "Comment",
				paused = "DiagnosticWarn",
				restarting = "DiagnosticWarn",
				other = "DiagnosticHint",
			},
		},
	},
	--- @type DockerSidebar.Config|nil
	current = nil,
}

--- Updates the current configuration with a new configuration.
--- If the provided configuration is not a table or is nil, the update is ignored.
--- @param new_config DockerSidebar.Config The new configuration to set as the current configuration.
function C.update(new_config)
	if not new_config then
		return
	end
	C.current = new_config
end

return C
