# Installs the optional offline Danish -> English translator for Windows.
# Downloads happen only during setup. The reader never sends text to a service.
[CmdletBinding()]
param(
    [string]$PythonPath,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'Babelstaarnet')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'This installer requires Windows.'
}

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable exited with code $LASTEXITCODE." }
}

if (-not $PythonPath) {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        $PythonPath = & $launcher.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -ne 0) { $PythonPath = $null }
    }
    if (-not $PythonPath) {
        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($python -and $python.Source -notlike '*\WindowsApps\*') { $PythonPath = $python.Source }
    }
}
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw 'Install 64-bit Python 3.12 from python.org, then run this script again (or pass -PythonPath).'
}
Invoke-Checked $PythonPath @('-c', 'import sys; assert (3, 10) <= sys.version_info < (3, 14), "Use Python 3.10-3.13 (3.12 recommended)"; assert sys.maxsize > 2**32, "Use 64-bit Python"')

$bundledBridge = Join-Path $PSScriptRoot 'argos_bridge.py'
$sourceBridge = Join-Path $PSScriptRoot '..\Resources\LocalEngines\argos_bridge.py'
$bridge = if (Test-Path -LiteralPath $bundledBridge) { $bundledBridge } else { $sourceBridge }
if (-not (Test-Path -LiteralPath $bridge)) { throw "Argos bridge not found: $bridge" }

$venv = Join-Path $DataDirectory 'argos-venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:XDG_DATA_HOME = Join-Path $DataDirectory 'Argos\data'
$env:XDG_CONFIG_HOME = Join-Path $DataDirectory 'Argos\config'
$env:XDG_CACHE_HOME = Join-Path $DataDirectory 'Argos\cache'
$env:ARGOS_CHUNK_TYPE = 'MINISBD'
$env:ARGOS_DEVICE_TYPE = 'cpu'
$env:ARGOS_MODEL_PROVIDER = 'OPENNMT'
$env:ARGOS_PACKAGE_INDEX = 'https://raw.githubusercontent.com/argosopentech/argospm-index/main/'
$env:ARGOS_PACKAGES_DIR = Join-Path $env:XDG_DATA_HOME 'argos-translate\packages'
foreach ($directory in @($DataDirectory, $env:XDG_DATA_HOME, $env:XDG_CONFIG_HOME, $env:XDG_CACHE_HOME)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
if (-not (Test-Path -LiteralPath $venvPython)) {
    Invoke-Checked $PythonPath @('-m', 'venv', $venv)
}
Invoke-Checked $venvPython @('-m', 'pip', 'install', '--quiet', '--upgrade', 'pip')
Invoke-Checked $venvPython @('-m', 'pip', 'install', '--quiet', 'argostranslate>=1.10,<2')
Invoke-Checked $venvPython @('-X', 'utf8', $bridge, '--install-word-model', '--source', 'da', '--target', 'en')
# Validate the same lightweight model used by the reader, including inference.
# Re-running setup no longer imports the unused full sentence-processing stack.
Invoke-Checked $venvPython @('-X', 'utf8', $bridge, '--check-word-model', '--source', 'da', '--target', 'en')
Write-Host 'Offline translation is ready. Start translating from the Babelstaarnet tray icon.'
