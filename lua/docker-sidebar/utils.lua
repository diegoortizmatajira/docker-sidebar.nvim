local M = {}

--- Returns whether the given command is available in the system PATH.
--- @param cmd string
--- @return boolean
function M.is_executable(cmd)
	return vim.fn.executable(cmd) == 1
end

--- Reports a `:checkhealth` line for whether `cmd` is on the PATH.
--- @param cmd string
--- @param severity? "error"|"warn" Severity to report when the command is missing (default "warn")
function M.check_executable(cmd, severity)
	if M.is_executable(cmd) then
		vim.health.ok(string.format("'%s' is installed", cmd))
		return
	end
	local message = string.format("'%s' is not available", cmd)
	if severity == "error" then
		vim.health.error(message)
	else
		vim.health.warn(message)
	end
end

--- Parses Docker's comma-separated "k=v,k2=v2" Labels string into a table.
--- @param labels string|nil
--- @return table<string, string>
function M.parse_labels(labels)
	local result = {}
	if not labels or labels == "" then
		return result
	end
	for pair in vim.gsplit(labels, ",") do
		local key, value = pair:match("^([^=]+)=(.*)$")
		if key then
			result[key] = value
		end
	end
	return result
end

--- Decodes NDJSON (one JSON object per line, as emitted by `docker ... --format json` for
--- multi-item listings) into a list of decoded tables. Blank lines are skipped; a line that
--- fails to decode is dropped with a WARN notify rather than raising an error.
--- @param lines string[]
--- @return table[]
function M.decode_ndjson(lines)
	local result = {}
	for _, line in ipairs(lines) do
		if line ~= "" then
			local ok, decoded = pcall(vim.json.decode, line)
			if ok and type(decoded) == "table" then
				table.insert(result, decoded)
			else
				vim.notify("DockerSidebar: could not parse Docker output line: " .. line, vim.log.levels.WARN)
			end
		end
	end
	return result
end

--- Maps a raw Docker container `State` value to the sidebar's status vocabulary.
--- @param raw_state string|nil
--- @return "running"|"stopped"|"paused"|"restarting"|"other"
function M.normalize_state(raw_state)
	if raw_state == "running" then
		return "running"
	elseif raw_state == "paused" then
		return "paused"
	elseif raw_state == "restarting" then
		return "restarting"
	elseif raw_state == "exited" or raw_state == "created" or raw_state == "dead" then
		return "stopped"
	end
	return "other"
end

--- Shell-escapes and joins a cmd+args list into a single command string, the same pattern
--- used for the default jobstart-based runner.
--- @param cmd string
--- @param args string[]|nil
--- @return string
function M.build_shell_command(cmd, args)
	local full_cmd = vim.list_extend({ cmd }, args or {})
	local escaped = vim.tbl_map(vim.fn.shellescape, full_cmd)
	return table.concat(escaped, " ")
end

return M
