[CmdletBinding()]
param(
    [ValidateSet('da', 'en', 'zh-Hans', 'zh-Hant')][string]$Source = 'da',
    [ValidateSet('da', 'en', 'zh-Hans', 'zh-Hant')][string]$Target = 'en',
    [string]$PythonPath,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'Babelstaarnet')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$env:PYTHONUTF8 = '1'
function Run([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Language setup failed with exit code $LASTEXITCODE." }
}
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$managed = Join-Path $DataDirectory 'argos-venv/Scripts/python.exe'
if ((Test-Path -LiteralPath $managed) -and -not $PythonPath) { $PythonPath = $managed }
if (-not $PythonPath) {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) { $PythonPath = & $launcher.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null }
    if (-not $PythonPath) { $PythonPath = (Get-Command python.exe -ErrorAction Stop).Source }
}
Run $PythonPath @('-c', 'import sys; assert (3,10) <= sys.version_info < (3,14) and sys.maxsize > 2**32, "Use 64-bit Python 3.10-3.13"')
$managed = Join-Path $DataDirectory 'argos-venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $managed)) { Run $PythonPath @('-m', 'venv', (Join-Path $DataDirectory 'argos-venv')) }
$helper = Join-Path $PSScriptRoot 'language_support.py'
if (-not (Test-Path -LiteralPath $helper)) { $helper = Join-Path $PSScriptRoot '../Resources/LocalEngines/language_support.py' }
$dependencies = @('-m', 'pip', 'install', 'opencc-python-reimplemented==0.1.7')
if (-not ($Source.StartsWith('zh-') -and $Target.StartsWith('zh-'))) { $dependencies += 'argostranslate>=1.10,<2' }
Run $managed $dependencies
Run $managed @('-X', 'utf8', $helper, 'install', '--data-directory', $DataDirectory, '--source', $Source, '--target', $Target)
# Validate with the same runtime route, never with a cloud service.
$env:XDG_DATA_HOME = Join-Path $DataDirectory 'Argos/data'
$env:XDG_CONFIG_HOME = Join-Path $DataDirectory 'Argos/config'
$env:XDG_CACHE_HOME = Join-Path $DataDirectory 'Argos/cache'
$env:ARGOS_PACKAGES_DIR = Join-Path $env:XDG_DATA_HOME 'argos-translate/packages'
Run $managed @('-X', 'utf8', (Join-Path (Split-Path -Parent $helper) 'argos_bridge.py'), '--check-word-model', '--source', $Source, '--target', $Target)
