local health = require("docker-sidebar.health")
local utils = require("docker-sidebar.utils")

describe("health", function()
	local previous_executable, previous_ok, previous_warn, previous_error, previous_start, previous_system
	local ok_messages, warn_messages, error_messages

	before_each(function()
		previous_executable = vim.fn.executable
		previous_ok = vim.health.ok
		previous_warn = vim.health.warn
		previous_error = vim.health.error
		previous_start = vim.health.start
		previous_system = vim.system

		ok_messages, warn_messages, error_messages = {}, {}, {}
		vim.health.start = function() end
		vim.health.ok = function(msg)
			table.insert(ok_messages, msg)
		end
		vim.health.warn = function(msg)
			table.insert(warn_messages, msg)
		end
		vim.health.error = function(msg)
			table.insert(error_messages, msg)
		end
		vim.system = function()
			return {
				wait = function()
					return { code = 0 }
				end,
			}
		end
	end)

	after_each(function()
		vim.fn.executable = previous_executable
		vim.health.ok = previous_ok
		vim.health.warn = previous_warn
		vim.health.error = previous_error
		vim.health.start = previous_start
		vim.system = previous_system
	end)

	local function set_executable(available)
		vim.fn.executable = function()
			return available and 1 or 0
		end
	end

	it("errors when docker is missing", function()
		set_executable(false)
		health.check()
		assert.is_true(#error_messages > 0)
		assert.is_truthy(error_messages[1]:match("docker"))
	end)

	--- Simulates `name` being absent from the runtime path for the duration of `fn`, even
	--- though it's actually installed in this dev/test environment.
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

	it("errors when nui.nvim is missing", function()
		set_executable(true)
		without_module("nui.split", health.check)
		local found = false
		for _, msg in ipairs(error_messages) do
			if msg:match("nui.nvim") then
				found = true
			end
		end
		assert.is_true(found)
	end)

	it("warns (not errors) when overseer.nvim is missing", function()
		set_executable(true)
		without_module("overseer", health.check)
		local found = false
		for _, msg in ipairs(warn_messages) do
			if msg:match("overseer.nvim") then
				found = true
			end
		end
		assert.is_true(found)
	end)

	it("utils.check_executable defaults to warn severity", function()
		set_executable(false)
		utils.check_executable("some-tool")
		assert.is_true(#warn_messages > 0)
	end)

	it("utils.check_executable reports error when requested", function()
		set_executable(false)
		utils.check_executable("some-tool", "error")
		assert.is_true(#error_messages > 0)
	end)
end)
