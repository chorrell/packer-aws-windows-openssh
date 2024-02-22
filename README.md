# Windows AMI with ssh

This repository contains a Packer template and supporting files for creating an AWS Windows AMI with OpenSSH. The code in this repository is inspired by this [blog post](https://operator-error.com/2018/04/16/windows-amis-with-even/) and accompanying [code](https://github.com/jen20/packer-aws-windows-ssh).

This is an updated implementation of `packer-aws-windows-ssh` with the following changes:

- The Packer template `aws-windows-ssh.pkr.hcl` is coded in [HCL2](https://developer.hashicorp.com/packer/guides/hcl) rather than JSON.
- The image is based off Windows Server 2022
- OpenSSH is installed with `Add-WindowsCapability` per <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell#install-openssh-for-windows>
- The code for downloading the ssh key is somewhat simplified and saves it to `$env:ProgramData\ssh\administrators_authorized_keys`
- Sysprep is run via the newer [EC2launch](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch.html)
- Installed [Chocolatey](https://chocolatey.org) for package management
- The template enables [Fast Launch](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/win-ami-config-fast-launch.html) for the AMI

## Usage

In order to build this iamge you need and AWS account an access key. Once you have that you need to set the following environent variables:

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

Once that's setup you'll need to initialize the tempalte:

```bash
packer init .
```

Now build the image:

```bash
packer build aws-windows-ssh.pkr.hcl
```
