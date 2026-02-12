BeforeAll {
    $ErrorActionPreference = 'Stop'
}

Describe "InstallChoco Script Configuration" {
    
    Context "Execution Policy" {
        It "should bypass execution policy for installation" {
            $scriptContent = Get-Content -Path "./files/InstallChoco.ps1" -Raw
            $scriptContent | Should -Match "Set-ExecutionPolicy.*Bypass.*Process"
        }
    }
    
    Context "TLS Configuration" {
        It "should enable TLS 1.2 and above for secure downloads" {
            $scriptContent = Get-Content -Path "./files/InstallChoco.ps1" -Raw
            $scriptContent | Should -Match "ServicePointManager"
            $scriptContent | Should -Match "SecurityProtocol"
            $scriptContent | Should -Match "3072"
        }
    }
    
    Context "Chocolatey Installation" {
        It "should download and execute Chocolatey install script" {
            $scriptContent = Get-Content -Path "./files/InstallChoco.ps1" -Raw
            $scriptContent | Should -Match "Invoke-Expression"
            $scriptContent | Should -Match "WebClient"
            $scriptContent | Should -Match "community\.chocolatey\.org"
        }
    }
    
    Context "Chocolatey Configuration" {
        It "should enable global confirmation for packages" {
            $scriptContent = Get-Content -Path "./files/InstallChoco.ps1" -Raw
            $scriptContent | Should -Match "choco\s+feature\s+enable"
            $scriptContent | Should -Match "allowGlobalConfirmation"
        }
    }
    
    Context "Error Handling" {
        It "should stop on errors" {
            $scriptContent = Get-Content -Path "./files/InstallChoco.ps1" -Raw
            $scriptContent | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }
    }
}
