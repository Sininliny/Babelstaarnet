[CmdletBinding()]
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot
$project = Join-Path $projectDirectory 'Windows\Babelstaarnet.Windows\Babelstaarnet.Windows.csproj'
$output = Join-Path $projectDirectory 'dist\Babelstaarnet-Windows-x64'
[xml]$info = Get-Content -LiteralPath (Join-Path $projectDirectory 'Resources\Info.plist') -Raw
$version = $info.SelectSingleNode('//key[.="CFBundleShortVersionString"]/following-sibling::string[1]').InnerText

# Publish into a clean directory so removed dependencies cannot enter a release.
# Resolve and check the exact target before any recursive operation.
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectDirectory 'dist')) + [IO.Path]::DirectorySeparatorChar
$resolvedOutput = [IO.Path]::GetFullPath($output)
if (-not $resolvedOutput.StartsWith($distRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Build output must be inside $distRoot"
}
if (Test-Path -LiteralPath $resolvedOutput) { Remove-Item -LiteralPath $resolvedOutput -Recurse -Force }
dotnet publish $project --configuration $Configuration --runtime win-x64 --self-contained true `
    --output $resolvedOutput "-p:Version=$version" '-p:DebugType=None' '-p:DebugSymbols=false'
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
Copy-Item -LiteralPath (Join-Path $projectDirectory 'LICENSE') -Destination $resolvedOutput
Copy-Item -LiteralPath (Join-Path $projectDirectory 'docs\WINDOWS.md') -Destination (Join-Path $resolvedOutput 'Start Here.md')
Write-Host "Windows app: $resolvedOutput\Babelstaarnet.exe"
