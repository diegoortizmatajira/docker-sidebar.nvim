local NuiTree = require("nui.tree")
local config = require("docker-sidebar.config")
local docker_core = require("docker-sidebar.docker_core")

local M = {
	--- @type DockerSidebar.SidebarNodeData|NuiTree.Node|nil
	deployments_node = nil,
	--- @type DockerSidebar.SidebarNodeData|NuiTree.Node|nil
	standalone_node = nil,
}

--- @class DockerSidebar.SidebarNodeData
--- @field id string The unique identifier for the node
--- @field kind "deployments_group"|"deployment"|"services_group"|"service"|"networks_group"|"network"|"volumes_group"|"volume"|"standalone_group"|"container"
--- @field icon? string The icon to display next to the node
--- @field icon_hl? string The highlight group for the icon
--- @field text string The display text for the node
--- @field description? string Additional description text for the node
--- @field count? number The number of child nodes (e.g. number of services in a deployment)
--- @field expandable? boolean Whether the node can be expanded to show children
--- @field project? string Compose project name, present on deployment/service/network/volume nodes
--- @field service? string Compose service name, present on service nodes
--- @field container_id? string The container id, present on container nodes once created
--- @field cwd? string The deployment's compose-file directory, present on deployment/service nodes
--- @field config_file? string The deployment's compose file path, present on deployment nodes when known
--- @field docker_name? string The real Docker object name for `docker network/volume inspect`, present on network/volume nodes
--- @field state? "running"|"stopped"|"paused"|"restarting"|"other" Container status, present on container nodes
--- @field refresh? fun(self: DockerSidebar.SidebarNodeData|NuiTree.Node, tree: NuiTree): nil A function to refresh the node's contents

--- @param state string|nil
--- @return string
local function status_icon(state)
	local icons = config.current.icons.status
	return icons[state] or icons.other
end

--- @param state string|nil
--- @return string
local function status_hl(state)
	local hl = config.current.highlight.status
	return hl[state] or hl.other
end

--- Create a new SidebarNode
--- @param o DockerSidebar.SidebarNodeData The properties of the node
--- @param children? table A list of child nodes
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.new_node(o, children)
	--- @type DockerSidebar.SidebarNodeData
	local default = {
		id = "",
		icon = "",
		icon_hl = "",
		text = "",
		description = nil,
		refresh = nil,
	}
	o = vim.tbl_extend("force", default, o or {})
	o._id = o.id -- NuiTree expects _id field for unique identification
	return NuiTree.Node(o, children)
end

--- A compose service, expandable to show the container(s) actually running it -- a scaled
--- service (`docker compose up --scale <service>=N`) has more than one. Actions on this node
--- (start/stop/restart/.../exec) target the whole service via `docker compose ... <service>`;
--- act on one specific replica instead by expanding it and acting on its container child.
--- @param deployment DockerSidebar.DeploymentInfo
--- @param service_name string
--- @param containers DockerSidebar.ContainerInfo[] This service's replica container(s), at least one
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_service_node(deployment, service_name, containers)
	local children = {}
	for _, container in ipairs(containers) do
		table.insert(children, M.new_container_node(container, deployment.project .. "_"))
	end

	local state = docker_core.aggregate_state(containers)
	local description
	if #containers > 1 then
		if state == "partial" then
			local running = 0
			for _, container in ipairs(containers) do
				if container.state == "running" then
					running = running + 1
				end
			end
			description = string.format("(%d/%d running)", running, #containers)
		else
			description = string.format("(%d replicas)", #containers)
		end
	end

	return M.new_node({
		id = "service_" .. deployment.project .. "_" .. service_name,
		kind = "service",
		icon = status_icon(state),
		icon_hl = status_hl(state),
		text = service_name,
		description = description,
		project = deployment.project,
		service = service_name,
		cwd = deployment.cwd,
		expandable = true,
	}, children)
end

--- Groups a deployment's containers by `service` (a scaled service reports one container per
--- replica, all sharing the same service name) so each service shows up once, expandable to
--- reveal its replica(s).
--- @param deployment DockerSidebar.DeploymentInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_services_group_node(deployment)
	local containers_by_service = {}
	local service_names = {}
	for _, container in ipairs(deployment.containers) do
		if not containers_by_service[container.service] then
			containers_by_service[container.service] = {}
			table.insert(service_names, container.service)
		end
		table.insert(containers_by_service[container.service], container)
	end
	table.sort(service_names)

	local children = {}
	for _, service_name in ipairs(service_names) do
		table.insert(children, M.new_service_node(deployment, service_name, containers_by_service[service_name]))
	end
	return M.new_node({
		id = "services_" .. deployment.project,
		kind = "services_group",
		icon = config.current.icons.tree.services_group,
		icon_hl = config.current.highlight.tree.folder,
		text = "Services",
		count = #children,
		expandable = true,
	}, children)
end

--- @param network DockerSidebar.NetworkInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_network_node(network)
	return M.new_node({
		id = "network_" .. (network.id or network.name),
		kind = "network",
		icon = config.current.icons.tree.network,
		icon_hl = config.current.highlight.tree.network,
		text = network.compose_name or network.name,
		description = network.name,
		project = network.project,
		docker_name = network.name,
	})
end

--- @param deployment DockerSidebar.DeploymentInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_networks_group_node(deployment)
	local children = {}
	for _, network in ipairs(deployment.networks) do
		table.insert(children, M.new_network_node(network))
	end
	return M.new_node({
		id = "networks_" .. deployment.project,
		kind = "networks_group",
		icon = config.current.icons.tree.networks_group,
		icon_hl = config.current.highlight.tree.folder,
		text = "Networks",
		count = #children,
		expandable = true,
	}, children)
end

--- @param volume DockerSidebar.VolumeInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_volume_node(volume)
	return M.new_node({
		id = "volume_" .. volume.name,
		kind = "volume",
		icon = config.current.icons.tree.volume,
		icon_hl = config.current.highlight.tree.volume,
		text = volume.compose_name or volume.name,
		description = volume.name,
		project = volume.project,
		docker_name = volume.name,
	})
end

--- @param deployment DockerSidebar.DeploymentInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_volumes_group_node(deployment)
	local children = {}
	for _, volume in ipairs(deployment.volumes) do
		table.insert(children, M.new_volume_node(volume))
	end
	return M.new_node({
		id = "volumes_" .. deployment.project,
		kind = "volumes_group",
		icon = config.current.icons.tree.volumes_group,
		icon_hl = config.current.highlight.tree.folder,
		text = "Volumes",
		count = #children,
		expandable = true,
	}, children)
end

--- Finds the current state of `project` by re-running the full deployment merge. Simpler and
--- more consistent than a narrower single-project query, at the cost of re-querying every
--- deployment on a single deployment's refresh -- an acceptable v1 trade-off given the
--- underlying Docker CLI calls are fast.
--- @param project string
--- @return DockerSidebar.DeploymentInfo|nil
local function find_deployment(project)
	for _, deployment in ipairs(docker_core.get_deployments()) do
		if deployment.project == project then
			return deployment
		end
	end
	return nil
end

--- @param deployment DockerSidebar.DeploymentInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_deployment_node(deployment)
	local services_node = M.new_services_group_node(deployment)
	local networks_node = M.new_networks_group_node(deployment)
	local volumes_node = M.new_volumes_group_node(deployment)
	return M.new_node({
		id = "deployment_" .. deployment.project,
		kind = "deployment",
		icon = config.current.icons.tree.deployment,
		icon_hl = config.current.highlight.tree.deployment,
		text = deployment.project,
		description = string.format("(%s)", deployment.state),
		project = deployment.project,
		cwd = deployment.cwd,
		config_file = deployment.config_file,
		expandable = true,
		refresh = function(self, tree)
			local updated = find_deployment(deployment.project)
			if not updated then
				vim.notify("DockerSidebar: deployment no longer exists: " .. deployment.project, vim.log.levels.WARN)
				return
			end
			tree:set_nodes({
				M.new_services_group_node(updated),
				M.new_networks_group_node(updated),
				M.new_volumes_group_node(updated),
			}, self:get_id())
			self.description = string.format("(%s)", updated.state)
			self.config_file = updated.config_file
			self.cwd = updated.cwd
			self:expand()
			tree:render()
			vim.notify(string.format("'%s' refreshed successfully", deployment.project), vim.log.levels.INFO)
		end,
	}, { services_node, networks_node, volumes_node })
end

--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_deployments_group_node()
	return M.new_node({
		id = "deployments_group",
		kind = "deployments_group",
		icon = config.current.icons.tree.deployments_group,
		icon_hl = config.current.highlight.tree.folder,
		text = "Deployments",
		expandable = true,
		refresh = function(self, tree)
			local children = {}
			for _, deployment in ipairs(docker_core.get_deployments()) do
				table.insert(children, M.new_deployment_node(deployment))
			end
			tree:set_nodes(children, self:get_id())
			self.count = #children
			self:expand()
			tree:render()
		end,
	})
end

--- @param container DockerSidebar.ContainerInfo
--- @param id_prefix? string Extra uniqueness prefix for a synthesized (never-created) container
---   -- its `id` is empty and its `name` (the service name) could otherwise collide with a
---   same-named service in a different "down" deployment
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_container_node(container, id_prefix)
	local container_id = (container.id ~= "" and container.id) or nil
	return M.new_node({
		id = "container_" .. (container_id or ((id_prefix or "") .. container.name)),
		kind = "container",
		icon = status_icon(container.state),
		icon_hl = status_hl(container.state),
		text = container.name,
		description = container.status,
		container_id = container_id,
		state = container.state,
	})
end

--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_standalone_group_node()
	return M.new_node({
		id = "standalone_group",
		kind = "standalone_group",
		icon = config.current.icons.tree.standalone_group,
		icon_hl = config.current.highlight.tree.folder,
		text = "Standalone Containers",
		expandable = true,
		refresh = function(self, tree)
			local children = {}
			for _, container in ipairs(docker_core.get_standalone_containers()) do
				table.insert(children, M.new_container_node(container))
			end
			tree:set_nodes(children, self:get_id())
			self.count = #children
			self:expand()
			tree:render()
		end,
	})
end

--- Builds the shell-exec spec shared by service and standalone container `exec` actions:
--- tries `sh` first, falling back to `bash` when `sh` isn't on the container's PATH.
--- @param cmd string[] The exec invocation up to (not including) the shell command itself
--- @return string[]
local function with_shell_fallback(cmd)
	local args = vim.list_extend({}, cmd)
	vim.list_extend(args, { "sh", "-c", "exec sh || exec bash" })
	return args
end

--- @type table<string, table<string, fun(node: DockerSidebar.SidebarNodeData): DockerSidebar.CommandSpec>>
local builders = {
	deployment = {
		up = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "up", "-d" },
				cwd = n.cwd,
				task_name = ("Up %s"):format(n.project),
				mode = "background",
			}
		end,
		down = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "down" },
				cwd = n.cwd,
				task_name = ("Down %s"):format(n.project),
				mode = "background",
			}
		end,
		start = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "start" },
				cwd = n.cwd,
				task_name = ("Start %s"):format(n.project),
				mode = "background",
			}
		end,
		stop = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "stop" },
				cwd = n.cwd,
				task_name = ("Stop %s"):format(n.project),
				mode = "background",
			}
		end,
		restart = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "restart" },
				cwd = n.cwd,
				task_name = ("Restart %s"):format(n.project),
				mode = "background",
			}
		end,
		pause = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "pause" },
				cwd = n.cwd,
				task_name = ("Pause %s"):format(n.project),
				mode = "background",
			}
		end,
		unpause = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "unpause" },
				cwd = n.cwd,
				task_name = ("Unpause %s"):format(n.project),
				mode = "background",
			}
		end,
		logs = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "logs", "-f" },
				cwd = n.cwd,
				task_name = ("Logs: %s"):format(n.project),
				mode = "interactive",
			}
		end,
	},
	service = {
		start = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "start", n.service },
				cwd = n.cwd,
				task_name = ("Start %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		stop = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "stop", n.service },
				cwd = n.cwd,
				task_name = ("Stop %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		restart = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "restart", n.service },
				cwd = n.cwd,
				task_name = ("Restart %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		pause = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "pause", n.service },
				cwd = n.cwd,
				task_name = ("Pause %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		unpause = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "unpause", n.service },
				cwd = n.cwd,
				task_name = ("Unpause %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		remove = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "rm", "-f", n.service },
				cwd = n.cwd,
				task_name = ("Remove %s (%s)"):format(n.service, n.project),
				mode = "background",
			}
		end,
		logs = function(n)
			return {
				cmd = "docker",
				args = { "compose", "-p", n.project, "logs", "-f", n.service },
				cwd = n.cwd,
				task_name = ("Logs: %s (%s)"):format(n.service, n.project),
				mode = "interactive",
			}
		end,
		exec = function(n)
			return {
				cmd = "docker",
				args = with_shell_fallback({ "compose", "-p", n.project, "exec", n.service }),
				cwd = n.cwd,
				task_name = ("Exec: %s (%s)"):format(n.service, n.project),
				mode = "interactive",
			}
		end,
	},
	container = {
		start = function(n)
			return {
				cmd = "docker",
				args = { "start", n.container_id },
				task_name = ("Start %s"):format(n.text),
				mode = "background",
			}
		end,
		stop = function(n)
			return {
				cmd = "docker",
				args = { "stop", n.container_id },
				task_name = ("Stop %s"):format(n.text),
				mode = "background",
			}
		end,
		restart = function(n)
			return {
				cmd = "docker",
				args = { "restart", n.container_id },
				task_name = ("Restart %s"):format(n.text),
				mode = "background",
			}
		end,
		pause = function(n)
			return {
				cmd = "docker",
				args = { "pause", n.container_id },
				task_name = ("Pause %s"):format(n.text),
				mode = "background",
			}
		end,
		unpause = function(n)
			return {
				cmd = "docker",
				args = { "unpause", n.container_id },
				task_name = ("Unpause %s"):format(n.text),
				mode = "background",
			}
		end,
		remove = function(n)
			return {
				cmd = "docker",
				args = { "rm", "-f", n.container_id },
				task_name = ("Remove %s"):format(n.text),
				mode = "background",
			}
		end,
		logs = function(n)
			return {
				cmd = "docker",
				args = { "logs", "-f", n.container_id },
				task_name = ("Logs: %s"):format(n.text),
				mode = "interactive",
			}
		end,
		exec = function(n)
			return {
				cmd = "docker",
				args = with_shell_fallback({ "exec", "-it", n.container_id }),
				task_name = ("Exec: %s"):format(n.text),
				mode = "interactive",
			}
		end,
	},
}

--- Builds the `DockerSidebar.CommandSpec` for `action` on `node`, per node kind. Returns nil
--- (with a WARN notify) for unsupported (action, node.kind) combinations -- e.g. `up`/`down` on
--- a service node, or any action on a network/volume node -- so callers can dispatch uniformly.
--- @param action "start"|"stop"|"restart"|"pause"|"unpause"|"remove"|"logs"|"exec"|"up"|"down"
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node
--- @return DockerSidebar.CommandSpec|nil
function M.build_command_spec(action, node)
	if node.kind == "container" and not node.container_id then
		vim.notify("DockerSidebar: this container hasn't been created yet", vim.log.levels.WARN)
		return nil
	end
	local kind_builders = node.kind and builders[node.kind]
	local builder = kind_builders and kind_builders[action]
	if not builder then
		vim.notify(string.format("DockerSidebar: '%s' is not supported on this node", action), vim.log.levels.WARN)
		return nil
	end
	return builder(node)
end

--- Returns the set of actions supported for a given node kind, without needing a real node
--- (unlike `build_command_spec`, which needs populated fields like `project`/`service` to
--- build a working spec). Used by the sidebar's `?` help window to show only the actions
--- that apply to the node under the cursor.
--- @param kind string|nil
--- @return table<string, boolean> actions Set of supported action names (action -> true)
function M.supported_actions(kind)
	local kind_builders = kind and builders[kind]
	if not kind_builders then
		return {}
	end
	local actions = {}
	for action in pairs(kind_builders) do
		actions[action] = true
	end
	return actions
end

return M
