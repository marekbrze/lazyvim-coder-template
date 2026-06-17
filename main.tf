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

# GLM Configuration Variables
variable "glm_api_url" {
  description = "GLM API URL for Claude Code (leave empty for default Anthropic API)"
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

# Data sources
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Coder Agent
resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Install mise
    echo "Installing mise..."
    curl https://mise.jdx.dev/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"

    # Install LazyVim
    echo "Installing LazyVim..."
    git clone https://github.com/LazyVim/starter ~/.config/nvim

    # Enable Go and TypeScript extras
    cat >> ~/.config/nvim/init.lua <<'EOF'
    -- Enable Go and TypeScript extras
    require("lazyvim.plugins.extras.lang.go")
    require("lazyvim.plugins.extras.lang.typescript")
    EOF

    # Install GitHub CLI
    echo "Installing GitHub CLI..."
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install -y wget)) && \
      (type -p git >/dev/null || sudo apt install -y git) && \
      sudo mkdir -p -m 755 /etc/apt/keyrings && \
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
      sudo apt update && \
      sudo apt install -y gh

    # Install minimal GPG packages for mise verification
    echo "Installing GPG packages for mise..."
    sudo apt install -y --no-install-recommends gnupg gpg-agent dirmngr >/dev/null 2>&1 || true

    # Install Node.js and Go via mise
    echo "Installing Node.js and Go via mise..."
    ~/.local/bin/mise use -g node@lts
    ~/.local/bin/mise use -g go@latest

    # Install language servers for LazyVim
    echo "Installing language servers..."
    ~/.local/bin/mise exec -- go install golang.org/x/tools/gopls@latest
    npm install -g typescript typescript-language-server vscode-langservers-extracted

    # Create terraform helper script
    echo "Installing Terraform debugging helper..."
    mkdir -p ~/.local/bin
    cat > ~/.local/bin/terraform-debug <<'EOF'
    #!/bin/bash
    export TF_LOG=$${TF_LOG:-INFO}
    export TF_LOG_PATH=$${TF_LOG_PATH:-/tmp/terraform-debug.log}
    echo "Terraform debugging enabled. Level: $TF_LOG, Log: $TF_LOG_PATH"
    terraform "$@"
    EOF
    chmod +x ~/.local/bin/terraform-debug

    # Create mise config
    cat > ~/.config/mise/config.toml <<'EOF'
    [tools]
    node = "lts"
    go = "latest"
    EOF

    echo ""
    echo "=========================================="
    echo "✓ mise installed"
    echo "✓ LazyVim with Go + TypeScript extras configured"
    echo "✓ GitHub CLI installed"
    echo "✓ Node.js and Go installed via mise"
    echo "✓ Language servers installed (gopls, tsserver)"
    echo "✓ Terraform debugging helper ready"
    echo "=========================================="
    echo ""
    echo "Start coding with: nvim"
    echo "Manage versions: mise list"
    echo "GitHub CLI: gh --help"
    echo ""
  EOT

  env = {
    GIT_AUTHOR_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL = "${data.coder_workspace_owner.me.email}"
    GLM_API_URL      = var.glm_api_url
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
data "docker_image" "main" {
  name = var.docker_image
}

# Docker Volume for home directory
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
}

# Docker Container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = data.docker_image.main.name
  name  = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"

  command = ["sh", "-c", replace(coder_agent.main.init_script, "/etc/skel", "/home/coder")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "GLM_API_URL=${var.glm_api_url}"
  ]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }

  # Resource limits
  memory = var.container_memory
}

# Claude Code Module with GLM support
module "claude-code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.2.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/projects"
  model    = "sonnet"
  mcp = jsonencode({
    "terraform" = {
      command = "local-exec"
      args    = ["terraform-debug-skill"]
    }
  })

  # GLM Configuration via post_install_script
  post_install_script = <<-EOT
    # Configure GLM API endpoint if provided
    if [ -n "$GLM_API_URL" ]; then
      mkdir -p ~/.claude
      cat > ~/.claude/settings.json <<EOF
    {
      "$schema": "https://code.claude.com/schema/settings.json",
      "apiBaseUrl": "$GLM_API_URL",
      "model": "$${GLM_MODEL:-sonnet}"
    }
    EOF
      echo "✓ GLM configured: $GLM_API_URL"
    fi

    # Install Terraform debugging skill
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

# Coder App for terminal access
resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  display_name = "Terminal"
  slug         = "terminal"
  icon         = "/icon/terminal.svg"
  url          = "https://localhost:0/?command=bash"
}
