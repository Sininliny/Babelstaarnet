[CmdletBinding()]
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot

if (-not $env:BABELSTAARNET_TEST_PYTHON) {
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python -and $python.Source -notlike '*\WindowsApps\*') {
        $env:BABELSTAARNET_TEST_PYTHON = $python.Source
    } else {
        throw 'Python 3 is required for the worker protocol checks. Set BABELSTAARNET_TEST_PYTHON to its full path.'
    }
}
$checksProject = Join-Path $projectDirectory 'Tests\WindowsChecks\WindowsChecks.csproj'
& $env:BABELSTAARNET_TEST_PYTHON (Join-Path $PSScriptRoot 'sync-windows-language.py') --check
if ($LASTEXITCODE -ne 0) { throw 'The Windows Danish language pack differs from the Mac source.' }
# A single build node also works in restricted Windows environments where
# MSBuild's worker-node IPC is unavailable. Keep compile failures separate
# from runtime failures in both local output and CI logs.
dotnet build $checksProject --configuration $Configuration -m:1 -nr:false
if ($LASTEXITCODE -ne 0) { throw 'Windows check build failed.' }
dotnet run --project $checksProject --configuration $Configuration --no-build --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Windows checks failed.' }

$application = Join-Path $projectDirectory "Windows\Babelstaarnet.Windows\bin\$Configuration\net10.0-windows10.0.19041.0\Babelstaarnet.exe"
$check = Start-Process -FilePath $application -ArgumentList '--check' -PassThru -Wait -WindowStyle Hidden
if ($check.ExitCode -ne 0) { throw "Windows app smoke check failed with exit code $($check.ExitCode)." }
