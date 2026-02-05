# AGENTS instructions for `packer-aws-windows-openssh`

This repository builds an AWS Windows AMI with OpenSSH pre-installed, using Packer and PowerShell provisioning scripts. The project is designed for automation and reproducibility, with a focus on modern Windows Server images and streamlined SSH access.

## Architecture Overview

- **Packer Template**: The main build logic is in [`aws-windows-ssh.pkr.hcl`](./aws-windows-ssh.pkr.hcl), written in HCL2. It defines:
  - The base Windows Server 2022 AMI (auto-discovered via filters)
  - Spot instance usage for cost efficiency (c8i/c8a/c7i/c7a/c6i/c6a/m8i/m8a/m7i/m7a/m6i/m6a instance types)
  - SSH as the communicator, with OpenSSH installed via provisioning
  - IMDSv2 enforcement via `metadata_options` block (`http_tokens = "required"`)
  - 100GB gp3 root volume (vs 30GB default) via `launch_block_device_mappings` for adequate disk space and performance
  - Fast Launch configurable via `enable_fast_launch` variable (default: enabled)
  - Manifest post-processor that outputs AMI IDs to `packer-manifest.json` for CI/CD automation

- **Provisioning Scripts**: All provisioning logic is in [`files/`](./files/):
  - [`SetupSsh.ps1`](./files/SetupSsh.ps1): Installs and configures OpenSSH, sets up firewall rules, and schedules a task to fetch the SSH key from EC2 metadata using IMDSv2 (retrieves a session token with 6-hour TTL via `PUT /latest/api/token`, then uses token to fetch SSH key).
  - [`InstallChoco.ps1`](./files/InstallChoco.ps1): Installs Chocolatey for package management.
  - [`PrepareImage.ps1`](./files/PrepareImage.ps1): Cleans up SSH keys with retry logic (5 attempts with 5-second delays to handle file locks), ensures scheduled tasks are enabled, and runs Sysprep via EC2Launch.

- **CI/CD**: GitHub Actions workflows in [`.github/workflows/`](./.github/workflows/):
  - [`build-and-test-ami.yml`](./.github/workflows/build-and-test-ami.yml): Comprehensive end-to-end testing on pull requests:
    - Validates and builds AMIs using Packer
    - Launches test instances from the built AMI
    - Tests SSH connectivity with automatic retry logic (20 attempts, 30-second intervals)
    - **Validates IMDSv2 enforcement**: Verifies that IMDSv1 is blocked and IMDSv2 works correctly
    - Automatically cleans up all test resources (instances, security groups, SSH keys, AMIs, snapshots)
    - Uses AWS OIDC authentication (no static credentials required)
  - [`PSScriptAnalyzer.yml`](./.github/workflows/PSScriptAnalyzer.yml): Lints PowerShell scripts on pull requests
  - [`markdownlint.yml`](./.github/workflows/markdownlint.yml): Lints Markdown files on pull requests

## Developer Workflows

- **Build the AMI**:
  1. Set AWS credentials in your environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`).
  2. Initialize Packer plugins:

     ```sh
     packer init .
     ```

  3. Build the image:
  
     ```sh
     packer build aws-windows-ssh.pkr.hcl
     ```

- **CI/CD Setup** (for GitHub Actions):
  - Configure AWS OIDC authentication following [`.github/workflows/AWS_OIDC_SETUP.md`](./.github/workflows/AWS_OIDC_SETUP.md)
  - Set up `AWS_ROLE_ARN` secret in GitHub repository settings
  - On pull requests, workflows will automatically:
    - Validate and build AMIs with Packer
    - Launch test instances and verify SSH connectivity
    - Test IMDSv2 enforcement (block IMDSv1, verify IMDSv2 works)
    - Lint PowerShell scripts with PSScriptAnalyzer
    - Lint Markdown files with markdownlint
    - Clean up all test resources

## Project Conventions

- **Script Placement**: All provisioning scripts are in `files/`, referenced directly in the Packer template.
- **No Hardcoded Secrets**: Sensitive variables (e.g., AWS credentials, `.pkrvars.hcl` files) are excluded via [.gitignore](./.gitignore).
- **IMDSv2-only**: The key-fetch task must use IMDSv2 (retrieve a token via `PUT /latest/api/token` with short TTL, do not persist tokens) and set instance/AMI metadata options to require IMDSv2.
- **ACLs**: Ensure `administrators_authorized_keys` has only `SYSTEM` and `BUILTIN\Administrators` read permissions, inheritance disabled, and `sshd_config` has `PubkeyAuthentication yes` with proper `Match Group administrators` settings.
- **Sysprep**: Uses EC2Launch for Sysprep, not the legacy Sysprep tool.
- **Documentation**: All Markdown file additions and changes must pass markdownlint validation before merging. The CI/CD pipeline enforces this on pull requests.

## Integration Points

- **AWS**: Uses the official Amazon Packer plugin and EC2 metadata for SSH key retrieval.
- **Chocolatey**: Installed for future extensibility in package management.
- **Windows Fast Launch**: Enabled for AMI performance.

## References

- Main Packer template: `aws-windows-ssh.pkr.hcl`
- Provisioning scripts: `files/`
- CI/CD workflows: `.github/workflows/`
- AWS OIDC setup guide: `.github/workflows/AWS_OIDC_SETUP.md`
- AMI manifest output: `packer-manifest.json` (generated during builds)
- Usage and rationale: `README.md`
