local docker = require("docker-sidebar.docker")

describe("docker", function()
	local previous_system

	before_each(function()
		previous_system = vim.system
	end)

	after_each(function()
		vim.system = previous_system
	end)

	--- @param responses table<string, {code?: integer, stdout?: string, stderr?: string}>
	local function stub_system(responses)
		vim.system = function(cmd)
			local key = table.concat(cmd, " ")
			local response = responses[key]
			assert.is_not_nil(response, "unexpected command: " .. key)
			return {
				wait = function()
					return { code = response.code or 0, stdout = response.stdout or "", stderr = response.stderr or "" }
				end,
			}
		end
	end

	describe("list_compose_projects", function()
		it("parses the JSON array", function()
			stub_system({
				["docker compose ls -a --format json"] = {
					stdout = '[{"Name":"myapp","Status":"running(2)","ConfigFiles":"/path/docker-compose.yaml"}]',
				},
			})
			local projects = docker.list_compose_projects()
			assert.are.equal(1, #projects)
			assert.are.equal("myapp", projects[1].Name)
			assert.are.equal("running(2)", projects[1].Status)
		end)

		it("returns an empty list when the command fails", function()
			stub_system({
				["docker compose ls -a --format json"] = { code = 1, stderr = "docker: command not found" },
			})
			assert.are.same({}, docker.list_compose_projects())
		end)
	end)

	describe("list_compose_containers", function()
		it("maps NDJSON rows to ContainerInfo", function()
			stub_system({
				["docker compose -p myapp ps -a --format json"] = {
					stdout = table.concat({
						'{"ID":"abc123","Name":"myapp-web-1","Image":"nginx","State":"running","Status":"Up 2 hours","Project":"myapp","Service":"web"}',
						'{"ID":"def456","Name":"myapp-db-1","Image":"postgres","State":"exited","Status":"Exited (0)","Project":"myapp","Service":"db"}',
					}, "\n"),
				},
			})
			local containers = docker.list_compose_containers("myapp")
			assert.are.equal(2, #containers)
			assert.are.equal("running", containers[1].state)
			assert.are.equal("web", containers[1].service)
			assert.are.equal("stopped", containers[2].state)
		end)
	end)

	describe("list_all_containers / list_standalone_containers", function()
		it("derives project/service from compose labels and filters standalone", function()
			stub_system({
				["docker ps -a --format json"] = {
					stdout = table.concat({
						'{"ID":"abc123","Names":"myapp-web-1","Image":"nginx","State":"running","Status":"Up 2 hours",'
							.. '"Labels":"com.docker.compose.project=myapp,com.docker.compose.service=web"}',
						'{"ID":"xyz789","Names":"standalone-box","Image":"alpine","State":"running","Status":"Up 1 day","Labels":""}',
					}, "\n"),
				},
			})
			local all = docker.list_all_containers()
			assert.are.equal(2, #all)
			assert.are.equal("myapp", all[1].project)
			assert.is_nil(all[2].project)

			local standalone = docker.list_standalone_containers()
			assert.are.equal(1, #standalone)
			assert.are.equal("standalone-box", standalone[1].name)
		end)
	end)

	describe("list_compose_networks / list_compose_volumes", function()
		it("filters by the com.docker.compose.project label", function()
			stub_system({
				["docker network ls --format json"] = {
					stdout = table.concat({
						'{"ID":"net1","Name":"myapp_default","Labels":"com.docker.compose.project=myapp,com.docker.compose.network=default"}',
						'{"ID":"net2","Name":"other_default","Labels":"com.docker.compose.project=other,com.docker.compose.network=default"}',
					}, "\n"),
				},
				["docker volume ls --format json"] = {
					stdout = '{"Name":"myapp_db-data","Labels":"com.docker.compose.project=myapp,com.docker.compose.volume=db-data"}',
				},
			})
			local networks = docker.list_compose_networks("myapp")
			assert.are.equal(1, #networks)
			assert.are.equal("myapp_default", networks[1].name)
			assert.are.equal("default", networks[1].compose_name)

			local volumes = docker.list_compose_volumes("myapp")
			assert.are.equal(1, #volumes)
			assert.are.equal("myapp_db-data", volumes[1].name)
		end)
	end)

	describe("_parse_compose_status", function()
		it("parses state and count", function()
			local state, count = docker._parse_compose_status("running(6)")
			assert.are.equal("running", state)
			assert.are.equal(6, count)
		end)

		it("returns the raw status and 0 when it doesn't match the pattern", function()
			local state, count = docker._parse_compose_status("unknown")
			assert.are.equal("unknown", state)
			assert.are.equal(0, count)
		end)
	end)

	describe("inspect_network / inspect_volume", function()
		it("returns the pretty-printed inspect output split into lines", function()
			stub_system({
				["docker network inspect myapp_default"] = {
					stdout = '[\n    {\n        "Name": "myapp_default"\n    }\n]',
				},
			})
			local lines = docker.inspect_network("myapp_default")
			assert.are.same({ "[", "    {", '        "Name": "myapp_default"', "    }", "]" }, lines)
		end)

		it("returns nil when the command fails", function()
			stub_system({
				["docker volume inspect missing"] = { code = 1, stderr = "no such volume" },
			})
			assert.is_nil(docker.inspect_volume("missing"))
		end)
	end)
end)
