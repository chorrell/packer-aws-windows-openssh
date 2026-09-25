BeforeAll {
    $ErrorActionPreference = 'Stop'
}

Describe "SetupSsh Script Configuration" {

    Context "SSH Services Installation" {
        It "should configure ssh-agent service with automatic startup" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "Set-Service.*ssh-agent.*Automatic"
            $scriptContent | Should -Match "Start-Service.*ssh-agent"
        }

        It "should install and configure sshd service" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "Add-WindowsCapability.*OpenSSH\.Server"
            $scriptContent | Should -Match "Set-Service.*sshd.*Automatic"
            $scriptContent | Should -Match "Start-Service.*sshd"
        }

        It "should install OpenSSH.Client capability" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "Add-WindowsCapability.*OpenSSH\.Client"
        }
    }

    Context "Firewall Configuration" {
        It "should create OpenSSH firewall rule if missing" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "New-NetFirewallRule.*OpenSSH-Server-In-TCP"
        }

        It "should allow inbound SSH traffic on port 22" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "LocalPort\s+22"
            $scriptContent | Should -Match "Direction\s+Inbound"
            $scriptContent | Should -Match "Action\s+Allow"
        }
    }

    Context "sshd Authentication Configuration" {
        It "should disable password and keyboard-interactive authentication" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "PasswordAuthentication no"
            $scriptContent | Should -Match "KbdInteractiveAuthentication no"
            $scriptContent | Should -Match "ChallengeResponseAuthentication no"
            $scriptContent | Should -Match "Restart-Service sshd"
        }

        It "should write sshd_config without UTF-16 encoding" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match 'Set-Content -Path \$sshdConfig .*-Encoding ascii'
        }
    }

    Context "PowerShell Default Shell Configuration" {
        It "should set PowerShell as default SSH shell" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "HKLM:\\SOFTWARE\\OpenSSH"
            $scriptContent | Should -Match "DefaultShell"
            $scriptContent | Should -Match "powershell\.exe"
        }
    }

    Context "IMDSv2 Key Download Configuration" {
        It "should retrieve IMDSv2 token with short TTL" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match '"X-aws-ec2-metadata-token-ttl-seconds"\s*=\s*"300"'
            $scriptContent | Should -Match "169\.254\.169\.254/latest/api/token"
        }

        It "should use PUT method for token retrieval" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "-Method\s+PUT"
        }

        It "should fetch public key using IMDSv2 token" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "X-aws-ec2-metadata-token"
            $scriptContent | Should -Match "latest/meta-data/public-keys/0/openssh-key"
        }

        It "should save key to administrators_authorized_keys" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "administrators_authorized_keys"
            $scriptContent | Should -Match "ProgramData.*ssh"
        }
    }

    Context "ACL Configuration" {
        It "should set correct ACLs on authorized_keys file" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "icacls"
            $scriptContent | Should -Match "administrators_authorized_keys"
            $scriptContent | Should -Match "/inheritance:r"
            $scriptContent | Should -Match "Administrators:F"
            $scriptContent | Should -Match "SYSTEM:F"
        }
    }

    Context "Key Download Script ACL" {
        It "should restrict download-key.ps1 to Administrators and SYSTEM" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match 'icacls\.exe \$keyDownloadScript /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"'
        }
    }

    Context "Scheduled Task Configuration" {
        It "should create DownloadKey scheduled task" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "Register-ScheduledTask"
            $scriptContent | Should -Match "DownloadKey"
        }

        It "should run task at startup with SYSTEM privileges" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "AtStartup"
            $scriptContent | Should -Match "NT AUTHORITY\\SYSTEM"
            $scriptContent | Should -Match "RunLevel.*Highest"
        }
    }

    Context "Error Handling" {
        It "should stop on errors" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }

        It "should record a transcript next to the EC2Launch agent log" {
            $scriptContent = Get-Content -Path "./files/SetupSsh.ps1" -Raw
            $scriptContent | Should -Match "Amazon\\EC2Launch\\log\\SetupSsh-transcript\.log"
            $scriptContent | Should -Match "Start-Transcript -Path \`$transcriptPath"
            $scriptContent | Should -Match "Stop-Transcript"
        }
    }
}
