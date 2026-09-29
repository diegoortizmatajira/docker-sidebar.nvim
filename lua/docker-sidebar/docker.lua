local utils = require("docker-sidebar.utils")

--- Thin wrappers around the `docker`/`docker compose` CLI for live-state queries. These are
--- fast, read-only metadata reads (not long-running actions), so unlike `runner.lua` there is
--- no pluggable-runner concern here -- always executed synchronously via `vim.system`.
local M = {}

--- Runs a docker CLI command synchronously.
--- @param args string[]
--- @param cwd? string
--- @return string[] lines, boolean ok
local function run(args, cwd)
	local ok, result = pcall(function()
		return vim.system(vim.list_extend({ "docker" }, args), { text = true, cwd = cwd }):wait()
	end)
	if not ok or result.code ~= 0 then
		local stderr = ok and result.stderr or tostring(result)
		if stderr and vim.trim(stderr) ~= "" then
			vim.notify("DockerSidebar: " .. vim.trim(stderr), vim.log.levels.WARN)
		end
		return {}, false
	end
	return vim.split(result.stdout or "", "\n", { trimempty = true }), true
end

--- @param labels string|nil
--- @return string|nil
local function project_label(labels)
	return utils.parse_labels(labels)["com.docker.compose.project"]
end

--- Lists Compose deployments known to the Docker daemon (running or stopped).
--- @return {Name:string, Status:string, ConfigFiles:string}[]
function M.list_compose_projects()
	local lines = run({ "compose", "ls", "-a", "--format", "json" })
	if #lines == 0 then
		return {}
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok or type(decoded) ~= "table" then
		vim.notify("DockerSidebar: could not parse `docker compose ls` output", vim.log.levels.WARN)
		return {}
	end
	return decoded
end

--- @param project string
--- @return DockerSidebar.ContainerInfo[]
function M.list_compose_containers(project)
	local items = utils.decode_ndjson(run({ "compose", "-p", project, "ps", "-a", "--format", "json" }))
	local containers = {}
	for _, item in ipairs(items) do
		table.insert(containers, {
			id = item.ID,
			name = item.Name,
			image = item.Image,
			state = utils.normalize_state(item.State),
			status = item.Status,
			project = item.Project,
			service = item.Service,
		})
	end
	return containers
end

--- Lists ALL containers (Compose-managed and standalone). `project`/`service` are populated
--- from the `com.docker.compose.*` labels, nil for standalone containers.
--- @return DockerSidebar.ContainerInfo[]
function M.list_all_containers()
	local items = utils.decode_ndjson(run({ "ps", "-a", "--format", "json" }))
	local containers = {}
	for _, item in ipairs(items) do
		local labels = utils.parse_labels(item.Labels)
		table.insert(containers, {
			id = item.ID,
			name = item.Names,
			image = item.Image,
			state = utils.normalize_state(item.State),
			status = item.Status,
			project = labels["com.docker.compose.project"],
			service = labels["com.docker.compose.service"],
		})
	end
	return containers
end

--- @return DockerSidebar.ContainerInfo[]
function M.list_standalone_containers()
	local standalone = {}
	for _, container in ipairs(M.list_all_containers()) do
		if not container.project then
			table.insert(standalone, container)
		end
	end
	return standalone
end

--- @param project string
--- @return DockerSidebar.NetworkInfo[]
function M.list_compose_networks(project)
	local items = utils.decode_ndjson(run({ "network", "ls", "--format", "json" }))
	local networks = {}
	for _, item in ipairs(items) do
		if project_label(item.Labels) == project then
			table.insert(networks, {
				id = item.ID,
				name = item.Name,
				project = project,
				compose_name = utils.parse_labels(item.Labels)["com.docker.compose.network"],
			})
		end
	end
	return networks
end

--- @param project string
--- @return DockerSidebar.VolumeInfo[]
function M.list_compose_volumes(project)
	local items = utils.decode_ndjson(run({ "volume", "ls", "--format", "json" }))
	local volumes = {}
	for _, item in ipairs(items) do
		if project_label(item.Labels) == project then
			table.insert(volumes, {
				name = item.Name,
				project = project,
				compose_name = utils.parse_labels(item.Labels)["com.docker.compose.volume"],
			})
		end
	end
	return volumes
end

--- Parses a `docker compose ls` `Status` field like `"running(6)"`/`"exited(3)"`.
--- @param status string|nil
--- @return string state, integer count
function M._parse_compose_status(status)
	if not status then
		return "other", 0
	end
	local state, count = status:match("^(%a+)%((%d+)%)$")
	if not state then
		return status, 0
	end
	return state, tonumber(count) or 0
end

return M
