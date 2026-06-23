terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "docker" {}

# GLM Configuration Variables (for Coding Plan)
variable "glm_api_url" {
  description = "GLM API URL for Coder Coding Plan (leave empty for default)"
  type        = string
  default     = ""
}


variable "docker_image" {
  description = "Docker image to use for the workspace"
  type        = string
  default     = "codercom/enterprise-base:ubuntu"
}

variable "container_memory" {
  description = "Container memory limit in MB"
  type        = number
  default     = 4096
}

variable "preview_port" {
  description = "Port the dev server (Astro or Go) listens on; surfaced as the Preview app"
  type        = number
  default     = 4321
}

# Data sources
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Coder Agent
resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = templatefile("${path.module}/scripts/setup.tftpl", {})

  env = {
    GIT_AUTHOR_NAME   = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL  = "${data.coder_workspace_owner.me.email}"
    CODER_GLM_API_URL = var.glm_api_url
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# Docker Image
# Use a resource (not a data source) so the image is pulled when missing from
# the local Docker cache. `data.docker_image` only reads the cache and never
# pulls, which causes "did not find docker image" errors after the image gets
# pruned from the host. `keep_locally` prevents the shared base image from being
# removed when a workspace is destroyed.
resource "docker_image" "main" {
  name         = var.docker_image
  keep_locally = true
}

# Docker Volume for home directory
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
}

# Docker Container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"

  command = ["sh", "-c", replace(coder_agent.main.init_script, "/etc/skel", "/home/coder")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CODER_GLM_API_URL=${var.glm_api_url}"
  ]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }

  # Resource limits
  memory = var.container_memory
}

# Claude Code Module
module "claude-code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.2.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/projects"
  model    = "sonnet"

  # Install Terraform debugging skill
  post_install_script = <<-EOT
    mkdir -p ~/.claude/skills
    cat > ~/.claude/skills/terraform-debug.md <<'EOF'
    # Terraform Debugging Skill

    Enables Terraform debugging with detailed logging.

    ## Environment Variables
    - `TF_LOG=INFO` - Standard debugging
    - `TF_LOG=DEBUG` - Verbose debugging
    - `TF_LOG_PATH` - Log file location (default: /tmp/terraform-debug.log)

    ## Usage
    Set environment variable before running terraform commands:
    \`\`\`bash
    export TF_LOG=INFO
    terraform plan
    \`\`\`
    EOF

    echo "✓ Terraform debugging skill installed"
  EOT
}

# code-server Module
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.4.3"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/projects"
  extensions = [
    "golang.go",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "hashicorp.terraform",
  ]
  settings = {
    "workbench.iconTheme"     = "vs-seti"
    "editor.formatOnSave"     = true
    "editor.defaultFormatter" = "esbenp.prettier-vscode"
    "go.useLanguageServer"    = true
    "gopls"                   = { "ui.semanticTokens" = true }
    "[go]"                    = { "editor.defaultFormatter" = "golang.go" }
    "[terraform]"             = { "editor.defaultFormatter" = "hashicorp.terraform" }
  }
}

# Preview App
# Subdomain-based so Vite/Astro HMR works out of the box. Coder's path-based
# proxy strips the URL prefix, which breaks dev-server asset URLs and the HMR
# WebSocket; subdomain apps hand the dev server a clean root, so HMR connects
# with no special config. Requires the Coder server to be configured with a
# wildcard app hostname (--wildcard-access-url).
#
# Run your dev server on var.preview_port (default 4321), then open this app:
#   Astro: `astro dev --host`            (binds 0.0.0.0:4321)
#   Go:    `go run .` / air, listening on :4321
resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Preview"
  icon         = "${data.coder_workspace.me.access_url}/icon/code.svg"
  subdomain    = true
  url          = "http://localhost:${var.preview_port}"
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:${var.preview_port}"
    interval  = 5
    threshold = 6
  }
}
