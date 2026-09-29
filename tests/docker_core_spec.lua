local compose_scanner = require("docker-sidebar.compose_scanner")
local docker = require("docker-sidebar.docker")
local docker_core = require("docker-sidebar.docker_core")

describe("docker_core", function()
	local originals

	before_each(function()
		originals = {
			list_compose_projects = docker.list_compose_projects,
			list_compose_containers = docker.list_compose_containers,
			list_compose_networks = docker.list_compose_networks,
			list_compose_volumes = docker.list_compose_volumes,
			list_standalone_containers = docker.list_standalone_containers,
			scan = compose_scanner.scan,
		}
	end)

	after_each(function()
		docker.list_compose_projects = originals.list_compose_projects
		docker.list_compose_containers = originals.list_compose_containers
		docker.list_compose_networks = originals.list_compose_networks
		docker.list_compose_volumes = originals.list_compose_volumes
		docker.list_standalone_containers = originals.list_standalone_containers
		compose_scanner.scan = originals.scan
	end)

	describe("get_deployments", function()
		it("prefers live state and uses the scanned config_file/cwd when both are known", function()
			docker.list_compose_projects = function()
				return { { Name = "myapp", Status = "running(1)", ConfigFiles = "/live/docker-compose.yml" } }
			end
			docker.list_compose_containers = function(project)
				assert.are.equal("myapp", project)
				return {
					{
						id = "abc",
						name = "myapp-web-1",
						image = "nginx",
						state = "running",
						status = "Up",
						project = "myapp",
						service = "web",
					},
				}
			end
			docker.list_compose_networks = function()
				return {}
			end
			docker.list_compose_volumes = function()
				return {}
			end
			compose_scanner.scan = function()
				return {
					myapp = {
						name = "myapp",
						services = { "web" },
						networks = {},
						volumes = {},
						config_file = "/scanned/docker-compose.yml",
						cwd = "/scanned",
					},
				}
			end

			local deployments = docker_core.get_deployments()
			assert.are.equal(1, #deployments)
			assert.are.equal("myapp", deployments[1].project)
			assert.are.equal("running", deployments[1].state)
			assert.are.equal("/scanned/docker-compose.yml", deployments[1].config_file)
			assert.are.equal("/scanned", deployments[1].cwd)
		end)

		it("marks scan-only projects as down with synthesized services", function()
			docker.list_compose_projects = function()
				return {}
			end
			compose_scanner.scan = function()
				return {
					neverstarted = {
						name = "neverstarted",
						services = { "web", "db" },
						networks = {},
						volumes = {},
						config_file = "/scanned/docker-compose.yml",
						cwd = "/scanned",
					},
				}
			end

			local deployments = docker_core.get_deployments()
			assert.are.equal(1, #deployments)
			assert.are.equal("down", deployments[1].state)
			assert.are.equal(2, #deployments[1].containers)
			assert.are.equal("stopped", deployments[1].containers[1].state)
		end)

		it("includes live-only projects with a nil config_file when nothing was scanned", function()
			docker.list_compose_projects = function()
				return { { Name = "external", Status = "running(1)", ConfigFiles = "" } }
			end
			docker.list_compose_containers = function()
				return {
					{
						id = "x",
						name = "external-web-1",
						image = "nginx",
						state = "running",
						status = "Up",
						project = "external",
						service = "web",
					},
				}
			end
			docker.list_compose_networks = function()
				return {}
			end
			docker.list_compose_volumes = function()
				return {}
			end
			compose_scanner.scan = function()
				return {}
			end

			local deployments = docker_core.get_deployments()
			assert.are.equal(1, #deployments)
			assert.is_nil(deployments[1].config_file)
		end)

		it("reports partial state when some containers are stopped", function()
			docker.list_compose_projects = function()
				return { { Name = "mixed", Status = "", ConfigFiles = "" } }
			end
			docker.list_compose_containers = function()
				return {
					{
						id = "a",
						name = "mixed-web-1",
						image = "nginx",
						state = "running",
						status = "Up",
						project = "mixed",
						service = "web",
					},
					{
						id = "b",
						name = "mixed-db-1",
						image = "postgres",
						state = "stopped",
						status = "Exited",
						project = "mixed",
						service = "db",
					},
				}
			end
			docker.list_compose_networks = function()
				return {}
			end
			docker.list_compose_volumes = function()
				return {}
			end
			compose_scanner.scan = function()
				return {}
			end

			local deployments = docker_core.get_deployments()
			assert.are.equal("partial", deployments[1].state)
		end)
	end)

	describe("get_standalone_containers", function()
		it("delegates to docker.list_standalone_containers", function()
			docker.list_standalone_containers = function()
				return { { id = "x", name = "box", image = "alpine", state = "running", status = "Up" } }
			end
			local standalone = docker_core.get_standalone_containers()
			assert.are.equal(1, #standalone)
			assert.are.equal("box", standalone[1].name)
		end)
	end)
end)
