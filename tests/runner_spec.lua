local config = require("docker-sidebar.config")
local runner = require("docker-sidebar.runner")

--- Simulates `name` being absent from the runtime path for the duration of `fn`, even though
--- it's actually installed in this dev/test environment (see health_spec.lua for the same
--- pattern).
--- @param name string
--- @param fn fun()
local function without_module(name, fn)
	local previous_loaded = package.loaded[name]
	local previous_preload = package.preload[name]
	package.loaded[name] = nil
	package.preload[name] = function()
		error(name .. " not found", 0)
	end
	local ok, err = pcall(fn)
	package.loaded[name] = previous_loaded
	package.preload[name] = previous_preload
	if not ok then
		error(err, 0)
	end
end

describe("runner", function()
	after_each(function()
		config.current = nil
	end)

	describe("jobstart_runner", function()
		local previous_jobstart

		before_each(function()
			previous_jobstart = vim.fn.jobstart
		end)

		after_each(function()
			vim.fn.jobstart = previous_jobstart
		end)

		it("shell-escapes the command and reports the result on exit", function()
			local captured_cmd, captured_opts
			vim.fn.jobstart = function(cmd, opts)
				captured_cmd, captured_opts = cmd, opts
				return 1
			end

			local result
			runner.jobstart_runner({
				cmd = "docker",
				args = { "compose", "-p", "myapp", "restart", "web" },
				cwd = "/project",
				task_name = "Restart web (myapp)",
				mode = "background",
			}, function(r)
				result = r
			end)

			assert.are.equal("/project", captured_opts.cwd)
			assert.is_truthy(captured_cmd:match("^'docker' 'compose' '%-p' 'myapp' 'restart' 'web'$"))

			captured_opts.on_stdout(nil, { "line1", "line2" })
			captured_opts.on_stderr(nil, { "warn1" })
			captured_opts.on_exit(nil, 0)
			vim.wait(50, function()
				return result ~= nil
			end)

			assert.is_true(result.ok)
			assert.are.equal(0, result.exit_code)
			assert.are.same({ "line1", "line2" }, result.stdout)
			assert.are.same({ "warn1" }, result.stderr)
		end)

		it("reports ok = false on a non-zero exit code", function()
			vim.fn.jobstart = function(_, opts)
				opts.on_exit(nil, 1)
				return 1
			end

			local result
			runner.jobstart_runner({
				cmd = "docker",
				args = { "stop", "abc" },
				task_name = "Stop abc",
				mode = "background",
			}, function(r)
				result = r
			end)

			vim.wait(50, function()
				return result ~= nil
			end)
			assert.is_false(result.ok)
			assert.are.equal(1, result.exit_code)
		end)
	end)

	describe("terminal_runner", function()
		local previous_termopen

		before_each(function()
			previous_termopen = vim.fn.termopen
		end)

		after_each(function()
			vim.fn.termopen = previous_termopen
			pcall(vim.cmd, "stopinsert")
		end)

		it("mounts a terminal split and runs the shell-escaped command", function()
			local mounted, mapped_keys = false, {}
			without_module("nui.split", function()
				package.preload["nui.split"] = function()
					return function()
						return {
							bufnr = 0,
							mount = function()
								mounted = true
							end,
							hide = function() end,
							map = function(_, _, key, fn)
								mapped_keys[key] = fn
							end,
						}
					end
				end

				local termopen_cmd, termopen_opts
				vim.fn.termopen = function(cmd, opts)
					termopen_cmd, termopen_opts = cmd, opts
					return 1
				end

				runner.terminal_runner({
					cmd = "docker",
					args = { "compose", "-p", "myapp", "logs", "-f", "web" },
					cwd = "/project",
					task_name = "Logs: web (myapp)",
					mode = "interactive",
				})

				assert.is_true(mounted)
				assert.is_truthy(termopen_cmd:match("^'docker' 'compose'"))
				assert.are.equal("/project", termopen_opts.cwd)
				assert.is_function(mapped_keys["q"])
			end)
		end)
	end)

	describe("overseer_runner", function()
		it("starts a terminal-strategy task and reports the result via on_complete", function()
			local STATUS = { SUCCESS = "SUCCESS", FAILURE = "FAILURE" }
			local started, subscribed_event, completion_cb
			local fake_task = {
				exit_code = 0,
				subscribe = function(_, event, cb)
					subscribed_event = event
					completion_cb = cb
				end,
				start = function()
					started = true
				end,
			}
			local captured_task_opts
			package.preload["overseer"] = function()
				return {
					new_task = function(opts)
						captured_task_opts = opts
						return fake_task
					end,
				}
			end
			package.preload["overseer.constants"] = function()
				return { STATUS = STATUS }
			end
			package.loaded["overseer"] = nil
			package.loaded["overseer.constants"] = nil

			local result
			runner.overseer_runner({
				cmd = "docker",
				args = { "compose", "-p", "myapp", "up", "-d" },
				cwd = "/project",
				task_name = "Up myapp",
				mode = "background",
			}, function(r)
				result = r
			end)

			assert.are.equal("docker", captured_task_opts.cmd)
			assert.are.equal("terminal", captured_task_opts.strategy)
			assert.is_true(started)
			assert.are.equal("on_complete", subscribed_event)

			completion_cb(fake_task, STATUS.SUCCESS)
			assert.is_true(result.ok)
			assert.are.equal(0, result.exit_code)

			package.preload["overseer"] = nil
			package.preload["overseer.constants"] = nil
		end)
	end)

	describe("run", function()
		it("dispatches background specs to jobstart_runner by default", function()
			local previous = runner.jobstart_runner
			local called_with
			runner.jobstart_runner = function(spec, cb)
				called_with = { spec = spec, cb = cb }
			end
			runner.run({ cmd = "docker", args = {}, task_name = "t", mode = "background" }, function() end)
			assert.is_not_nil(called_with)
			runner.jobstart_runner = previous
		end)

		it("dispatches interactive specs to terminal_runner by default", function()
			local previous = runner.terminal_runner
			local called = false
			runner.terminal_runner = function()
				called = true
			end
			runner.run({ cmd = "docker", args = {}, task_name = "t", mode = "interactive" })
			assert.is_true(called)
			runner.terminal_runner = previous
		end)

		it('dispatches to overseer_runner when runner = "overseer"', function()
			config.current = vim.tbl_deep_extend("force", {}, config.default, { runner = "overseer" })
			local previous = runner.overseer_runner
			local called = false
			runner.overseer_runner = function()
				called = true
			end
			package.preload["overseer"] = function()
				return {}
			end
			package.loaded["overseer"] = nil

			runner.run({ cmd = "docker", args = {}, task_name = "t", mode = "background" }, function() end)

			assert.is_true(called)
			runner.overseer_runner = previous
			package.preload["overseer"] = nil
		end)

		it('falls back to the default runner and warns when runner = "overseer" but overseer is missing', function()
			config.current = vim.tbl_deep_extend("force", {}, config.default, { runner = "overseer" })
			local previous = runner.jobstart_runner
			local called = false
			runner.jobstart_runner = function()
				called = true
			end
			local previous_notify = vim.notify
			local warned = false
			vim.notify = function(_, level)
				if level == vim.log.levels.WARN then
					warned = true
				end
			end

			without_module("overseer", function()
				runner.run({ cmd = "docker", args = {}, task_name = "t", mode = "background" }, function() end)
			end)

			assert.is_true(called)
			assert.is_true(warned)
			runner.jobstart_runner = previous
			vim.notify = previous_notify
		end)

		it("calls a custom function runner directly", function()
			local received_spec, received_cb
			config.current = vim.tbl_deep_extend("force", {}, config.default, {
				runner = function(spec, cb)
					received_spec, received_cb = spec, cb
				end,
			})
			local cb = function() end
			local spec = { cmd = "docker", args = {}, task_name = "t", mode = "background" }
			runner.run(spec, cb)
			assert.are.equal(spec, received_spec)
			assert.are.equal(cb, received_cb)
		end)
	end)
end)
