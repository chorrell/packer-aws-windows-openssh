BeforeAll {
    $ErrorActionPreference = 'Stop'
}

Describe "PrepareImage Script Configuration" {
    
    Context "Key Cleanup" {
        It "should remove administrators_authorized_keys file" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "Remove-Item"
            $scriptContent | Should -Match "administrators_authorized_keys"
        }
        
        It "should handle file locks with retry logic" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "maxRetries\s*=\s*5"
            $scriptContent | Should -Match "Start-Sleep.*5"
        }
        
        It "should continue if cleanup fails after retries" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "continuing anyway"
        }
    }
    
    Context "Scheduled Task Management" {
        It "should enable DownloadKey scheduled task" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "Enable-ScheduledTask"
            $scriptContent | Should -Match "DownloadKey"
        }
    }
    
    Context "Sysprep Configuration" {
        It "should run EC2Launch Sysprep" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "ec2launch\.exe"
            $scriptContent | Should -Match "sysprep"
        }
        
        It "should use correct EC2Launch path" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match "Amazon\\EC2Launch"
        }
    }
    
    Context "Error Handling" {
        It "should stop on errors" {
            $scriptContent = Get-Content -Path "./files/PrepareImage.ps1" -Raw
            $scriptContent | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }
    }
}
