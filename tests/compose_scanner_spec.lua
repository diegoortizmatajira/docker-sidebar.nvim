local compose_scanner = require("docker-sidebar.compose_scanner")
local config = require("docker-sidebar.config")

describe("compose_scanner", function()
	describe("find_compose_files", function()
		local root

		before_each(function()
			root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
			config.current = vim.tbl_deep_extend("force", {}, config.default)
		end)

		after_each(function()
			vim.fn.delete(root, "rf")
			config.current = nil
		end)

		it("finds compose files matching the configured patterns", function()
			vim.fn.mkdir(root .. "/service-a", "p")
			vim.fn.writefile({ "services: {}" }, root .. "/service-a/docker-compose.yml")
			vim.fn.writefile({ "not a compose file" }, root .. "/service-a/readme.txt")

			config.current.compose = {
				project_dirs = { root },
				file_patterns = { "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml" },
				scan_depth = 3,
			}

			local files = compose_scanner.find_compose_files()
			assert.are.equal(1, #files)
			assert.is_truthy(files[1]:match("docker%-compose%.yml$"))
		end)

		it("respects scan_depth", function()
			vim.fn.mkdir(root .. "/a/b/c", "p")
			vim.fn.writefile({ "services: {}" }, root .. "/a/b/c/docker-compose.yml")

			config.current.compose = {
				project_dirs = { root },
				file_patterns = { "docker-compose.yml" },
				scan_depth = 1,
			}

			assert.are.same({}, compose_scanner.find_compose_files())
		end)
	end)

	describe("resolve_compose_file", function()
		local previous_system

		before_each(function()
			previous_system = vim.system
		end)

		after_each(function()
			vim.system = previous_system
		end)

		it("resolves a compose file via `docker compose config`", function()
			vim.system = function(cmd)
				assert.are.same({
					"docker",
					"compose",
					"-f",
					"/tmp/project/docker-compose.yml",
					"config",
					"--format",
					"json",
				}, cmd)
				return {
					wait = function()
						return {
							code = 0,
							stdout = '{"name":"myapp","services":{"web":{},"db":{}},"networks":{"default":{}},"volumes":{"db-data":{}}}',
						}
					end,
				}
			end
			local resolved = compose_scanner.resolve_compose_file("/tmp/project/docker-compose.yml")
			assert.are.equal("myapp", resolved.name)
			assert.are.equal(2, #resolved.services)
			assert.are.equal(1, #resolved.networks)
			assert.are.equal(1, #resolved.volumes)
			assert.are.equal("/tmp/project", resolved.cwd)
		end)

		it("returns nil when the command fails", function()
			vim.system = function()
				return {
					wait = function()
						return { code = 1, stderr = "invalid compose file" }
					end,
				}
			end
			assert.is_nil(compose_scanner.resolve_compose_file("/tmp/project/docker-compose.yml"))
		end)
	end)
end)
