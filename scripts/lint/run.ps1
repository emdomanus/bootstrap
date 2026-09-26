[CmdletBinding()]
param([ValidateSet('stylua', 'selene')][string]$Check = 'stylua', [string[]]$Paths = @('src', 'examples', 'tests'))
. "$PSScriptRoot/../tools.ps1"
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
    $arguments = if ($Check -eq 'stylua') { @('--check') + $Paths } else { $Paths }
    $result = Invoke-Tool $Check $arguments
    Write-Output $result.Output
    if ($result.Code -ne 0) { throw "$Check failed." }
    exit 0
} finally { Pop-Location }
