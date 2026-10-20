# Installs a separate offline neural voice. Runtime speech never downloads or
# sends text anywhere. Re-running this preserves the installed translation env.
[CmdletBinding()]
param([string]$PythonPath, [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'Babelstaarnet'))
$ErrorActionPreference='Stop'
$env:PIP_DISABLE_PIP_VERSION_CHECK='1'
Set-StrictMode -Version Latest
if (-not $PythonPath) {
    $existing=Join-Path $DataDirectory 'argos-venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $existing) { $PythonPath=$existing }
    else { $PythonPath=(Get-Command python.exe -ErrorAction Stop).Source }
}
function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Neural voice setup failed (exit $LASTEXITCODE)." }
}
$venv=Join-Path $DataDirectory 'piper-venv'
$python=Join-Path $venv 'Scripts\python.exe'
New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
if (-not (Test-Path -LiteralPath $python)) { Invoke-Checked $PythonPath @('-m', 'venv', $venv) }
Invoke-Checked $python @('-m', 'pip', 'install', '--quiet', 'piper-tts==1.8.0')
$bridge=Join-Path $PSScriptRoot 'piper_bridge.py'
if (-not (Test-Path -LiteralPath $bridge)) { $bridge=Join-Path $PSScriptRoot '..\Resources\LocalEngines\piper_bridge.py' }
$model=Join-Path $DataDirectory 'Piper\da_DK-talesyntese-medium'
Invoke-Checked $python @('-I', '-X', 'utf8', $bridge, '--model-directory', $model, '--install')
Write-Host 'Offline Danish neural speech is ready. Select Danish neural voice in Babelstaarnet.'
