local compose_scanner = require("docker-sidebar.compose_scanner")
local docker = require("docker-sidebar.docker")

--- Merges `docker.lua`'s live Docker state with `compose_scanner.lua`'s workspace compose-file
--- scan into the sidebar's deployment model. Kept separate from both, since this merge logic
--- (live-vs-scanned precedence, synthesizing "down" deployments) is independently testable.
local M = {}

--- Aggregates a set of containers' individual states into one bucket. Exposed publicly since
--- `sidebar/nodes.lua` reuses it to compute a per-service icon for a scaled service's replicas.
--- @param containers DockerSidebar.ContainerInfo[]
--- @return "running"|"partial"|"stopped"
function M.aggregate_state(containers)
	if #containers == 0 then
		return "stopped"
	end
	local running = 0
	for _, container in ipairs(containers) do
		if container.state == "running" or container.state == "restarting" then
			running = running + 1
		end
	end
	if running == #containers then
		return "running"
	elseif running == 0 then
		return "stopped"
	end
	return "partial"
end

--- Builds synthesized "not yet created" containers for a deployment known only from a
--- scanned compose file (never started, so `docker compose ps` has nothing to report).
--- @param project string
--- @param services string[]
--- @return DockerSidebar.ContainerInfo[]
local function synthesize_containers(project, services)
	local containers = {}
	for _, service in ipairs(services) do
		table.insert(containers, {
			id = "",
			name = service,
			image = "",
			state = "stopped",
			status = "not created",
			project = project,
			service = service,
		})
	end
	return containers
end

--- @param live {Name:string, Status:string, ConfigFiles:string}
--- @param scan_info {config_file:string, cwd:string}|nil
--- @return DockerSidebar.DeploymentInfo
local function build_live_deployment(live, scan_info)
	local project = live.Name
	local containers = docker.list_compose_containers(project)
	local config_file = scan_info and scan_info.config_file
	if not config_file and live.ConfigFiles and live.ConfigFiles ~= "" then
		config_file = vim.split(live.ConfigFiles, ",")[1]
	end
	return {
		project = project,
		state = M.aggregate_state(containers),
		config_file = config_file,
		cwd = scan_info and scan_info.cwd or nil,
		containers = containers,
		networks = docker.list_compose_networks(project),
		volumes = docker.list_compose_volumes(project),
	}
end

--- @param scan_info {name:string, services:string[], config_file:string, cwd:string}
--- @return DockerSidebar.DeploymentInfo
local function build_down_deployment(scan_info)
	return {
		project = scan_info.name,
		state = "down",
		config_file = scan_info.config_file,
		cwd = scan_info.cwd,
		containers = synthesize_containers(scan_info.name, scan_info.services),
		networks = {},
		volumes = {},
	}
end

--- Merges live Docker state with the workspace compose-file scan. Live projects always take
--- precedence for state; scan-only projects (no matching entry in `docker compose ls -a`)
--- become `state = "down"` deployments with synthesized stopped services.
--- @return DockerSidebar.DeploymentInfo[]
function M.get_deployments()
	local live_projects = docker.list_compose_projects()
	local scanned = compose_scanner.scan()
	local deployments = {}
	local seen = {}

	for _, live in ipairs(live_projects) do
		seen[live.Name] = true
		table.insert(deployments, build_live_deployment(live, scanned[live.Name]))
	end

	for project, scan_info in pairs(scanned) do
		if not seen[project] then
			table.insert(deployments, build_down_deployment(scan_info))
		end
	end

	table.sort(deployments, function(a, b)
		return a.project < b.project
	end)
	return deployments
end

--- @return DockerSidebar.ContainerInfo[]
function M.get_standalone_containers()
	return docker.list_standalone_containers()
end

return M
