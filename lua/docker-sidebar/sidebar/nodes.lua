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
--- @field container_id? string The container id, present on service nodes once created and on container nodes
--- @field cwd? string The deployment's compose-file directory, present on deployment/service nodes
--- @field state? "running"|"stopped"|"paused"|"restarting"|"other" Container status, present on service/container nodes
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

--- @param deployment DockerSidebar.DeploymentInfo
--- @param container DockerSidebar.ContainerInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_service_node(deployment, container)
	-- A scaled service (`docker compose up --scale <service>=N`) reports one container per
	-- replica, all sharing `container.service` -- key by the (unique) container name instead,
	-- falling back to the service name for a synthesized (never-created) container.
	local unique_key = (container.name ~= "" and container.name) or container.service
	return M.new_node({
		id = "service_" .. deployment.project .. "_" .. unique_key,
		kind = "service",
		icon = status_icon(container.state),
		icon_hl = status_hl(container.state),
		text = container.service,
		description = container.status,
		project = deployment.project,
		service = container.service,
		container_id = (container.id ~= "" and container.id) or nil,
		cwd = deployment.cwd,
		state = container.state,
	})
end

--- @param deployment DockerSidebar.DeploymentInfo
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_services_group_node(deployment)
	local children = {}
	for _, container in ipairs(deployment.containers) do
		table.insert(children, M.new_service_node(deployment, container))
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
--- @return DockerSidebar.SidebarNodeData|NuiTree.Node
function M.new_container_node(container)
	return M.new_node({
		id = "container_" .. container.id,
		kind = "container",
		icon = status_icon(container.state),
		icon_hl = status_hl(container.state),
		text = container.name,
		description = container.status,
		container_id = container.id,
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
