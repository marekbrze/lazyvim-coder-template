---
name: coder-templates
description: Edit and maintain this standalone Coder workspace template — coder_agent setup, Docker resources, registry module consumption, parameters, and pushing versions to the Coder deployment
---

# Coder Template (this repo)

This repo is a **single, standalone Coder workspace template** (`main.tf` + `README.md` + `scripts/setup.tftpl`). It is *not* the `coder/registry` monorepo — there is one template, Docker-based, published as **`lazyvim-starter`**.

Use this skill whenever you are asked to change the workspace definition: add resources/modules/parameters, fix provisioning errors, tune resource limits, or push a new template version.

## Deployment & Operations (specific to this template)

These facts are load-bearing — act on them, do not rediscover them:

- **Coder server:** `https://coder.marekbrze.dev`. The `coder` CLI is already authenticated (user `marekbrze`, org `coder`).
- **Published name:** `lazyvim-starter`. Provisioning uses the **Docker provider** against the server's Docker daemon.
- **There is no Docker on this dev shell.** Provisioning runs server-side via Coder provisioners. Never try to `docker pull` / `docker run` locally to "test" an image change — it cannot work here. Image errors must be fixed in the template.
- **`coder templates push` gotcha:** pushing with the default relative `-d .` uploads an **empty** dir to the provisioner ("no Terraform configuration files"). Always pass an **absolute** `-d` path:

  ```bash
  coder templates push lazyvim-starter -d /home/coder/lazyvim-coder-template -m "<message>" -y
  ```

- **`coder update <workspace>` has no `-y` flag** and reuses existing parameters; redirect stdin from `/dev/null` to run non-interactively.
- **`docker_image` must be a resource, not a data source.** `data "docker_image"` only reads the cache and never pulls; once the image is pruned from the provisioner host, every plan fails with `did not find docker image`. This template already uses the resource form with `keep_locally = true` — preserve it.

## Before You Start

1. **Understand the request.** This template is Docker-based, so most changes touch `docker_image` / `docker_volume` / `docker_container`, the `coder_agent`, or a registry module. If the user asks for something that implies another platform (AWS VM, Kubernetes pod), say so explicitly — that is a larger change than they may expect.
2. **Read `main.tf` first.** It is small and is the single source of truth. Understand the current resources, the `coder_agent`, consumed modules (`claude-code`, `code-server`), variables, and the startup script before editing.
3. **Look up modules on the registry.** For any capability you might add, check <https://registry.coder.com> first — prefer consuming an existing module over reimplementing it. Read the module's `main.tf` and `README` to confirm its variables/outputs/prerequisites before passing arguments.
4. **Check provider docs.** Verify the Coder provider and `kreuzwerker/docker` resources you plan to use (version-specific docs if the behavior is subtle).
5. **Clarify before building** if the request is ambiguous (which parameters to expose, which image, what the module should configure). Summarize what you will change before editing for anything beyond a one-line fix.

When editing, note any deviation from the patterns below as improvement opportunities in your response (hardcoded values that should be variables, missing `metadata`, inline logic a module could replace, scripts without error handling).

Prefer the proper implementation over a shortcut. A template is infrastructure users depend on; doing less work is not the same as reducing complexity if it leaves the template fragile.

Features marked "Premium" require a Coder Premium license — note these in your response when you use them.

## Documentation References

### Coder

- Platform docs (latest): <https://coder.com/docs>
- Version-specific docs: `https://coder.com/docs/@v{MAJOR}.{MINOR}.{PATCH}` (e.g. <https://coder.com/docs/@v2.31.5>)
- Creating templates: <https://coder.com/docs/admin/templates/creating-templates>
- Extending templates: <https://coder.com/docs/admin/templates/extending-templates>
- Template parameters: <https://coder.com/docs/admin/templates/extending-templates/parameters>
- Dynamic parameters: <https://coder.com/docs/admin/templates/extending-templates/dynamic-parameters>
- Workspace presets: <https://coder.com/docs/admin/templates/extending-templates/parameters#workspace-presets>
- Prebuilt workspaces: <https://coder.com/docs/admin/templates/extending-templates/prebuilt-workspaces>
- Tasks: <https://coder.com/docs/ai-coder/tasks>
- Agent Boundaries: <https://coder.com/docs/ai-coder/agent-boundaries>
- Coder Registry: <https://registry.coder.com>

### Coder Terraform provider

- Provider docs (latest): <https://registry.terraform.io/providers/coder/coder/latest/docs>
- Version-specific: replace `latest` with a version (e.g. <https://registry.terraform.io/providers/coder/coder/2.13.1/docs>)

Resources:

| Resource         | Docs                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| `coder_agent`    | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent>    |
| `coder_app`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/app>      |
| `coder_script`   | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script>   |
| `coder_env`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/env>      |
| `coder_metadata` | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata> |
| `coder_ai_task`  | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/ai_task>  |

Data sources:

| Data Source              | Docs                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| `coder_parameter`        | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/parameter>        |
| `coder_workspace`        | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace>        |
| `coder_workspace_owner`  | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace_owner>  |
| `coder_provisioner`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/provisioner>      |
| `coder_workspace_preset` | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace_preset> |
| `coder_task`             | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/task>             |

### Terraform providers used here

All provider docs follow `https://registry.terraform.io/providers/ORG/NAME/latest/docs`:

| Provider   | Source               |
| ---------- | -------------------- |
| Docker     | `kreuzwerker/docker` |
| Coder      | `coder/coder`        |
| Cloud-Init | `hashicorp/cloudinit` (if you add a VM-based template later) |

Browse all providers: <https://registry.terraform.io/browse/providers>

## Key Patterns

- **Pull images with a `docker_image` resource, never `data "docker_image"`.** Set `keep_locally = true` so the shared base image survives a workspace destroy. The container references `docker_image.main.image_id`. (See *Deployment & Operations* — this was a real outage cause.)
- Provider version constraints must reflect actual functionality requirements. Only raise the minimum `coder` provider version when the template uses a resource/attribute introduced in that version; same for the Docker provider. Check changelogs to confirm.
- Include `data.coder_workspace.me` and `data.coder_workspace_owner.me` for workspace/owner metadata. Include `data.coder_provisioner.me` only when you need the provisioner's `arch`/`os` for `coder_agent` — this template does (Docker), so it is present.
- Use `locals {}` for computed values: usernames, environment variables, startup scripts, URL assembly.
- Use `data.coder_workspace.me.start_count` as `count` on ephemeral resources (the container and the modules here both do this).
- Connect the container to the agent via `coder_agent.main.init_script` and `CODER_AGENT_TOKEN`. This template rewrites `/etc/skel` → `/home/coder` in the init script — preserve that mapping.
- Add `metadata` blocks on `coder_agent` for dashboard stats (`coder stat cpu`, `coder stat mem`, `coder stat disk`).
- Add `coder_metadata` on the primary compute resource to surface key details (image, memory limit, disk) in the workspace dashboard.
- Optionally use a `display_apps` block to hide specific built-in apps (defaults show all).
- Before implementing functionality from scratch, look for an existing module on <https://registry.coder.com>. Read its `main.tf` and `README` to learn its full interface (variables, outputs, prerequisites, runtime requirements) before passing arguments.
- After identifying a module's prerequisites, verify the base image satisfies them. A missing tool only surfaces when the workspace starts — `terraform validate` will not catch it.
- Module source URLs use `registry.coder.com/<namespace>/<module>/coder` (e.g. `registry.coder.com/coder/claude-code/coder`). Prefer the short form.
- Label infrastructure resources with `coder.owner` and `coder.workspace_id` for orphan tracking.
- Use `lifecycle { ignore_changes = all }` on persistent volumes to prevent data loss.
- Do not add comments that narrate what the code does. Only comment non-obvious constraints (why a workaround exists, a subtle ordering rule).

### Additional files

This template includes files beyond `main.tf`:

- `scripts/setup.tftpl`: the workspace startup script (installs mise, Neovim, LazyVim, Go, Node, etc.), loaded via `templatefile()`. Keep install logic here rather than inlining into `main.tf`.
- If you later add VM provisioning, put cloud-init in `cloud-init/*.tftpl`.
- If you build a custom image, put it in `build/Dockerfile`.

### Parameters

Use `data "coder_parameter"` for user-facing workspace options. This template currently uses plain `variable`s exposed via README `parameters` frontmatter; `coder_parameter` data sources give richer UI controls. Typical parameters for a Docker template: base image, container memory/CPU, disk size.

- Prefer `dynamic "option"` blocks with `for_each` from a `locals` map over static `option` blocks.
- Use `form_type` for richer UI controls: `dropdown` (searchable), `multi-select` (for `list(string)`), `slider` (numeric), `radio`, `checkbox`, `textarea`.
- Conditional parameters: use `count` to show/hide a parameter based on another parameter's value.
- `mutable = false` for infrastructure that cannot change after creation; `mutable = true` for runtime config.
- `ephemeral = true` for one-shot build options that do not persist between starts.
- `validation {}` with `min`/`max`/`monotonic` for numbers, `regex`/`error` for strings.
- Dynamic parameter features require Coder provider `>= 2.4.0`.

### Presets

Workspace presets bundle commonly-used parameter combinations into selectable options, auto-filling multiple parameters at workspace creation. Define with `data "coder_workspace_preset"`:

```tf
data "coder_workspace_preset" "default" {
  name    = "Standard Dev Environment"
  default = true

  parameters = {
    "docker_image"     = "codercom/enterprise-base:ubuntu"
    "container_memory" = "4096"
  }
}
```

- Keys in `parameters` must match the `name` of `coder_parameter` data sources in this template.
- Set `default = true` on at most one preset to pre-select it.
- Optional fields: `description` and `icon`.

### Prebuilds (Premium)

Prebuilds maintain an automatically-managed pool of pre-provisioned workspaces for a preset, cutting creation time. This is a Premium feature, configured as a nested block inside a preset:

```tf
data "coder_workspace_preset" "large" {
  name = "Large"
  parameters = {
    "container_memory" = "8192"
  }

  prebuilds {
    instances = 3

    expiration_policy {
      ttl = 86400
    }

    scheduling {
      timezone = "UTC"
      schedule {
        cron      = "* 8-18 * * 1-5"
        instances = 5
      }
    }
  }
}
```

- `instances`: pool size (base count when no schedule matches).
- `expiration_policy.ttl`: seconds before unclaimed prebuilds are cleaned up.
- `scheduling`: scale the pool on a cron schedule; the `cron` minute field must always be `*`.
- When a prebuild is claimed, ownership transfers to the real user. Use `lifecycle { ignore_changes = [...] }` on owner-specific resources to avoid recreation.

### Task-Oriented Templates

This template already consumes the `claude-code` module. To make it task-capable (enables the Coder Tasks UI for AI agent workflows), add three things on top of the existing agent:

```tf
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.claude-code[count.index].task_app_id
}

data "coder_task" "me" {}

# then pass data.coder_task.me.prompt to the claude-code module as ai_prompt
```

- `coder_ai_task.app_id` must point to the agent module's `task_app_id` output.
- `data "coder_task"` reads the user's task prompt; pass it to the module via `ai_prompt`.
- A `coder_app` with `slug = "preview"` gets special treatment in the Tasks UI navbar.
- Boundaries: set `enable_boundary = true` on the agent module for network-level filtering of the AI agent. See <https://coder.com/docs/ai-coder/agent-boundaries>.

Docs: <https://coder.com/docs/ai-coder/tasks>

## README.md

This repo's README already has frontmatter (`display_name`, `description`, `icon`, `tags`, `parameters`) and documents features/troubleshooting. When you change behavior, update the README to match.

Rules for keeping README consistent:

- Single H1 matching `display_name`, directly below frontmatter.
- Increment header levels by one (h1 → h2 → h3).
- Opening paragraph describes what the template provisions, specifically (platform, key tools) — not generic.
- Keep a **Prerequisites**/**Requirements** section (Docker runtime, RAM, disk).
- Code fences labeled `tf` (not `hcl`).
- This template uses a **URL** for `icon` (e.g. `https://lazyvim.github.io/favicon.svg`). Relative `.icons/` paths are only required if contributing to the public registry — not needed here.

## Testing

Templates are tested by pushing to the Coder deployment, not with `.tftest.hcl`. Before pushing:

```bash
terraform init && terraform validate    # in the repo root
terraform fmt                           # in the repo root
```

If you add shell scripts, lint them with `shellcheck` (install if absent); there is no project-level lint script in this repo.

## Commands

| Task      | Command                              | Scope  |
| --------- | ------------------------------------ | ------ |
| Format    | `terraform fmt`                      | Repo   |
| Validate  | `terraform init && terraform validate` | Repo |
| ShellCheck| `shellcheck <file>` (if scripts added) | File |
| Push      | `coder templates push lazyvim-starter -d /home/coder/lazyvim-coder-template -m "..." -y` | Deploy |

## Final Checks

Before considering the work complete, verify:

- `terraform init && terraform validate` passes in the repo root
- `terraform fmt` has been run (no diff)
- README still matches the template's actual behavior
- Shell scripts in `scripts/` handle errors gracefully (`set -euo pipefail` is already set; use `|| echo "Warning..."` for non-fatal failures). If a script sources external files (`~/.bashrc`, `/etc/os-release`), the `source` must come before `set -u`.
- No hardcoded values that should be variables or parameters
- `docker_image` remains a resource with `keep_locally = true`

## Response to the User

In your response, include:

- The ready-to-run push command with the **absolute** `-d` path (the relative-path form uploads an empty dir here):

  ```bash
  coder templates push lazyvim-starter \
    -d /home/coder/lazyvim-coder-template \
    -m "<brief description of the change>" \
    -y
  ```

- A reminder that there is no local Docker on this shell, so the only way to exercise the change is to push and start/restart a workspace.
- If you used a Premium feature (prebuilds, boundaries beyond defaults), say so.
