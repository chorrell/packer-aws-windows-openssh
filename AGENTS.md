# AGENTS instructions for `packer-aws-windows-openssh`

This repository builds an AWS Windows AMI with OpenSSH pre-installed, using Packer and PowerShell provisioning scripts. The project is designed for automation and reproducibility, with a focus on modern Windows Server images and streamlined SSH access.

## Architecture Overview

- **Packer Template**: The main build logic is in [`aws-windows-ssh.pkr.hcl`](./aws-windows-ssh.pkr.hcl), written in HCL2. It defines:
  - The base Windows Server 2022 AMI (auto-discovered via filters)
  - Spot instance usage for cost efficiency
  - SSH as the communicator, with OpenSSH installed via provisioning
  - Fast Launch enabled for improved AMI boot times

- **Provisioning Scripts**: All provisioning logic is in [`files/`](./files/):
  - [`SetupSsh.ps1`](./files/SetupSsh.ps1): Installs and configures OpenSSH, sets up firewall rules, and schedules a task to fetch the SSH key from EC2 metadata.
  - [`InstallChoco.ps1`](./files/InstallChoco.ps1): Installs Chocolatey for package management.
  - [`PrepareImage.ps1`](./files/PrepareImage.ps1): Cleans up keys, ensures scheduled tasks are enabled, and runs Sysprep via EC2Launch.

- **CI/CD**: GitHub Actions workflows in [`.github/workflows/`](./.github/workflows/) validate Packer templates and run PSScriptAnalyzer on PowerShell scripts.

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

- **CI Validation**:
  - On pull requests, workflows will:
    - Validate the Packer template (`packer validate`)
    - Lint PowerShell scripts with PSScriptAnalyzer

## Project Conventions

- **Script Placement**: All provisioning scripts are in `files/`, referenced directly in the Packer template.
- **No Hardcoded Secrets**: Sensitive variables (e.g., AWS credentials, `.pkrvars.hcl` files) are excluded via [.gitignore](./.gitignore).
- **IMDSv2-only**: The key-fetch task must use IMDSv2 (retrieve a token via `PUT /latest/api/token` with short TTL, do not persist tokens) and set instance/AMI metadata options to require IMDSv2.
- **ACLs**: Ensure `administrators_authorized_keys` has only `SYSTEM` and `BUILTIN\Administrators` read permissions, inheritance disabled, and `sshd_config` has `PubkeyAuthentication yes` with proper `Match Group administrators` settings.
- **Sysprep**: Uses EC2Launch for Sysprep, not the legacy Sysprep tool.

## Integration Points

- **AWS**: Uses the official Amazon Packer plugin and EC2 metadata for SSH key retrieval.
- **Chocolatey**: Installed for future extensibility in package management.
- **Windows Fast Launch**: Enabled for AMI performance.

## References

- Main Packer template: `aws-windows-ssh.pkr.hcl`
- Provisioning scripts: `files/`
- CI workflows: `.github/workflows/`
- Usage and rationale: `README.md`
