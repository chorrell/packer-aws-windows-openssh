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

variable "enable_fast_launch" {
  type    = bool
  default = true
}

variable "workflow_run_id" {
  type    = string
  default = ""
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
  # Prefer pools with low interruption risk; the default (lowest-price) picks
  # the cheapest pool, which is the most likely to be reclaimed mid-build
  spot_allocation_strategy = "price-capacity-optimized"
  spot_instance_types      = ["c8i.xlarge", "c8a.xlarge", "c7i.xlarge", "c7a.xlarge", "c6i.xlarge", "c6a.xlarge", "m8i.xlarge", "m8a.xlarge", "m7i.xlarge", "m7a.xlarge", "m6i.xlarge", "m6a.xlarge"]
  ssh_timeout              = "10m"
  ssh_username             = "Administrator"
  ssh_file_transfer_method = "sftp"
  user_data_file           = "files/SetupSsh.ps1"
  # This ensures the instace has enough disk space and that
  # the volume_type is gp3 for better performance
  launch_block_device_mappings {
    device_name           = "/dev/sda1" # sda1 is the root device for Windows AMIs
    volume_size           = 100         # The default is 30GB, which isn't enough
    volume_type           = "gp3"
    iops                  = 3000 # Default for gp3
    throughput            = 125  # Default for gp3
    delete_on_termination = true
    # Encrypt the build volume at launch (default aws/ebs key) so the AMI and
    # its snapshots are encrypted without an encrypt_boot copy step
    encrypted = true
  }
  # The encrypted root volume produces a full (non-incremental) snapshot of the
  # unencrypted base image, which can take over 30 minutes (Packer's default wait)
  aws_polling {
    delay_seconds = 30
    max_attempts  = 120
  }
  # Register the AMI so instances launched from it require IMDSv2 by default;
  # metadata_options below only applies to the build instance
  imds_support = "v2.0"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  fast_launch {
    enable_fast_launch = var.enable_fast_launch
  }
  run_tags = {
    Name          = "packer-build-${var.ami_name_prefix}"
    WorkflowRunId = var.workflow_run_id
  }

  run_volume_tags = {
    WorkflowRunId = var.workflow_run_id
  }

  spot_tags = {
    WorkflowRunId = var.workflow_run_id
  }

  snapshot_tags = {
    Name          = "${var.image_name}"
    BuildTime     = "${local.timestamp}"
    WorkflowRunId = var.workflow_run_id
  }

  tags = {
    Name          = "${var.image_name}"
    BuildTime     = "${local.timestamp}"
    WorkflowRunId = var.workflow_run_id
  }
}

build {
  sources = ["source.amazon-ebs.aws-windows-ssh"]

  # Add custom provisioners here; PrepareImage.ps1 must stay last since it runs Sysprep
  provisioner "powershell" {
    script           = "files/PrepareImage.ps1"
    valid_exit_codes = [0, 2300218]
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
