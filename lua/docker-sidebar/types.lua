--- @meta

--- @class DockerSidebar.CommandSpec
--- @field cmd string The command to invoke, e.g. "docker"
--- @field args string[] Arguments to pass to the command
--- @field cwd? string Working directory, e.g. a deployment's compose-file directory. nil for standalone containers.
--- @field env? table<string, string> Extra environment variables
--- @field task_name string Human-readable label, e.g. "Restart web (project-a)"
--- @field mode "background"|"interactive" "background" completes and reports a result; "interactive" attaches a terminal (logs -f, exec)

--- @class DockerSidebar.RunnerResult
--- @field ok boolean True on a zero exit code
--- @field exit_code integer
--- @field stdout string[]
--- @field stderr string[]

--- A pluggable command runner. Every sidebar action funnels through this. `callback` is
--- present for "background" specs and absent for "interactive" specs (the runner is
--- expected to attach its own terminal and has no single result to report).
--- @alias DockerSidebar.Runner fun(spec: DockerSidebar.CommandSpec, callback: (fun(result: DockerSidebar.RunnerResult))|nil)

--- @class DockerSidebar.ContainerInfo
--- @field id string
--- @field name string
--- @field image string
--- @field state "running"|"stopped"|"paused"|"restarting"|"other"
--- @field status string Raw Docker status text, e.g. "Up 8 days"
--- @field project? string Compose project name; nil for standalone containers
--- @field service? string Compose service name; nil for standalone containers

--- @class DockerSidebar.NetworkInfo
--- @field id string
--- @field name string
--- @field project? string
--- @field compose_name? string Local name within the compose file (com.docker.compose.network label)

--- @class DockerSidebar.VolumeInfo
--- @field name string
--- @field project? string
--- @field compose_name? string

--- @class DockerSidebar.DeploymentInfo
--- @field project string
--- @field state "running"|"partial"|"stopped"|"down" "down" = known only from a scanned compose file, never started
--- @field config_file? string Primary compose file path; nil when only known from live Docker state
--- @field cwd? string Directory of config_file, used as cwd for `docker compose -p` invocations
--- @field containers DockerSidebar.ContainerInfo[]
--- @field networks DockerSidebar.NetworkInfo[]
--- @field volumes DockerSidebar.VolumeInfo[]

--- @class DockerSidebar.SidebarKeybindingsConfig
--- @field toggle_expand string[]
--- @field expand string[]
--- @field collapse string[]
--- @field quit string[]
--- @field refresh string[]
--- @field refresh_all string[]
--- @field start string[]
--- @field stop string[]
--- @field restart string[]
--- @field pause string[]
--- @field unpause string[]
--- @field remove string[]
--- @field logs string[]
--- @field exec string[]
--- @field up string[]
--- @field down string[]
--- @field help string[]

--- @class DockerSidebar.ComposeConfig
--- @field project_dirs string[]|fun(): string[] Workspace directories to scan for compose files
--- @field file_patterns string[] e.g. {"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}
--- @field scan_depth integer Max recursion depth under each project dir

--- @class DockerSidebar.SidebarConfig
--- @field keybindings DockerSidebar.SidebarKeybindingsConfig
--- @field confirm_destructive boolean Prompt before deployment `down` / service or container `remove`

--- @class DockerSidebar.IconsConfig
--- @field tree table<string, string>
--- @field status table<string, string>

--- @class DockerSidebar.HighlightConfig
--- @field tree table<string, string>
--- @field status table<string, string>

--- @class DockerSidebar.Config
--- @field runner nil|"overseer"|DockerSidebar.Runner
--- @field compose DockerSidebar.ComposeConfig
--- @field sidebar DockerSidebar.SidebarConfig
--- @field icons DockerSidebar.IconsConfig
--- @field highlight DockerSidebar.HighlightConfig
