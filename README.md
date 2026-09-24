# Windows AMI with ssh

[![Build and Test AMI](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/build-and-test-ami.yml/badge.svg)](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/build-and-test-ami.yml)
[![Test PowerShell Scripts](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/test.yml/badge.svg)](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/test.yml)
[![PSScriptAnalyzer](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/PSScriptAnalyzer.yml/badge.svg)](https://github.com/chorrell/packer-aws-windows-openssh/actions/workflows/PSScriptAnalyzer.yml)

This repository contains a Packer template and supporting files for creating an AWS Windows AMI with OpenSSH. The code in this repository is inspired by this [blog post](https://operator-error.com/2018/04/16/windows-amis-with-even/) and accompanying [code](https://github.com/jen20/packer-aws-windows-ssh).

This is an updated implementation of `packer-aws-windows-ssh` with the following changes:

- The Packer template `aws-windows-ssh.pkr.hcl` is coded in [HCL2](https://developer.hashicorp.com/packer/guides/hcl) rather than JSON.
- The image is based on Windows Server 2022
- OpenSSH is installed with `Add-WindowsCapability` per <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell#install-openssh-for-windows>
- The code for downloading the ssh key is somewhat simplified and saves it to `$env:ProgramData\ssh\administrators_authorized_keys`
- Sysprep is run via the newer [EC2launch](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch.html)
- The template enables [Fast Launch](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/win-ami-config-fast-launch.html) for the AMI (see `enable_fast_launch = true`)

## Usage

In order to build this image you need an AWS account and an access key. Once you have that you need to set the following environment variables:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`

You can put this in your `.zshrc` or `.bashrc` file, for example:

```bash
# AWS packer config
export AWS_ACCESS_KEY_ID="<ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<AWS_SECRET_ACCESS_KEY>"
export AWS_DEFAULT_REGION="ca-central-1"
```

Once that's setup you'll need to initialize the template:

```bash
packer init .
```

Now build the image:

```bash
packer build aws-windows-ssh.pkr.hcl
```

## Customizing the image

The image intentionally includes only what's needed for SSH access. To add your own software or configuration, add a provisioner to the `build` block in `aws-windows-ssh.pkr.hcl`, before the `PrepareImage.ps1` provisioner. `PrepareImage.ps1` must run last because it removes build-time SSH keys and runs Sysprep.

For example, to install a pinned version of [Chocolatey](https://chocolatey.org) and a pinned package:

```hcl
provisioner "powershell" {
  # The Chocolatey install script installs the version in chocolateyVersion
  # instead of the latest release
  environment_vars = ["chocolateyVersion=2.7.4"]
  inline = [
    "Set-ExecutionPolicy Bypass -Scope Process -Force",
    "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
    "Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
    "choco install git --version=2.55.0.5 -y",
  ]
}
```

Anything installed this way is baked into every instance launched from the AMI, so pin versions as shown above. Pinning `chocolateyVersion` controls which Chocolatey release is installed, but `install.ps1` itself is always fetched fresh. To guard against changes to it, download it, compare its SHA-256 hash to a known value, and only then run it.
