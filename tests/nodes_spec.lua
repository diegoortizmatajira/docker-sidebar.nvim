local NuiTree = require("nui.tree")
local config = require("docker-sidebar.config")
local nodes = require("docker-sidebar.sidebar.nodes")

--- Builds a real NuiTree (nui.nvim only tracks parent/child ids once a node is attached to
--- one -- see nui/tree/init.lua's TreeNode:get_child_ids()) around `top_node` in a scratch
--- buffer, so child structure can be inspected via `tree:get_node(id)`.
--- @param top_node NuiTree.Node
--- @return NuiTree tree, integer bufnr
local function build_tree(top_node)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local tree = NuiTree({ bufnr = bufnr, nodes = { top_node } })
	return tree, bufnr
end

--- Finds a direct child of `node` whose `kind`/`id` field matches `predicate`. Note the tree's
--- internal node id (`node:get_id()`) is NOT the raw `id` passed to `new_node` -- nui.nvim's
--- default `get_node_id` derives its own key from it -- so children must be looked up this way
--- rather than by guessing the internal id string.
--- @param tree NuiTree
--- @param node NuiTree.Node
--- @param predicate fun(child: NuiTree.Node): boolean
--- @return NuiTree.Node|nil
local function find_child(tree, node, predicate)
	for _, child_id in ipairs(node:get_child_ids()) do
		local child = tree:get_node(child_id)
		if child and predicate(child) then
			return child
		end
	end
	return nil
end

describe("node construction", function()
	local bufnrs = {}

	before_each(function()
		config.current = vim.tbl_deep_extend("force", {}, config.default)
	end)

	after_each(function()
		config.current = nil
		for _, bufnr in ipairs(bufnrs) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		bufnrs = {}
	end)

	--- @type DockerSidebar.DeploymentInfo
	local deployment = {
		project = "myapp",
		state = "running",
		config_file = "/project/docker-compose.yml",
		cwd = "/project",
		containers = {
			{ id = "abc", name = "myapp-web-1", image = "nginx", state = "running", status = "Up", service = "web" },
			{
				id = "abd",
				name = "myapp-web-2",
				image = "nginx",
				state = "running",
				status = "Up",
				service = "web",
			},
			{
				id = "def",
				name = "myapp-db-1",
				image = "postgres",
				state = "stopped",
				status = "Exited",
				service = "db",
			},
		},
		networks = { { id = "net1", name = "myapp_default", project = "myapp", compose_name = "default" } },
		volumes = { { name = "myapp_db-data", project = "myapp", compose_name = "db-data" } },
	}

	it("builds a deployment node with services/networks/volumes sub-groups", function()
		local node = nodes.new_deployment_node(deployment)
		local tree, bufnr = build_tree(node)
		table.insert(bufnrs, bufnr)

		assert.are.equal("deployment", node.kind)
		assert.are.equal("myapp", node.project)
		assert.are.equal("/project", node.cwd)
		assert.are.equal("(running)", node.description)
		assert.is_true(node:has_children())
		assert.are.equal(3, #node:get_child_ids())

		local services_node = find_child(tree, node, function(child)
			return child.kind == "services_group"
		end)
		-- 2 distinct services (web, db), even though "web" has 2 replica containers
		assert.are.equal(2, services_node.count)
		local networks_node = find_child(tree, node, function(child)
			return child.kind == "networks_group"
		end)
		assert.are.equal(1, networks_node.count)
		local volumes_node = find_child(tree, node, function(child)
			return child.kind == "volumes_group"
		end)
		assert.are.equal(1, volumes_node.count)
	end)

	it("collapses a scaled service's replicas into one expandable service node", function()
		local services_node = nodes.new_services_group_node(deployment)
		local tree, bufnr = build_tree(services_node)
		table.insert(bufnrs, bufnr)

		-- one node per distinct service, not one per container
		assert.are.equal(2, #services_node:get_child_ids())

		local web_node = find_child(tree, services_node, function(child)
			return child.service == "web"
		end)
		assert.are.equal("service", web_node.kind)
		assert.is_true(web_node:has_children())
		assert.are.equal(2, #web_node:get_child_ids())
		assert.are.equal("(2 replicas)", web_node.description)
		assert.are.equal(config.current.icons.status.running, web_node.icon)

		local web_containers = web_node:get_child_ids()
		local first_replica = tree:get_node(web_containers[1])
		assert.are.equal("container", first_replica.kind)
		assert.is_not_nil(first_replica.container_id)

		local db_node = find_child(tree, services_node, function(child)
			return child.service == "db"
		end)
		assert.are.equal(1, #db_node:get_child_ids())
		assert.is_nil(db_node.description) -- no "(N replicas)" note for a single-instance service
		assert.are.equal(config.current.icons.status.stopped, db_node.icon)
	end)

	it("shows a partial icon note when a scaled service's replicas disagree", function()
		local mixed_deployment = {
			project = "myapp",
			cwd = "/project",
			containers = {
				{ id = "a", name = "myapp-web-1", image = "nginx", state = "running", status = "Up", service = "web" },
				{
					id = "b",
					name = "myapp-web-2",
					image = "nginx",
					state = "stopped",
					status = "Exited",
					service = "web",
				},
			},
			networks = {},
			volumes = {},
		}
		local services_node = nodes.new_services_group_node(mixed_deployment)
		local tree, bufnr = build_tree(services_node)
		table.insert(bufnrs, bufnr)

		local web_node = find_child(tree, services_node, function(child)
			return child.service == "web"
		end)
		assert.are.equal("(1/2 running)", web_node.description)
	end)

	it("leaves container_id nil for a synthesized (never-created) service", function()
		local synthesized_deployment = {
			project = "neverstarted",
			cwd = "/scanned",
			containers = {
				{ id = "", name = "web", image = "", state = "stopped", status = "not created", service = "web" },
			},
			networks = {},
			volumes = {},
		}
		local service_node = nodes.new_service_node(synthesized_deployment, "web", synthesized_deployment.containers)
		local container_child = service_node.__children[1]
		assert.is_nil(container_child.container_id)
	end)

	it("attaches Deployments and Standalone Containers directly as tree roots (no wrapping node)", function()
		local deployments_node = nodes.new_deployments_group_node()
		local standalone_node = nodes.new_standalone_group_node()
		local bufnr = vim.api.nvim_create_buf(false, true)
		local tree = NuiTree({ bufnr = bufnr, nodes = { deployments_node, standalone_node } })
		table.insert(bufnrs, bufnr)

		assert.are.equal(2, #tree.nodes.root_ids)
		assert.are.equal("deployments_group", deployments_node.kind)
		assert.are.equal("standalone_group", standalone_node.kind)
		assert.are.equal(1, deployments_node:get_depth())
		assert.are.equal(1, standalone_node:get_depth())
	end)
end)

describe("nodes.build_command_spec", function()
	local previous_notify

	before_each(function()
		previous_notify = vim.notify
		vim.notify = function() end
	end)

	after_each(function()
		vim.notify = previous_notify
	end)

	describe("deployment nodes", function()
		local node = { kind = "deployment", project = "myapp", cwd = "/project", text = "myapp" }

		it("up", function()
			assert.are.same({
				cmd = "docker",
				args = { "compose", "-p", "myapp", "up", "-d" },
				cwd = "/project",
				task_name = "Up myapp",
				mode = "background",
			}, nodes.build_command_spec("up", node))
		end)

		it("down", function()
			assert.are.same({
				cmd = "docker",
				args = { "compose", "-p", "myapp", "down" },
				cwd = "/project",
				task_name = "Down myapp",
				mode = "background",
			}, nodes.build_command_spec("down", node))
		end)

		for _, action in ipairs({ "start", "stop", "restart", "pause", "unpause" }) do
			it(action, function()
				local spec = nodes.build_command_spec(action, node)
				assert.are.equal("docker", spec.cmd)
				assert.are.same({ "compose", "-p", "myapp", action }, spec.args)
				assert.are.equal("/project", spec.cwd)
				assert.are.equal("background", spec.mode)
			end)
		end

		for _, action in ipairs({ "remove", "logs", "exec" }) do
			it(action .. " is unsupported on a deployment node", function()
				assert.is_nil(nodes.build_command_spec(action, node))
			end)
		end
	end)

	describe("service nodes", function()
		local node = { kind = "service", project = "myapp", service = "web", cwd = "/project", text = "web" }

		for _, action in ipairs({ "start", "stop", "restart", "pause", "unpause" }) do
			it(action, function()
				local spec = nodes.build_command_spec(action, node)
				assert.are.same({ "compose", "-p", "myapp", action, "web" }, spec.args)
				assert.are.equal("/project", spec.cwd)
				assert.are.equal("background", spec.mode)
			end)
		end

		it("remove", function()
			local spec = nodes.build_command_spec("remove", node)
			assert.are.same({ "compose", "-p", "myapp", "rm", "-f", "web" }, spec.args)
			assert.are.equal("background", spec.mode)
		end)

		it("logs", function()
			local spec = nodes.build_command_spec("logs", node)
			assert.are.same({ "compose", "-p", "myapp", "logs", "-f", "web" }, spec.args)
			assert.are.equal("interactive", spec.mode)
		end)

		it("exec falls back to bash when sh is unavailable", function()
			local spec = nodes.build_command_spec("exec", node)
			assert.are.same({ "compose", "-p", "myapp", "exec", "web", "sh", "-c", "exec sh || exec bash" }, spec.args)
			assert.are.equal("interactive", spec.mode)
		end)

		for _, action in ipairs({ "up", "down" }) do
			it(action .. " is unsupported on a service node", function()
				assert.is_nil(nodes.build_command_spec(action, node))
			end)
		end
	end)

	describe("container nodes (standalone)", function()
		local node = { kind = "container", container_id = "abc123", text = "standalone-box" }

		for _, action in ipairs({ "start", "stop", "restart", "pause", "unpause" }) do
			it(action, function()
				local spec = nodes.build_command_spec(action, node)
				assert.are.same({ action, "abc123" }, spec.args)
				assert.is_nil(spec.cwd)
				assert.are.equal("background", spec.mode)
			end)
		end

		it("remove", function()
			local spec = nodes.build_command_spec("remove", node)
			assert.are.same({ "rm", "-f", "abc123" }, spec.args)
		end)

		it("logs", function()
			local spec = nodes.build_command_spec("logs", node)
			assert.are.same({ "logs", "-f", "abc123" }, spec.args)
			assert.are.equal("interactive", spec.mode)
		end)

		it("exec falls back to bash when sh is unavailable", function()
			local spec = nodes.build_command_spec("exec", node)
			assert.are.same({ "exec", "-it", "abc123", "sh", "-c", "exec sh || exec bash" }, spec.args)
			assert.are.equal("interactive", spec.mode)
		end)

		for _, action in ipairs({ "up", "down" }) do
			it(action .. " is unsupported on a container node", function()
				assert.is_nil(nodes.build_command_spec(action, node))
			end)
		end
	end)

	describe("network and volume nodes", function()
		local network_node = { kind = "network", text = "myapp_default" }
		local volume_node = { kind = "volume", text = "myapp_db-data" }
		local all_actions = { "start", "stop", "restart", "pause", "unpause", "remove", "logs", "exec", "up", "down" }

		for _, action in ipairs(all_actions) do
			it("no actions are supported on a network node (" .. action .. ")", function()
				assert.is_nil(nodes.build_command_spec(action, network_node))
			end)

			it("no actions are supported on a volume node (" .. action .. ")", function()
				assert.is_nil(nodes.build_command_spec(action, volume_node))
			end)
		end
	end)

	describe("group nodes", function()
		local kinds = { "deployments_group", "services_group", "networks_group", "volumes_group", "standalone_group" }

		it("no actions are supported on group nodes", function()
			for _, kind in ipairs(kinds) do
				assert.is_nil(nodes.build_command_spec("start", { kind = kind, text = kind }))
			end
		end)
	end)
end)

describe("nodes.supported_actions", function()
	it("returns the exact action set for a deployment node", function()
		assert.are.same({
			up = true,
			down = true,
			start = true,
			stop = true,
			restart = true,
			pause = true,
			unpause = true,
		}, nodes.supported_actions("deployment"))
	end)

	it("returns the exact action set for a service node", function()
		assert.are.same({
			start = true,
			stop = true,
			restart = true,
			pause = true,
			unpause = true,
			remove = true,
			logs = true,
			exec = true,
		}, nodes.supported_actions("service"))
	end)

	it("returns the exact action set for a container node", function()
		assert.are.same({
			start = true,
			stop = true,
			restart = true,
			pause = true,
			unpause = true,
			remove = true,
			logs = true,
			exec = true,
		}, nodes.supported_actions("container"))
	end)

	it("returns an empty set for network/volume/group kinds and nil", function()
		for _, kind in ipairs({ "network", "volume", "deployments_group", "standalone_group", nil }) do
			assert.are.same({}, nodes.supported_actions(kind))
		end
	end)
end)
