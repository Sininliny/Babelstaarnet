[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build-windows.ps1')
[xml]$info = Get-Content -LiteralPath (Join-Path $projectDirectory 'Resources\Info.plist') -Raw
$version = $info.SelectSingleNode('//key[.="CFBundleShortVersionString"]/following-sibling::string[1]').InnerText
$folder = Join-Path $projectDirectory 'dist\Babelstaarnet-Windows-x64'
$archive = Join-Path $projectDirectory "dist\Babelstaarnet-$version-Windows-x64.zip"
Compress-Archive -LiteralPath $folder -DestinationPath $archive -Force
$checksum = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$checksum + '  ' + [IO.Path]::GetFileName($archive) | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
Write-Host "Windows archive: $archive"
