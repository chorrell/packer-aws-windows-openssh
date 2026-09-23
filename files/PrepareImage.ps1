$ErrorActionPreference = 'Stop'

Write-Output "Cleaning up keys"
$openSSHAuthorizedKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'

# Retry deleting the file with delays to allow SSH connection to close
$maxRetries = 5
$retryCount = 0
$deleted = $false

while ($retryCount -lt $maxRetries -and -not $deleted) {
  try {
    Remove-Item -Recurse -Force -Path $openSSHAuthorizedKeys -ErrorAction Stop
    $deleted = $true
    Write-Output "Successfully deleted authorized_keys file"
  } catch {
    $retryCount++
    if ($retryCount -lt $maxRetries) {
      Write-Output "File is locked, retrying in 5 seconds... (attempt $retryCount/$maxRetries)"
      Start-Sleep -Seconds 5
    } else {
      Write-Output "Could not delete authorized_keys file after $maxRetries attempts, continuing anyway (Sysprep will clean up)"
    }
  }
}

# Remove host keys generated during the build so every instance launched from
# the AMI gets unique host keys; sshd regenerates missing keys on first start
Write-Output "Removing SSH host keys"
Remove-Item -Force -Path (Join-Path $env:ProgramData 'ssh\ssh_host_*')

# Make sure task is enabled
Enable-ScheduledTask "DownloadKey"

Write-Output "Running Sysprep"
& "$Env:Programfiles\Amazon\EC2Launch\ec2launch.exe" sysprep
