$ErrorActionPreference = 'Stop'

Write-Output "Cleaning up keys"
$openSSHAuthorizedKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
Remove-Item -Recurse -Force -Path $openSSHAuthorizedKeys

# Make sure task is enabled
Enable-ScheduledTask "DownloadKey"

Write-Output "Running Sysprep"
& "$Env:Programfiles\Amazon\EC2Launch\ec2launch.exe" sysprep
