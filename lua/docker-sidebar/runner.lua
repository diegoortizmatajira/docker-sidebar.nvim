local utils = require("docker-sidebar.utils")

--- The pluggable command-runner abstraction. Every sidebar action funnels through `M.run`,
--- which resolves `config.current.runner` to one of:
---   nil        -> built-in jobstart runner (background) / built-in terminal split (interactive)
---   "overseer" -> routes through overseer.nvim's terminal strategy
---   function   -> the user's own runner, called as-is
local M = {}

--- @param env table<string, string>|nil
--- @return table<string, string>|nil
local function non_empty_env(env)
	if env and next(env) then
		return env
	end
	return nil
end

--- Default background runner: shell-escapes the command and runs it via `vim.fn.jobstart`,
--- buffering stdout/stderr and scheduling `callback` with the result on exit.
--- @param spec DockerSidebar.CommandSpec
--- @param callback fun(result: DockerSidebar.RunnerResult)
function M.jobstart_runner(spec, callback)
	local command = utils.build_shell_command(spec.cmd, spec.args)
	local stdout_lines, stderr_lines = {}, {}
	vim.fn.jobstart(command, {
		cwd = spec.cwd,
		env = non_empty_env(spec.env),
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(stdout_lines, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr_lines, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				callback({
					ok = exit_code == 0,
					exit_code = exit_code,
					stdout = stdout_lines,
					stderr = stderr_lines,
				})
			end)
		end,
	})
end

--- Default interactive runner: mounts a bottom `nui.Split` terminal buffer and runs the
--- command in it via `vim.fn.termopen`. No callback is invoked -- interactive specs never
--- carry one, since there's no single "result" to report for a followed log stream or an
--- interactive shell. `q` closes the split.
--- @param spec DockerSidebar.CommandSpec
function M.terminal_runner(spec)
	local Split = require("nui.split")
	local split = Split({ relative = "editor", position = "bottom", size = "30%" })
	split:mount()
	vim.fn.termopen(utils.build_shell_command(spec.cmd, spec.args), {
		cwd = spec.cwd,
		env = non_empty_env(spec.env),
	})
	split:map("n", "q", function()
		split:hide()
	end)
	vim.cmd("startinsert")
end

--- Routes a spec through overseer.nvim (`strategy = "terminal"` + `open_output`, mirroring
--- db-cli-adapter.nvim's `_run_with_overseer`). For background specs, subscribes to the
--- task's `on_complete` event to synthesize a `RunnerResult` for `callback`.
--- @param spec DockerSidebar.CommandSpec
--- @param callback (fun(result: DockerSidebar.RunnerResult))|nil
function M.overseer_runner(spec, callback)
	local overseer = require("overseer")
	local task = overseer.new_task({
		cmd = spec.cmd,
		args = spec.args,
		cwd = spec.cwd,
		env = spec.env,
		name = spec.task_name,
		strategy = "terminal",
		components = {
			{ "open_output", direction = "dock", focus = false, on_complete = "always" },
			"default",
		},
	})
	if callback then
		local STATUS = require("overseer.constants").STATUS
		task:subscribe("on_complete", function(finished_task, status)
			callback({
				ok = status == STATUS.SUCCESS,
				exit_code = finished_task.exit_code or (status == STATUS.SUCCESS and 0 or 1),
				stdout = {},
				stderr = {},
			})
		end)
	end
	task:start()
end

--- @param spec DockerSidebar.CommandSpec
--- @param callback (fun(result: DockerSidebar.RunnerResult))|nil
local function default_run(spec, callback)
	if spec.mode == "interactive" then
		M.terminal_runner(spec)
	else
		M.jobstart_runner(spec, callback)
	end
end

--- Resolves `config.current.runner` and executes `spec` through it.
--- @param spec DockerSidebar.CommandSpec
--- @param callback (fun(result: DockerSidebar.RunnerResult))|nil
function M.run(spec, callback)
	local config = require("docker-sidebar.config")
	local runner = (config.current or config.default).runner

	if runner == nil then
		default_run(spec, callback)
		return
	end

	if runner == "overseer" then
		local ok = pcall(require, "overseer")
		if not ok then
			vim.notify(
				"DockerSidebar: overseer.nvim not installed, falling back to the default runner",
				vim.log.levels.WARN
			)
			default_run(spec, callback)
			return
		end
		M.overseer_runner(spec, callback)
		return
	end

	runner(spec, callback)
end

return M
