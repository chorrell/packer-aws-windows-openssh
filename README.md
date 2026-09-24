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
- The AMI and its snapshots are encrypted with the default `aws/ebs` KMS key (see [Encryption and build time](#encryption-and-build-time))
- Password authentication is disabled; SSH access is key-only

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

## Encryption and build time

The build instance's root volume sets `encrypted = true` in `launch_block_device_mappings`, so the AMI and its snapshots are encrypted with the account's default `aws/ebs` KMS key. This doesn't depend on the account's [EBS encryption by default](https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html) setting, and it avoids `encrypt_boot`, which creates an intermediate unencrypted AMI and copies it (requiring `ec2:CopyImage`).

Encryption can make AMI creation much slower. The Windows base AMI published by AWS is unencrypted, so an encrypted build volume launched from it shares no snapshot history with it. As a result, the AMI's snapshot is a full copy of every block in use (roughly 25–30 GB for Windows Server 2022) rather than an incremental snapshot of the changes the build made. Expect the "Waiting for AMI to become ready" step to take 30 minutes or more, compared with about 5 minutes for an unencrypted build.

### Building from an encrypted base AMI

To avoid the full copy, build from an **encrypted copy** of the AWS base AMI in your own account. The build volume then shares snapshot history with that copy, so the AMI's snapshot only contains the build's changes.

The template's `source_ami_owner` and `source_ami_name` variables choose the base AMI. By default they use Amazon's AMI. To use an encrypted copy:

```bash
packer build \
  -var "source_ami_owner=self" \
  -var "source_ami_name=encrypted-Windows_Server-2022-English-Full-Base-*" \
  aws-windows-ssh.pkr.hcl
```

CI does this. The [`refresh-base-ami.yml`](.github/workflows/refresh-base-ami.yml) workflow checks weekly for a new AWS base AMI, copies it encrypted as `encrypted-<source name>` (tagged `Purpose=encrypted-base-ami`), and keeps the newest 2 copies. The first copy of each new base AMI takes the full-copy time once. The CI build warns if the copy is behind Amazon's latest AMI. To create a copy by hand in another account or region:

```bash
aws ec2 copy-image --encrypted \
  --source-region us-east-1 --source-image-id <amazon-ami-id> \
  --name "encrypted-<amazon-ami-name>"
```

For builds from Amazon's unencrypted AMI, Packer's default wait for an AMI is 30 minutes (120 checks, 15 seconds apart), which isn't enough. The template raises it with an `aws_polling` block (120 checks, 30 seconds apart, up to 60 minutes). This only extends the timeout; it doesn't slow down builds that finish sooner.

Some notes:

- Shrinking `volume_size` doesn't speed this up. Snapshots only contain blocks that have been written, so the unused space on the 100 GB volume isn't copied.
- AMIs encrypted with the `aws/ebs` key can't be shared with other AWS accounts. To share the AMI, set `kms_key_id` on the root volume to a customer-managed KMS key and grant the other accounts access to that key.

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
