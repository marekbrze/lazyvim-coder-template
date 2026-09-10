---
display_name: "LazyVim + mise + Claude Code"
description: "Go & Node.js development environment with LazyVim, mise version manager, Claude Code AI (GLM-ready), GitHub CLI, and a subdomain dev-server preview"
icon: "https://lazyvim.github.io/favicon.svg"
verified: false
tags: ["neovim", "lazyvim", "go", "nodejs", "mise", "claude-code", "github-cli", "glm", "preview"]
parameters:
  - name: glm_api_url
    display_name: GLM API URL
    description: Custom GLM endpoint for Claude Code (optional)
    type: string
    default: ""
    required: false
  - name: docker_image
    display_name: Docker Image
    description: Base Docker image for the workspace
    type: string
    default: "codercom/enterprise-base:ubuntu"
    required: false
  - name: container_memory
    display_name: Container Memory (MB)
    description: Memory limit for the container in megabytes
    type: number
    default: 4096
    required: false
  - name: preview_port
    display_name: Preview Port
    description: Port the Astro/Go dev server listens on (surfaced as the Preview app)
    type: number
    default: 4321
    required: false
---

# LazyVim + mise + Claude Code Template

A complete development environment for Go and Node.js projects with:
- **LazyVim** - Blazing fast Neovim config with Go and TypeScript extras
- **mise** - Unified version manager for Go, Node.js, and more
- **Claude Code** - AI assistant integrated via Coder Tasks
- **GitHub CLI** - Full GitHub operations from terminal

## Features

### LazyVim Configuration
- **Go extra**: gopls LSP, gofumpt formatting, test debugging
- **TypeScript extra**: vtsls/tsserver LSP, ESLint, Prettier
- Pre-configured for terminal-based development

### mise Version Management
- **Node.js LTS** installed and configured
- **Go latest** installed and configured
- Easy switching between versions: `mise use node@22`

### Claude Code Integration
- **Coder module** with `permission_mode = "plan"` for GLM coding plan
- **GLM-ready** - configure `glm_api_url` parameter for custom endpoint
- Coder Tasks integration for AI-assisted development
- Terraform debugging skill pre-installed
- Settings file at `~/.claude/settings.json`

### Development Tools
- **GitHub CLI** (`gh`) - PRs, issues, repos from terminal
- **Language servers**: gopls, tsserver, typescript-language-server
- **Git** pre-configured with your Coder credentials
- **Terraform debugging helper** script

## Usage

### First Start
1. Create workspace from this template
2. Wait for installation (~3-5 minutes)
3. Open terminal and start coding!

### What Survives a Restart
`/home/coder` is a persistent Docker volume; the container itself is recreated
on every start. The startup script installs everything into `$HOME` and skips
steps that are already done, so restarts are fast and keep your changes:

- **LazyExtras** - stored in `~/.config/nvim/lazyvim.json`, never overwritten
- **Neovim config** - `~/.config/nvim` is only cloned on the first start
- **mise tools** - `~/.config/mise/config.toml` is only created on the first start;
  tools added with `mise use -g ...` stay installed
- **Neovim, lazygit, ripgrep, fd, gh, Node.js, Go, LSPs** - live in `~/.local`

Anything installed outside `$HOME` (e.g. `sudo apt-get install ...`) is lost when
the container is recreated. Prefer `mise use -g <tool>`, or put the commands in
an executable `~/.config/coder/startup.sh` - it runs at the end of every start:

```bash
mkdir -p ~/.config/coder
cat > ~/.config/coder/startup.sh <<'EOF'
#!/bin/bash
sudo apt-get install -y htop
EOF
chmod +x ~/.config/coder/startup.sh
```

### LazyVim
```bash
nvim                    # Start LazyVim
:LazyExtras            # Browse and enable extras
```

### mise
```bash
mise list              # Show installed tools
mise use node@22       # Switch Node.js version
mise use go@1.23       # Switch Go version
mise ls-remote node     # List available Node versions
```

### Claude Code with GLM (Coding Plan)
```bash
# GLM is configured via template parameter
# Use Coder Tasks button in dashboard to interact with Claude

# GLM API endpoint is set during workspace creation
# Check current config:
cat ~/.claude/settings.json

# For GLM coding plan, use the Tasks interface
# Claude will operate in plan mode with permission checks
```

**GLM Configuration:**
- Set `glm_api_url` parameter when creating workspace
- `permission_mode = "plan"` ensures safe coding operations
- Default: Anthropic API (add your API key)

### GitHub CLI
```bash
gh auth login         # Authenticate with GitHub
gh pr create          # Create pull request
gh issue list         # List issues
gh repo view          # View repository info
```

### Terraform Debugging
```bash
# Enable debugging
export TF_LOG=INFO
export TF_LOG_PATH=/tmp/terraform.log

# Run terraform commands
terraform plan

# Or use the helper script
terraform-debug plan

# Check logs
cat /tmp/terraform.log
```

### Language Servers
```bash
# Go LSP (gopls) - installed via mise
gopls version

# TypeScript LSP - installed via npm
typescript-language-server --version

# Test in nvim
nvim main.go          # Go file with LSP
nvim index.ts         # TypeScript file with LSP
```

## Dev Server Preview

The template registers a **Preview** app (subdomain-based) that proxies to your dev server on `preview_port` (default **4321**, Astro's default — point a Go server at the same port). Start your dev server, then click **Preview** in the workspace dashboard.

### Astro
```bash
cd ~/projects/my-astro-app
astro dev --host            # binds 0.0.0.0:4321; --host lets HMR resolve correctly
```

### Go
```bash
cd ~/projects/my-go-app
# serve on the preview port, e.g.:
#   http.ListenAndServe(":4321", mux)
go run .
```

### Why subdomains (not path-based)
The Preview app uses `subdomain = true` so Vite/Astro **HMR works out of the box**. Coder's path-based proxy strips the URL prefix before forwarding, which breaks the dev server's absolute asset URLs and the HMR WebSocket. Subdomain apps hand the dev server a clean root (`base = /`), so assets, the `/@vite/client` script, and the HMR socket all resolve correctly.

> Requires the Coder server to be configured with a wildcard app hostname
> (`--wildcard-access-url`). If the Preview app is unreachable, ask your admin
> to set this; without it, subdomain apps cannot resolve.

### If HMR won't connect
Astro usually infers the HMR target from the page URL and works automatically. If live reload fails, set the HMR host in `astro.config.mjs`:
```js
export default defineConfig({
  vite: {
    server: { hmr: { host: 'YOUR-PREVIEW-SUBDOMAIN', clientPort: 443, protocol: 'wss' } },
  },
});
```

## Requirements

- Docker runtime
- 2 GB RAM minimum (4 GB recommended)
- 10 GB disk space

## Customize

### GLM Configuration
To use a custom GLM endpoint:
1. Set `glm_api_url` parameter when creating workspace
2. GLM operates in `plan` permission mode (safe coding)
3. Settings written to `~/.claude/settings.json`

### Add More Tools via mise
To add more tools, edit `scripts/setup.tftpl`:
```bash
~/.local/bin/mise use -g python@latest  # Add Python
~/.local/bin/mise use -g rust@latest   # Add Rust
~/.local/bin/mise use -g java@21       # Add Java
```

Or edit `~/.config/mise/config.toml` after workspace creation:
```toml
[tools]
python = "latest"
rust = "latest"
```

### Enable More LazyVim Extras
Enable interactively in nvim - the choice is saved in `~/.config/nvim/lazyvim.json`
and survives workspace restarts:
```vim
:LazyExtras
# Navigate to desired extra and press 'x' to enable
```

To change the default extras for new workspaces, edit the `lazyvim.json` block
in `scripts/setup.tftpl`:
```json
"extras": [
  "lazyvim.plugins.extras.lang.go",
  "lazyvim.plugins.extras.lang.typescript",
  "lazyvim.plugins.extras.lang.python"
],
```

### Resource Limits
Adjust `container_memory` parameter based on your needs:
- 2048 MB - Minimal development
- 4096 MB - Recommended (default)
- 8192 MB - Large projects

## Project Structure

```
/home/coder/
├── .config/
│   ├── nvim/           # LazyVim configuration (lazyvim.json = enabled extras)
│   ├── mise/           # mise configuration
│   └── coder/          # Optional startup.sh run on every start
├── .local/
│   ├── bin/            # Local binaries (mise, nvim, gopls)
│   ├── opt/            # Neovim installation
│   └── share/          # mise tools, nvim plugins, Mason packages
├── .claude/            # Claude Code settings and skills
└── .gitconfig          # Git configuration
```

## Troubleshooting

### mise not found
```bash
# Add to PATH in ~/.bashrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### LazyVim doesn't start
```bash
# Check Neovim version
nvim --version  # Should be 0.9+

# Reinstall LazyVim (the next workspace start clones a fresh starter)
rm -rf ~/.config/nvim

# Upgrade Neovim (reinstalled with the latest release on the next start)
rm -rf ~/.local/opt/nvim-linux-*
```

### Language servers not working
```bash
# Check gopls
~/.local/bin/mise exec -- gopls version

# Check typescript-language-server
which typescript-language-server

# Reinstall if needed
~/.local/bin/mise exec -- go install golang.org/x/tools/gopls@latest
npm install -g typescript-language-server
```

### GitHub CLI authentication issues
```bash
# Re-authenticate
gh auth logout
gh auth login

# Check status
gh auth status
```

## References

- [LazyVim Documentation](https://lazyvim.github.io/)
- [LazyVim Go Extra](https://lazyvim.github.io/extras/lang/go)
- [LazyVim TypeScript Extra](https://lazyvim.github.io/extras/lang/typescript)
- [mise Documentation](https://mise.jdx.dev/)
- [GitHub CLI Documentation](https://cli.github.com/)
- [Coder Templates](https://coder.com/docs/about/contributing/templates)
