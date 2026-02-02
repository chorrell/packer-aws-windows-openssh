packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "ami_name_prefix" {
  type    = string
  default = "windows-base-2022"
}

variable "image_name" {
  type    = string
  default = "Windows Server 2022 image with ssh"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

data "amazon-ami" "aws-windows-ssh" {
  filters = {
    name                = "Windows_Server-2022-English-Full-Base-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
}

source "amazon-ebs" "aws-windows-ssh" {
  source_ami                  = "${data.amazon-ami.aws-windows-ssh.id}"
  ami_name                    = "${var.ami_name_prefix}-${local.timestamp}"
  ami_description             = "${var.image_name}"
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  spot_price                  = "auto"
  spot_instance_types         = ["c7i.large", "c7a.large", "c6i.large", "c6a.large", "c5a.large", "m6a.large", "m5a.large", "m5.large"]
  ssh_timeout                 = "10m"
  ssh_username                = "Administrator"
  ssh_file_transfer_method    = "sftp"
  user_data_file              = "files/SetupSsh.ps1"
  # This ensures the instace has enough disk space and that
  # the volume_type is gp3 for better performance
  launch_block_device_mappings {
    device_name           = "/dev/sda1" # sda1 is the root device for Windows AMIs
    volume_size           = 100         # The default is 30GB, which isn't enough
    volume_type           = "gp3"
    iops                  = 3000 # Default for gp3
    throughput            = 125  # Default for gp3
    delete_on_termination = true
  }
  fast_launch {
    enable_fast_launch = true
  }
  snapshot_tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
  }

  tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
  }
}

build {
  sources = ["source.amazon-ebs.aws-windows-ssh"]

  provisioner "powershell" {
    script = "files/InstallChoco.ps1"
  }

  provisioner "windows-restart" {
    max_retries = 3
  }

  provisioner "powershell" {
    script = "files/PrepareImage.ps1"
  }
}
