[CmdletBinding()]
param(
    [ValidateSet('tests', 'analyze', 'types')][string]$Check = 'tests',
    [string]$OutDir = '.verification/current',
    [string]$Definitions = '.verification/globalTypes.d.luau',
    [string]$Project = 'verification.project.json',
    [string]$Sourcemap = 'examples-sourcemap.json',
    [string[]]$Paths = @('src', 'examples', 'tests/typechecks/accepted.luau')
)
. "$PSScriptRoot/../tools.ps1"
$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
Push-Location $repoRoot
try {
    if ($Check -eq 'tests') {
        $result = Invoke-Tool 'lune' @('run', 'tests/lune/bootstrap.spec.luau')
        Write-Output $result.Output
        if ($result.Code -ne 0) { throw 'Behavior tests failed.' }
        exit 0
    }
    if (-not (Test-Path -LiteralPath $Definitions -PathType Leaf)) {
        throw 'Supply pinned Roblox definitions with -Definitions, or place them at .verification/globalTypes.d.luau.'
    }
    $result = Invoke-Tool 'rojo' @('sourcemap', $Project, '--output', $Sourcemap)
    if ($result.Code -ne 0) { throw $result.Output }
    $argsList = @('analyze', '--flag:LuauSolverV2=true', "--sourcemap=$Sourcemap", "--definitions:@roblox=$((Resolve-Path $Definitions).Path)")
    if ($Check -eq 'types') { $Paths = @('src', 'examples', 'tests/typechecks/accepted.luau') }
    $result = Invoke-Tool 'luau-lsp' ($argsList + $Paths)
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $result.Output | Set-Content (Join-Path $OutDir 'analyze.txt') -Encoding utf8
    $counts = @{}
    foreach ($line in ($result.Output -split '\r?\n')) {
        if ($line -match '^(.+?)(?: \[game/.*?\])?\(\d+,\d+\):') {
            $key = $Matches[1].Replace('\', '/')
            if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }
            $counts[$key]++
        }
    }
    $counts | ConvertTo-Json | Set-Content (Join-Path $OutDir 'diagnostics.json') -Encoding utf8
    Write-Output $result.Output
    if ($result.Code -ne 0) { throw 'Analyzer failed; see the saved diagnostic capture.' }
    if ($Check -eq 'types') {
        $fixture = 'tests/typechecks/rejected.luau'
        $negative = Invoke-Tool 'luau-lsp' ($argsList + @($fixture))
        $negative.Output | Set-Content (Join-Path $OutDir 'rejected.txt') -Encoding utf8
        $expected = @{}
        $lines = Get-Content -LiteralPath $fixture
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '-- reject$') { $expected[$i + 1] = $true }
        }
        $total = $expected.Count
        if ($total -eq 0 -or $negative.Code -eq 0) { throw 'Negative type fixtures did not reject.' }
        foreach ($line in ($negative.Output -split '\r?\n')) {
            if ($line -match '^.*rejected\.luau(?: \[game/.*?\])?\((\d+),\d+\): TypeError:') {
                $number = [int]$Matches[1]
                if (-not $expected.ContainsKey($number)) { throw "Unexpected type failure: $line" }
                $expected.Remove($number)
            } elseif ($line -match 'TypeError:|SyntaxError:') { throw "Unexpected diagnostic: $line" }
        }
        if ($expected.Count -ne 0) { throw "Missing rejections at lines: $($expected.Keys -join ', ')" }
        Write-Output "PASS $total negative public type fixtures."
    }
    exit 0
} finally { Pop-Location }
