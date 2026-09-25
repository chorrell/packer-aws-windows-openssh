@{
    # Shared by CI (.github/workflows/PSScriptAnalyzer.yml), the pre-commit
    # hook, and editors (VS Code picks this file up from the repository root).
    Severity     = @('Error', 'Warning')
    ExcludeRules = @()
}
