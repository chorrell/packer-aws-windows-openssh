# Runs PSScriptAnalyzer with the repository settings. Used by the
# PSScriptAnalyzer workflow and the psscriptanalyzer pre-commit hook.
[CmdletBinding()]
param(
    # Files or directories to analyze; defaults to the whole repository.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$version = '1.25.0'
$repoRoot = Split-Path -Parent $PSScriptRoot
$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
if (-not $Path) {
    $Path = @($repoRoot)
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object Version -eq $version)) {
    Install-PSResource -Name PSScriptAnalyzer -Version $version -TrustRepository -Quiet
}
Import-Module -Name PSScriptAnalyzer -RequiredVersion $version

$results = @($Path | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Settings $settings })

if ($env:GITHUB_ACTIONS -eq 'true') {
    # Workflow commands put each finding inline on the pull request diff.
    # See: https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions
    foreach ($result in $results) {
        $level = if ($result.Severity -eq 'Warning') { 'warning' } elseif ($result.Severity -eq 'Information') { 'notice' } else { 'error' }
        $file = [System.IO.Path]::GetRelativePath($repoRoot, $result.ScriptPath)
        $message = $result.Message -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A'
        Write-Output "::${level} file=${file},line=$($result.Line),col=$($result.Column),title=$($result.RuleName)::${message}"
    }
}

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 200 | Write-Output
    Write-Output "PSScriptAnalyzer found $($results.Count) issue(s)."
    exit 1
}

Write-Output 'PSScriptAnalyzer found no issues.'
