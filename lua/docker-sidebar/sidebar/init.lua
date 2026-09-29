local config = require("docker-sidebar.config")
local docker = require("docker-sidebar.docker")
local nodes = require("docker-sidebar.sidebar.nodes")
local runner = require("docker-sidebar.runner")

local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local Popup = require("nui.popup")
local Split = require("nui.split")

local M = {
	split = nil,
	tree = nil,
	-- Window the sidebar was last opened/shown from, so the compose file for a deployment can
	-- be opened there instead of always splitting.
	previous_winid = nil,
}

local ACTIONS = { "start", "stop", "restart", "pause", "unpause", "remove", "logs", "exec", "up", "down" }

local NAV_KEYS = { "toggle_expand", "expand", "collapse", "refresh", "refresh_all", "help", "quit" }
local NAV_DESCRIPTIONS = {
	toggle_expand = "Toggle expand/collapse",
	expand = "Expand node",
	collapse = "Collapse node",
	refresh = "Refresh nearest ancestor",
	refresh_all = "Refresh the whole tree",
	help = "Show this help",
	quit = "Close sidebar",
}
local ACTION_DESCRIPTIONS = {
	start = "Start",
	stop = "Stop",
	restart = "Restart",
	pause = "Pause",
	unpause = "Unpause",
	remove = "Remove (confirms)",
	logs = "Logs (follow)",
	exec = "Exec shell",
	up = "Up (compose up -d)",
	down = "Down (confirms)",
}

--- Attempt to refresh the nearest ancestor node with a refresh function, walking up from
--- `node` (mirrors db-cli-adapter.nvim's sidebar `try_refresh`). Since group/deployment nodes
--- carry `refresh` but leaf action targets (service/container/network/volume) don't, this
--- naturally refreshes the smallest enclosing subtree that knows how to reload itself.
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node|nil
local function try_refresh(node)
	while node do
		if node.refresh then
			node:refresh(M.tree)
			return
		end
		node = M.tree:get_node(node:get_parent_id())
	end
end

--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node
--- @return boolean expanded True if the node was expanded
local function try_expand_node(node)
	if node and not node:is_expanded() and node:has_children() then
		node:expand()
		return true
	end
	return false
end

--- Destructive actions (deployment `down`, service/container `remove`) are gated behind a
--- `vim.fn.confirm` prompt when `sidebar.confirm_destructive` is enabled.
--- @param action string
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node
--- @return boolean proceed
local function confirm_if_destructive(action, node)
	if (action ~= "down" and action ~= "remove") or not config.current.sidebar.confirm_destructive then
		return true
	end
	local label = node.text
	if node.project and node.service then
		label = string.format("%s (%s)", node.service, node.project)
	end
	local choice = vim.fn.confirm(string.format("Really %s '%s'?", action, label), "&Yes\n&No", 2)
	return choice == 1
end

--- Dispatches `action` on the node under the cursor: builds a command spec, confirms
--- destructive actions, runs it through `runner.run`, and refreshes the nearest ancestor with
--- a `refresh` function once a background action completes.
--- @param action string
local function dispatch_action(action)
	local node = M.tree:get_node()
	if not node then
		return
	end
	local spec = nodes.build_command_spec(action, node)
	if not spec then
		return
	end
	if not confirm_if_destructive(action, node) then
		return
	end
	if spec.mode == "background" then
		runner.run(spec, function(result)
			vim.schedule(function()
				local level = result.ok and vim.log.levels.INFO or vim.log.levels.ERROR
				vim.notify(spec.task_name .. (result.ok and " completed" or " failed"), level)
				try_refresh(node)
			end)
		end)
	else
		runner.run(spec)
	end
end

--- Switches to the window the sidebar was opened/shown from, falling back to a new full-width
--- split if that window is gone (e.g. it was closed), so the compose file never ends up
--- squeezed into the narrow sidebar column.
local function switch_to_main_window()
	if M.previous_winid and vim.api.nvim_win_is_valid(M.previous_winid) then
		vim.api.nvim_set_current_win(M.previous_winid)
		return
	end
	vim.cmd("botright new")
end

--- Opens a deployment's compose file in the main editor window.
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node|nil
local function open_compose_file(node)
	if not node or node.kind ~= "deployment" then
		vim.notify("DockerSidebar: select a deployment node to open its compose file", vim.log.levels.WARN)
		return
	end
	if not node.config_file then
		vim.notify("DockerSidebar: no compose file known for this deployment", vim.log.levels.WARN)
		return
	end
	switch_to_main_window()
	vim.cmd.edit(vim.fn.fnameescape(node.config_file))
end

--- Opens `docker network/volume inspect` output for a network or volume node in a read-only
--- scratch buffer in the main window. Not a pluggable-runner action (start/stop/.../up/down)
--- -- this is a synchronous read, not a mutating command, so it always runs the same way
--- regardless of the configured `runner` (the JSON should land in a real buffer, not an
--- overseer terminal pane or wherever a custom runner happens to send it).
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node|nil
local function inspect_node(node)
	if not node or (node.kind ~= "network" and node.kind ~= "volume") then
		vim.notify("DockerSidebar: select a network or volume node to inspect", vim.log.levels.WARN)
		return
	end
	local lines = (node.kind == "network" and docker.inspect_network or docker.inspect_volume)(node.docker_name)
	if not lines then
		return -- docker.lua already notified on failure
	end
	switch_to_main_window()
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "json"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	pcall(vim.api.nvim_buf_set_name, bufnr, string.format("docker-inspect://%s/%s", node.kind, node.docker_name))
end

--- Builds the help window's contents: the always-available navigation keys, then the action
--- keys that apply to the node under the cursor. When no node is focused (or its kind isn't
--- recognized), every action is listed unfiltered.
--- @param node DockerSidebar.SidebarNodeData|NuiTree.Node|nil
--- @return string[] lines
local function build_help_lines(node)
	local kb = config.current.sidebar.keybindings
	local lines = { "Navigation", "" }
	for _, action in ipairs(NAV_KEYS) do
		table.insert(lines, string.format("  %-10s %s", table.concat(kb[action], "/"), NAV_DESCRIPTIONS[action]))
	end
	table.insert(lines, "")
	table.insert(lines, "Actions" .. (node and node.kind and (" (" .. node.kind .. ")") or ""))
	table.insert(lines, "")

	local supported = node and nodes.supported_actions(node.kind) or nil
	local shown_any = false
	for _, action in ipairs(ACTIONS) do
		if not supported or supported[action] then
			table.insert(lines, string.format("  %-10s %s", table.concat(kb[action], "/"), ACTION_DESCRIPTIONS[action]))
			shown_any = true
		end
	end
	-- Not runner actions (no CommandSpec), so they aren't tracked by nodes.supported_actions.
	if not node or node.kind == "deployment" then
		table.insert(lines, string.format("  %-10s %s", table.concat(kb.edit, "/"), "Open compose file"))
		shown_any = true
	end
	if not node or node.kind == "network" or node.kind == "volume" then
		table.insert(lines, string.format("  %-10s %s", table.concat(kb.inspect, "/"), "Inspect (view JSON)"))
		shown_any = true
	end
	if not shown_any then
		table.insert(lines, "  (no actions apply to this node)")
	end
	return lines
end

--- Opens a floating help window listing the sidebar's keybindings, filtered to the node
--- under the cursor. Closed with `q`/`<Esc>`.
local function show_help()
	local node = M.tree and M.tree:get_node()
	local lines = build_help_lines(node)

	local width = 30
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
	end
	local height = math.min(#lines, vim.o.lines - 6)

	local popup = Popup({
		relative = "editor",
		position = "50%",
		size = { width = width, height = height },
		border = {
			style = "rounded",
			text = { top = " DockerSidebar Help ", top_align = "center" },
		},
		buf_options = {
			filetype = "docker-sidebar-help",
		},
		enter = true,
	})
	popup:mount()
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
	vim.bo[popup.bufnr].modifiable = false
	vim.bo[popup.bufnr].readonly = true

	local function close()
		popup:unmount()
	end
	popup:map("n", "q", close, { noremap = true })
	popup:map("n", "<Esc>", close, { noremap = true })
end

function M.init()
	if not config.current then
		vim.notify("DockerSidebar: Configuration not found.", vim.log.levels.ERROR)
		return
	end
	M.previous_winid = vim.api.nvim_get_current_win()
	M.split = Split({ relative = "editor", position = "right", size = "40%" })
	M.split:mount()

	nodes.deployments_node = nodes.new_deployments_group_node()
	nodes.standalone_node = nodes.new_standalone_group_node()
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = { nodes.deployments_node, nodes.standalone_node },
		prepare_node = function(node)
			local line = NuiLine()
			line:append(string.rep("  ", node:get_depth() - 1))
			line:append(
				node:has_children()
						and (node:is_expanded() and config.current.icons.tree.chevron_open or config.current.icons.tree.chevron_closed)
					or (node.expandable and config.current.icons.tree.chevron_closed or "  "),
				config.current.highlight.tree.chevron
			)
			if node.icon and node.icon ~= "" then
				line:append(node.icon, node.icon_hl or config.current.highlight.tree.default_icon)
			end
			line:append(node.text)
			if node.count then
				line:append(" (" .. node.count .. ")", "@comment")
			end
			if node.description then
				line:append(" " .. node.description, "@comment")
			end
			return line
		end,
		buf_options = {
			buftype = "nofile",
			filetype = "docker-sidebar",
			swapfile = false,
			bufhidden = "hide",
		},
		win_options = {},
	})
	M.tree:render()

	local kb = config.current.sidebar.keybindings
	for _, key in ipairs(kb.toggle_expand) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node then
				if node:is_expanded() then
					node:collapse()
				else
					try_expand_node(node)
				end
				M.tree:render()
			end
		end)
	end
	for _, key in ipairs(kb.expand) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and try_expand_node(node) then
				M.tree:render()
			end
		end)
	end
	for _, key in ipairs(kb.collapse) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:collapse()
				M.tree:render()
			end
		end)
	end
	for _, key in ipairs(kb.refresh) do
		M.split:map("n", key, function()
			try_refresh(M.tree:get_node())
		end)
	end
	for _, key in ipairs(kb.refresh_all) do
		M.split:map("n", key, function()
			M.refresh()
		end)
	end
	for _, key in ipairs(kb.help) do
		M.split:map("n", key, show_help)
	end
	for _, key in ipairs(kb.edit) do
		M.split:map("n", key, function()
			open_compose_file(M.tree:get_node())
		end)
	end
	for _, key in ipairs(kb.inspect) do
		M.split:map("n", key, function()
			inspect_node(M.tree:get_node())
		end)
	end
	for _, action in ipairs(ACTIONS) do
		for _, key in ipairs(kb[action]) do
			M.split:map("n", key, function()
				dispatch_action(action)
			end)
		end
	end
	for _, key in ipairs(kb.quit) do
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end

	-- Hides gutter and number columns
	vim.opt_local.number = false
	vim.opt_local.relativenumber = false
	vim.opt_local.signcolumn = "no"
	vim.opt_local.foldcolumn = "0"

	M.refresh()
end

function M.refresh()
	if not M.tree then
		return
	end
	nodes.deployments_node:refresh(M.tree)
	nodes.standalone_node:refresh(M.tree)
	nodes.deployments_node:expand()
	nodes.standalone_node:expand()
	M.tree:render()
end

function M.toggle()
	if M.split then
		if M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
			M.split:hide()
		else
			M.previous_winid = vim.api.nvim_get_current_win()
			M.split:show()
		end
	else
		M.init()
	end
end

return M
