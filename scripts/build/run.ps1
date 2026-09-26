. "$PSScriptRoot/../tools.ps1"
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
    New-Item -ItemType Directory -Force .verification | Out-Null
    foreach ($arguments in @(
        @('sourcemap', 'default.project.json', '--output', 'sourcemap.json'),
        @('sourcemap', 'verification.project.json', '--output', 'examples-sourcemap.json'),
        @('build', 'default.project.json', '--output', '.verification/bootstrap.rbxm')
    )) {
        $result = Invoke-Tool 'rojo' $arguments
        Write-Output $result.Output
        if ($result.Code -ne 0) { throw 'Rojo build failed.' }
    }
    exit 0
} finally { Pop-Location }
