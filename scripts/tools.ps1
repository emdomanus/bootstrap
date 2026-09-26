$ErrorActionPreference = 'Stop'

function Resolve-Tool([string]$Name) {
    $tool = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".rokit/bin/$Name"
    if ($IsWindows) { $tool += '.exe' }
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Rokit tool: $Name" }
    return $tool
}

function Invoke-Tool([string]$Name, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Resolve-Tool $Name
    $start.WorkingDirectory = (Get-Location).Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        return [pscustomobject]@{ Code = $child.ExitCode; Output = $stdout.Result + $stderr.Result }
    } finally { $child.Dispose() }
}
