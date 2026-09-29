--- Discovers Docker Compose files across the configured workspace directories, and resolves
--- each into its canonical project name/services/networks/volumes via
--- `docker compose config`, so a stack that has never been started still shows up in the
--- sidebar (as a fully "down" deployment).
local M = {}

--- Recursively collects files matching `patterns` under `dir`, bounded by `max_depth`.
--- @param dir string
--- @param patterns string[]
--- @param depth integer
--- @param max_depth integer
--- @param found string[]
local function scan_dir(dir, patterns, depth, max_depth, found)
	if depth > max_depth then
		return
	end
	local ok, iter = pcall(vim.fs.dir, dir)
	if not ok or not iter then
		return
	end
	for name, kind in iter do
		if kind == "file" and vim.tbl_contains(patterns, name) then
			table.insert(found, dir .. "/" .. name)
		elseif kind == "directory" and name ~= ".git" and name ~= "node_modules" then
			scan_dir(dir .. "/" .. name, patterns, depth + 1, max_depth, found)
		end
	end
end

--- @return string[] absolute compose file paths found under `config.current.compose.project_dirs`
function M.find_compose_files()
	local config = require("docker-sidebar.config")
	local compose_config = (config.current or config.default).compose
	local dirs = compose_config.project_dirs
	if type(dirs) == "function" then
		dirs = dirs()
	end
	local found = {}
	for _, dir in ipairs(dirs or {}) do
		scan_dir(vim.fs.normalize(dir), compose_config.file_patterns, 0, compose_config.scan_depth, found)
	end
	return found
end

--- Resolves a single compose file into its canonical project config via
--- `docker compose -f <file> config --format json` (run with `cwd` = the file's directory).
--- @param file_path string
--- @return {name:string, services:string[], networks:string[], volumes:string[], config_file:string, cwd:string}|nil
function M.resolve_compose_file(file_path)
	local cwd = vim.fs.dirname(file_path)
	local ok, result = pcall(function()
		return vim.system(
			{ "docker", "compose", "-f", file_path, "config", "--format", "json" },
			{ text = true, cwd = cwd }
		)
			:wait()
	end)
	if not ok or result.code ~= 0 then
		vim.notify("DockerSidebar: could not resolve compose file: " .. file_path, vim.log.levels.WARN)
		return nil
	end
	local decode_ok, decoded = pcall(vim.json.decode, result.stdout or "")
	if not decode_ok or type(decoded) ~= "table" or not decoded.name then
		vim.notify("DockerSidebar: invalid `docker compose config` output for: " .. file_path, vim.log.levels.WARN)
		return nil
	end
	return {
		name = decoded.name,
		services = vim.tbl_keys(decoded.services or {}),
		networks = vim.tbl_keys(decoded.networks or {}),
		volumes = vim.tbl_keys(decoded.volumes or {}),
		config_file = file_path,
		cwd = cwd,
	}
end

--- Full scan: `find_compose_files()` + `resolve_compose_file()` for each, keyed by resolved
--- project name. Always re-scans (no caching); refresh semantics live in the sidebar layer.
--- @return table<string, {name:string, services:string[], networks:string[], volumes:string[], config_file:string, cwd:string}>
function M.scan()
	local result = {}
	for _, file in ipairs(M.find_compose_files()) do
		local resolved = M.resolve_compose_file(file)
		if resolved then
			result[resolved.name] = resolved
		end
	end
	return result
end

return M
