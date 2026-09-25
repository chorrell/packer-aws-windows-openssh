<powershell>
# Don't display progress bars
# See: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.3#progresspreference
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Record everything this script does (including the error that stops it) next
# to EC2Launch v2's agent.log, so a failed build can be diagnosed from a fixed
# path. PrepareImage.ps1 deletes it so it isn't baked into the AMI. Native
# command output is piped to Write-Output below so the transcript captures it.
$transcriptPath = Join-Path $env:ProgramData 'Amazon\EC2Launch\log\SetupSsh-transcript.log'
Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader

# Install OpenSSH using Add-WindowsCapability
# See: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell#install-openssh-for-windows

Write-Host 'Installing and starting ssh-agent'
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent

Write-Host 'Installing and starting sshd'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# Only allow public key authentication. Prepend so the settings apply globally
# (the default sshd_config ends with a Match block) and take precedence, since
# sshd uses the first value it finds. sshd_config must not be UTF-16 encoded.
# Older OpenSSH (as shipped with Windows Server 2022) re-enables
# keyboard-interactive when ChallengeResponseAuthentication is yes (the
# default); newer versions treat it as an alias, so set both.
$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$authSettings = @('PasswordAuthentication no', 'KbdInteractiveAuthentication no', 'ChallengeResponseAuthentication no')
Set-Content -Path $sshdConfig -Value ($authSettings + (Get-Content -Path $sshdConfig)) -Encoding ascii
Restart-Service sshd

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}

# Set default shell to Powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

$keyDownloadScript = Join-Path $env:ProgramData 'ssh\download-key.ps1'

@'
# Download private key to $env:ProgramData\ssh\administrators_authorized_keys using IMDSv2
$openSSHAuthorizedKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'

# Retrieve a short-lived (5 minute) IMDSv2 session token
# See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
$tokenUrl = "http://169.254.169.254/latest/api/token"
$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "300"} -Method PUT -Uri $tokenUrl

# Retrieve SSH public key using the IMDSv2 token
$keyUrl = "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"
Invoke-WebRequest -Headers @{"X-aws-ec2-metadata-token" = $token} -Uri $keyUrl -OutFile $openSSHAuthorizedKeys

# Ensure ACL for administrators_authorized_keys is correct
# See https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration#authorizedkeysfile
icacls.exe $openSSHAuthorizedKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
'@ | Out-File $keyDownloadScript

# The task below runs this script as SYSTEM at every boot, so don't rely on the
# folder's inherited ACL: only Administrators and SYSTEM may read or change it
icacls.exe $keyDownloadScript /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Write-Output

# Create Task
$taskName = "DownloadKey"
$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -File ""$keyDownloadScript"""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName $taskName -Description $taskName

# Fetch key via $keyDownloadScript
& Powershell.exe -ExecutionPolicy Bypass -File $keyDownloadScript | Write-Output

Stop-Transcript

</powershell>
