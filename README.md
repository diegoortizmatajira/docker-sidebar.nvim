# docker-sidebar.nvim

`docker-sidebar.nvim` is a Neovim plugin that gives you a toggleable sidebar for browsing
Docker Compose deployments and standalone containers, with actions (start/stop/restart/
pause/logs/exec/remove, plus deployment-level up/down) right from the tree. Command
execution is pluggable: run everything with the built-in default, delegate to
[overseer.nvim](https://github.com/stevearc/overseer.nvim), or hand it off to your own
runner.

## Features

- Toggleable sidebar showing Docker Compose deployments (with their services, networks, and
  volumes) plus a separate group for standalone containers not managed by Compose.
- Deployments are populated from both live Docker state (`docker compose ls`, `docker ps`,
  `docker network/volume ls`) and a workspace compose-file scan, so a stack that has never
  been started still shows up (as a "down" deployment you can bring up from the tree).
- Per-node actions: start/stop/restart, pause/unpause, remove, logs (follow), exec shell, and
  deployment-level up/down.
- Status-aware icons and highlight groups, fully overridable.
- A pluggable command runner: built-in `jobstart`/terminal execution by default, an
  `overseer.nvim` integration, or a fully custom `function(spec, callback)` extension point.
- Health check (`:checkhealth docker-sidebar`).

## Prerequisites

- Neovim 0.10 or higher (uses `vim.system`).
- `docker` CLI with the Compose v2 plugin (`docker compose ...`) installed and on your `PATH`.
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required — used for the sidebar tree
  and the default interactive-terminal runner).
- [overseer.nvim](https://github.com/stevearc/overseer.nvim) (optional — only needed when you
  set `runner = "overseer"`).

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'diegoortizmatajira/docker-sidebar.nvim',
    dependencies = {
        'MunifTanjim/nui.nvim',
    },
    opts = {}
}
```

## Configuration

The plugin works out of the box with `setup({})`. All options below can be overridden via
`vim.tbl_deep_extend` merge:

```lua
require('docker-sidebar').setup({
    -- Pluggable command runner. Every sidebar action (start/stop/restart/pause/unpause/
    -- remove/logs/exec/up/down) funnels through this.
    --   nil (default)  -> built-in jobstart runner for background actions, built-in
    --                      terminal split (via nui.Split + termopen) for interactive ones
    --                      (logs -f, exec)
    --   "overseer"     -> route both modes through overseer.nvim's terminal strategy
    --                      (falls back to the default runner with a warning if
    --                      overseer.nvim isn't installed)
    --   function(spec, callback) ... end -> fully custom runner; see below
    runner = nil,

    -- Workspace compose-file discovery: finds docker-compose.yml/compose.yaml files not
    -- (yet) known to the Docker daemon, so never-started stacks still appear in the tree.
    compose = {
        project_dirs = function() return { vim.fn.getcwd() } end,
        file_patterns = { 'docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml' },
        scan_depth = 3,
    },

    -- Sidebar behaviour
    sidebar = {
        keybindings = {
            toggle_expand = { 't', '<CR>' },
            expand        = { 'o' },
            collapse      = { 'c' },
            quit          = { 'q' },
            refresh       = { 'r' },
            refresh_all   = { 'R' },
            start         = { 's' },
            stop          = { 'S' },
            restart       = { 'x' },
            pause         = { 'p' },
            unpause       = { 'P' },
            remove        = { 'd' },
            logs          = { 'L' },
            exec          = { 'e' },
            up            = { 'u' },
            down          = { 'U' },
            edit          = { 'E' },
            inspect       = { 'i' },
            help          = { '?' },
        },
        -- Gate deployment `down` and service/container `remove` behind a confirmation prompt
        confirm_destructive = true,
    },

    -- Icons used in the sidebar (per node kind, plus per container/service status)
    icons = {
        tree = {
            chevron_open = ' ', chevron_closed = ' ',
            deployments_group = ' ', standalone_group = ' ',
            deployment = '󰡨 ',
            services_group = ' ', networks_group = '󰛳 ', volumes_group = '󰆺 ',
            network = '󰛳 ', volume = '󰆺 ',
        },
        status = { running = '● ', stopped = '○ ', paused = '⏸ ', restarting = '↻ ', other = '? ' },
    },

    -- Highlight groups for sidebar nodes and status icons
    highlight = {
        tree = {
            chevron = '@constant', default_icon = '@symbol', folder = '@symbol',
            deployment = '@type',
            network = '@macro', volume = '@macro',
        },
        status = {
            running = 'DiagnosticOk', stopped = 'Comment',
            paused = 'DiagnosticWarn', restarting = 'DiagnosticWarn', other = 'DiagnosticHint',
        },
    },
})
```

### Using `overseer.nvim` as the runner

```lua
require('docker-sidebar').setup({
    runner = 'overseer',
})
```

Every action opens (or reuses) an overseer terminal-strategy task, the same way
`db-cli-adapter.nvim` displays command output.

### Using a fully custom runner

The custom runner receives a `spec` table with `cmd`, `args`, `cwd` (the deployment's
compose-file directory, or `nil` for standalone containers), `env`, `task_name` (a
human-readable label such as `"Restart web (myapp)"`), and `mode` (`"background"` or
`"interactive"`). For `"background"` specs, call `callback` with
`{ ok, exit_code, stdout, stderr }` once the command finishes; `"interactive"` specs (logs
`-f`, exec) never carry a callback — your runner is expected to attach its own terminal.

```lua
require('docker-sidebar').setup({
    runner = function(spec, callback)
        if spec.mode == 'interactive' then
            -- e.g. open your own terminal/float and run spec.cmd/spec.args in spec.cwd
            return
        end
        -- e.g. hand off to your own task queue / notification system
        my_task_runner.run(spec.cmd, spec.args, { cwd = spec.cwd, name = spec.task_name }, function(result)
            callback({ ok = result.exit_code == 0, exit_code = result.exit_code, stdout = result.stdout, stderr = result.stderr })
        end)
    end,
})
```

## Usage

### Commands

| Command                  | Description                          |
| ------------------------ | ------------------------------------- |
| `:DockerSidebarToggle`   | Toggle the Docker sidebar             |
| `:DockerSidebarRefresh`  | Refresh the whole tree                |

### Suggested keymaps

The plugin does not set any global keymaps by default. Here is a suggested configuration:

```lua
vim.keymap.set('n', '<leader>ds', '<cmd>DockerSidebarToggle<cr>', { desc = 'Toggle Docker sidebar' })
```

### Sidebar keybindings

Once the sidebar is open, the following keys are available (configurable via
`sidebar.keybindings`):

| Key            | Action                | Applies to                          |
| -------------- | --------------------- | ------------------------------------ |
| `t` / `<CR>`   | Toggle expand/collapse | any expandable node                  |
| `o`            | Expand node            | any expandable node                  |
| `c`            | Collapse node          | any expandable node                  |
| `q`            | Close sidebar          | —                                     |
| `r`            | Refresh nearest ancestor | any node                           |
| `R`            | Refresh the whole tree | —                                     |
| `?`            | Show contextual help window | —                                |
| `s`            | Start                  | deployment, service, container        |
| `S`            | Stop                   | deployment, service, container        |
| `x`            | Restart                | deployment, service, container        |
| `p`            | Pause                  | deployment, service, container        |
| `P`            | Unpause                | deployment, service, container        |
| `d`            | Remove (confirms)      | service, container                    |
| `L`            | Logs (follow)          | deployment, service, container         |
| `e`            | Exec shell             | service, container                    |
| `u`            | Up (`compose up -d`)   | deployment                            |
| `U`            | Down (confirms)        | deployment                            |
| `E`            | Open compose file in the main window | deployment              |
| `i`            | Inspect (view JSON) in the main window | network, volume       |

Pressing an action key on a node that doesn't support it (e.g. `u`/`U` on a service node, or
`i` on anything but a network/volume node) shows a warning instead of doing nothing silently.

`L` (logs) follows every service's output at once when pressed on a deployment node
(`docker compose logs -f`); press it on a service or container instead to follow just that
one.

### Tree shape

```
 Deployments
├──  project-a (running)
│   ├──  Services
│   │   ├──  web (2 replicas)
│   │   │   ├──  project-a-web-1 (running)
│   │   │   └──  project-a-web-2 (running)
│   │   └──  db (stopped)
│   ├──  Networks
│   │   └──  project-a_default
│   └──  Volumes
│       └──  project-a_db-data
└──  project-b (down — from compose file, never started)

 Standalone Containers
├──  some-container (running)
└──  another-container (paused)
```

Each service is a single, expandable node — even a scaled service (`docker compose up
--scale web=2`) shows up once, expandable to reveal the container(s) actually running it.
Actions on the service node (start/stop/restart/...) target the whole service via
`docker compose`; act on one specific replica instead by expanding it and acting on its
container child directly.

Deployments and Standalone Containers are two independent top-level groups — there's no
enclosing "Docker" root node, since the whole sidebar is already Docker-specific.

### Health check

Run `:checkhealth docker-sidebar` to verify that `docker`, the Compose v2 plugin, and
`nui.nvim` are available (and whether `overseer.nvim` is installed).

## Known limitations / deferred

- No support for remote Docker contexts (`DOCKER_HOST`) yet.
- A project directory with multiple compose files is resolved via whichever file
  `compose.project_dirs`'s scan finds first with that project name; multi-file-per-project
  merging isn't modeled yet.
- No tree filtering/search.

## Testing

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). Run them with:

```bash
./tests/run_tests.sh            # run all tests
./tests/run_tests.sh config_spec # run a specific test file
```

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This plugin is licensed under the MIT License. See the [LICENSE](LICENSE) file for more
details.
