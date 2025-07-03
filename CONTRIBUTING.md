# Contributing to Clusterforge

<div align="center">
  <img src="assets/banner.jpg" alt="Clusterforge - Enterprise Infrastructure for One-Person Companies" width="1012" height="207" />
</div>

---

Clusterforge exists to **level the playing field for one-person and small companies** by making enterprise-grade infrastructure a one-command experience. Your bug fixes, features, docs, and ideas all make the project better and help empower solo founders and small teams to compete with the biggest players.

---

## 1. Ground Rules

| Rule | Why it matters |
|------|----------------|
| **Be kind & professional.** | We follow the [Contributor Covenant](https://www.contributor-covenant.org/) Code of Conduct. |
| **Submit a Pull Request within 30 days** of deploying a modified version. | Keeps the upstream healthy (and is required by our AGPL-3.0 + Commons Clause license). |
| **All contributions are licensed** under **AGPL-3.0 with the Commons Clause**. | Ensures downstream users keep the same freedoms (and limitations). |
| **Sign your commits** (`Signed-off-by:`). | Adds a lightweight [Developer Certificate of Origin](https://developercertificate.org/). |
| **No secrets in code.** | CI will reject PRs that contain API keys, passwords, or private certs. |

---

## 2. Questions & Ideas

- **Search issues first.** Someone may already be working on it.
- Open a new **GitHub Discussion** for design/feature ideas.
- Use **Issues** for bug reports; include logs, steps to reproduce, and your platform details (`clusterforge version` output).

---

## 3. Quick-Start Dev Environment

```bash
# Fork & clone
git clone https://github.com/<your-username>/clusterforge.git
cd clusterforge
git remote add upstream https://github.com/The-One-Person-Company/clusterforge.git

# One-liner to spin up a full stack in Docker-in-Docker
make dev            # needs Docker + make

# Run all linters & unit tests
make check
```

> **Prerequisites**: Docker 24+, GNU Make, Bash 5+, and (optionally) Go 1.22 if you plan to hack on the CLI helpers.

---

## 4. Branch & Pull-Request Workflow

1. Create a feature branch:
   ```bash
   git checkout -b feat/descriptive-name   # for new features
   git checkout -b fix/descriptive-name    # for bug fixes
   git checkout -b docs/descriptive-name   # for documentation
   ```

2. Make focused commits:
   - Keep changes small and logical
   - Use `git add -p` to review changes
   - Test your changes before committing

3. Follow our commit message convention:
   ```
   type(scope): short description

   - Detailed bullet points if needed
   - Breaking changes must be noted

   Signed-off-by: Your Name <your.email@example.com>
   ```

   Types:
   - `feat`: New feature or enhancement
   - `fix`: Bug fix
   - `docs`: Documentation only
   - `refactor`: Code change that neither fixes a bug nor adds a feature
   - `style`: Changes to shell scripts formatting, semicolons, etc.
   - `test`: Adding missing tests or correcting existing tests

4. Push to your fork and open a PR against `main`
5. Ensure all checks pass:
   - ShellCheck validation for bash scripts
   - YAML lint for templates
   - Documentation is updated
6. Respond to review comments promptly

---

## 5. Coding & Style Guide

### Bash Scripts

| Rule | Example | Explanation |
|------|---------|-------------|
| Use shellcheck | `shellcheck script.sh` | All scripts must pass shellcheck |
| 2-space indentation | `if [ "$x" = "y" ]; then`<br>&nbsp;&nbsp;`echo "yes"`<br>`fi` | Consistent spacing |
| Use `#!/usr/bin/env bash` | First line of every script | Portable shebang |
| Quote variables | `"${VARIABLE}"` not `$VARIABLE` | Prevent word splitting |
| Use `set -euo pipefail` | At start of scripts | Fail fast and safely |
| Use functions | `function_name() {` | Modular, reusable code |
| Comment complex logic | `# Explanation of complex operation` | Help others understand |

### YAML Templates

| Rule | Example | Explanation |
|------|---------|-------------|
| 2-space indentation | `apiVersion: v1`<br>`kind: Pod`<br>&nbsp;&nbsp;`metadata:` | Standard K8s format |
| Use comments | `# This template creates a deployment` | Document purpose |
| Template variables | `${VARIABLE_NAME}` | Consistent variable format |
| Group related resources | Separate with `---` | Logical organization |
| Validate syntax | Use `yamllint` | Ensure valid YAML |
| Include defaults | Document in comments | Help users understand options |

### Documentation

- Update README.md when adding new features
- Document all environment variables
- Include example usage
- Add comments in templates explaining options
- Keep line length under 80 characters
- Use markdown tables for structured data

### File Organization

```
./                          # Root directory
├── assets/                 # Images and static assets
├── airbyte/                # Airbyte configuration
├── backup/                 # Velero backup configuration
├── database/               # Database configurations
├── mcp-ghl/               # MCP GoHighLevel templates
│   └── templates/         # GoHighLevel specific templates
├── monitoring/            # Monitoring stack
│   └── dashboards/       # Grafana dashboards
├── n8n/                   # n8n automation platform
├── nocodeapi/            # NoCodeAPI configuration
├── ntfy/                  # Notification service
├── zitadel/              # Identity management
│
├── *.yaml.template        # Core infrastructure templates
│   ├── cloudflare-issuer.yml.template
│   ├── dashboard-ingress.yaml.template
│   └── metallb-config.yaml.template
│
├── *.sh                   # Core scripts
│   ├── 00-config.sh      # Main configuration
│   ├── setup-server.sh   # Initial server setup
│   ├── install.sh        # Main installation script
│   └── get_config.sh     # Configuration helper
│
└── docs/                  # Documentation (if adding new features)
```

#### Key Files

- **Configuration**
  - `00-config.sh`: Main configuration file
  - `*.yaml.template`: Infrastructure templates
  - `.env`: Environment variables (generated from templates)

- **Installation**
  - `setup-server.sh`: Initial server preparation
  - `install.sh`: Main installation orchestrator
  - `get_config.sh`: Configuration management

- **Documentation**
  - `README.md`: Project overview and setup guide
  - `CONTRIBUTING.md`: Contribution guidelines
  - `LICENSE`: AGPL-3.0 + Commons Clause
  - `THIRD_PARTY.md`: Third-party licenses
  - `VERSION`: Current version information

---

## 6. Documentation

User-facing changes require matching doc updates in `/docs`.
Diagrams are drawn in **Excalidraw** (`.excalidraw` source + exported PNG).

---

## 7. Licensing & DCO

By submitting code, you agree that:

- Your contribution is provided under **AGPL-3.0 + Commons Clause**; and
- You have the right to license it (i.e., you wrote it or it's public domain).

Add this trailer to **every** commit:

```
Signed-off-by: Your Name <email@example.com>
```

Git can do this automatically with `git config --global commit.gpgsign true` and `git config --global user.signingkey <key>`.

---

## 8. Security

Found a potential vulnerability?
**Please *do not* open a public issue.**
Email **[it@theoneperson.company](mailto:it@theoneperson.company)** with details and we'll coordinate a fix and disclosure.

---

## 9. Community & Support

- **Discussions:** [https://github.com/The-One-Person-Company/clusterforge/discussions](https://github.com/The-One-Person-Company/clusterforge/discussions)
- **Twitter / X:** [@theonepersonco](https://twitter.com/theonepersonco)

---

## 10. Integrating a New Service

To ensure consistency and reliability, follow these rules when adding a new service to the Clusterforge ecosystem.

### A. Directory Structure

1.  Create a new directory for your service at the root of the project (e.g., `my-new-service/`).
2.  Inside this directory, create an installation script named `<service>-install.sh` (e.g., `my-new-service-install.sh`).
3.  Add all Kubernetes manifest templates (`*.yaml.template`) to this directory.

```
./
├── my-new-service/
│   ├── my-new-service-install.sh
│   ├── deployment.yaml.template
│   ├── service.yaml.template
│   └── ingress.yaml.template
└── ...
```

### B. Installation Script (`<service>-install.sh`)

Your service's installation script must be self-contained and idempotent. It should be modeled after the existing scripts (e.g., `harbor/harbor-install.sh`).

**Key Requirements:**

1.  **Source `00-config.sh`**: Begin the script by sourcing the shared configuration and utilities:
    ```bash
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    source "${WORKSPACE_DIR}/00-config.sh"
    ```

2.  **Implement Core Functions**:
    - `install()`: The main function that orchestrates the installation. It should apply the namespace, secrets, configmaps, PVCs, deployments, and services in the correct order.
    - `init_yaml_files()`: Reads all `.yaml.template` files, substitutes environment variables using `envsubst`, and creates the final `.yaml` manifests.
    - `cleanup()`: A function to completely remove all resources related to the service, including the namespace and PVCs.
    - `soft_cleanup()`: (Optional) A function to remove deployments and pods but preserve the namespace, TLS secrets, and PVCs for faster re-installation.
    - `check_prerequisites()`: Verifies that all dependencies (e.g., database, Redis, other services) are running before installation.
    - `wait_for_deployment()`: Waits for the Kubernetes deployment to become available and for all pods to be in a `Ready` state.
    - `display_access_info()`: Prints the URL, default credentials, and other relevant access information after a successful installation.

3.  **Menu Interface**: Include a `show_menu` function that allows the user to interactively run the install, cleanup, and other functions.

### C. Kubernetes Templates (`*.yaml.template`)

- All Kubernetes manifests must be created as `*.yaml.template` files.
- Use `${VARIABLE_NAME}` syntax for values that need to be substituted from environment variables.
- Add standard labels to all resources for easy identification and management:
  ```yaml
  metadata:
    labels:
      app: my-new-service
      managed-by: script
  ```

### D. Core Project Integration

1.  **`env.template`**: Add all new environment variables required by your service to the `env.template` file. Include comments explaining what each variable is for and provide sensible defaults where possible.
2.  **`install.sh` (Root Script)**: Add an entry for your new service to the main installation menu in the root `install.sh` script. This makes your service discoverable and installable from the central orchestrator.
3.  **`README.md`**: Document your new service in the main `README.md`. Include a brief description of what it does, the environment variables it uses, and any post-installation steps.
4.  **`.gitignore`**: Add the generated YAML files to `.gitignore` to avoid committing them to the repository (e.g., `harbor/*.yaml`).

### Thanks!

Your time and talent make Clusterforge possible.
Happy hacking! 🚀
