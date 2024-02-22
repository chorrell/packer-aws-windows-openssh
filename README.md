# Windows AMI with ssh

This repository contains a Packer template and supporting files for creating an AWS Windows AMI with OpenSSH. The code in this repository is inspired by this [blog post](https://operator-error.com/2018/04/16/windows-amis-with-even/) and accompanying [code](https://github.com/jen20/packer-aws-windows-ssh).

This is an updated implementation of `packer-aws-windows-ssh` with the following changes:

- The Packer template `aws-windows-ssh.pkr.hcl` is coded in [HCL2](https://developer.hashicorp.com/packer/guides/hcl) rather than JSON.
- The image is based off Windows Server 2022
- OpenSSH is installed with `Add-WindowsCapability` per <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell#install-openssh-for-windows>
- The code for downloading the ssh key is somewhat simplified and saves it to `$env:ProgramData\ssh\administrators_authorized_keys`
- Sysprep is run via the newer [EC2launch](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2launch.html)
- Installed [Chocolatey](https://chocolatey.org) for package management
