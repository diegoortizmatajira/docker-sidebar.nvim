local config = require("docker-sidebar.config")

describe("config", function()
	describe("default", function()
		it("has runner unset by default", function()
			assert.is_nil(config.default.runner)
		end)

		it("has compose scan configuration", function()
			assert.is_function(config.default.compose.project_dirs)
			assert.is_table(config.default.compose.project_dirs())
			assert.is_table(config.default.compose.file_patterns)
			assert.is_true(#config.default.compose.file_patterns > 0)
			assert.is_number(config.default.compose.scan_depth)
			assert.is_true(config.default.compose.scan_depth > 0)
		end)

		it("has all sidebar keybindings", function()
			local kb = config.default.sidebar.keybindings
			local actions = {
				"toggle_expand",
				"expand",
				"collapse",
				"quit",
				"refresh",
				"refresh_all",
				"start",
				"stop",
				"restart",
				"pause",
				"unpause",
				"remove",
				"logs",
				"exec",
				"help",
				"up",
				"down",
				"edit",
				"inspect",
			}
			for _, action in ipairs(actions) do
				assert.is_table(kb[action], "missing keybinding for: " .. action)
			end
		end)

		it("defaults sidebar.confirm_destructive to true", function()
			assert.is_true(config.default.sidebar.confirm_destructive)
		end)

		it("has icon and status icon configurations", function()
			assert.is_table(config.default.icons.tree)
			assert.is_table(config.default.icons.status)
			assert.is_string(config.default.icons.status.running)
			assert.is_string(config.default.icons.status.stopped)
			assert.is_string(config.default.icons.status.paused)
		end)

		it("has highlight configurations", function()
			assert.is_table(config.default.highlight.tree)
			assert.is_table(config.default.highlight.status)
		end)
	end)

	describe("update", function()
		after_each(function()
			config.current = nil
		end)

		it("sets current config", function()
			config.update({ test = true })
			assert.is_true(config.current.test)
		end)

		it("ignores nil input", function()
			config.update(nil)
			assert.is_nil(config.current)
		end)
	end)
end)
