BeforeAll {
    $ErrorActionPreference = 'Stop'

    # Template lines without comments or blank lines, so only the HCL is compared
    function Get-TemplateCode {
        param([string]$Path)
        Get-Content -Path $Path | Where-Object { $_ -notmatch '^\s*(#|$)' }
    }
}

Describe "Packer Templates" {

    Context "Windows Server 2022 and 2025 templates stay in sync" {
        It "should differ only in the Windows version" {
            $template2022 = Get-TemplateCode -Path "./aws-windows-ssh-2022.pkr.hcl"
            $template2025 = Get-TemplateCode -Path "./aws-windows-ssh-2025.pkr.hcl"
            $template2025 -replace '2025', '2022' | Should -Be $template2022
        }

        It "should default to the matching Windows Server base AMI" {
            $template2025 = Get-Content -Path "./aws-windows-ssh-2025.pkr.hcl" -Raw
            $template2025 | Should -Match 'default = "Windows_Server-2025-English-Full-Base-\*"'
            $template2025 | Should -Match 'default = "windows-base-2025"'
        }
    }
}
